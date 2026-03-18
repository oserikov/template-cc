#!/usr/bin/env bash
# Containerized Claude Code experiment runner.
#
# Runs one Claude Code agent per task in an isolated devcontainer.
# Each task gets a git worktree, a rendered prompt, and condition-gated data.
#
# Usage:
#   ./experiment/run_experiment.sh                          # defaults
#   ./experiment/run_experiment.sh --conditions cond1,cond2 # specific conditions
#   ./experiment/run_experiment.sh --dry-run                # validate setup
#   BUDGET_USD=100 ./experiment/run_experiment.sh           # custom budget
#
# Prerequisites:
#   Docker running, devcontainer CLI, Claude Code auth in ~/.claude.json
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EXPERIMENT_DIR="$REPO_ROOT/experiment"
DEVCONTAINER_DIR="$EXPERIMENT_DIR/.devcontainer"
DATA_DIR="$EXPERIMENT_DIR/data"
RESULTS_DIR="$EXPERIMENT_DIR/results"
TRACES_DIR="$EXPERIMENT_DIR/traces"
LOGS_DIR="$EXPERIMENT_DIR/logs"
TEMPLATE="$EXPERIMENT_DIR/AGENT_PROMPT.md.template"
WORKTREE_ROOT="${WORKTREE_ROOT:-/tmp/experiment-worktrees}"

BUDGET_USD="${BUDGET_USD:-200}"
N=1  # parallel agents per batch
AGENT_TIMEOUT="${AGENT_TIMEOUT:-600}"
MAX_TURNS="${MAX_TURNS:-30}"
MODEL="claude-opus-4-6"
DRY_RUN=false

# Override CONDITIONS in your project before sourcing, or use --conditions flag.
if [ -z "${CONDITIONS+x}" ]; then
  CONDITIONS=("default")
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --n) N="$2"; shift 2 ;;
    --budget) BUDGET_USD="$2"; shift 2 ;;
    --timeout) AGENT_TIMEOUT="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    --conditions) IFS=',' read -ra CONDITIONS <<< "$2"; shift 2 ;;
    *) echo "Unknown flag: $1" >&2; exit 1 ;;
  esac
done

mkdir -p "$LOGS_DIR"

# ── Per-condition state file (fcntl-locked for concurrent safety) ─────────────
CONDITION_TAG="${CONDITIONS[*]}"
CONDITION_TAG="${CONDITION_TAG// /_}"
STATE_FILE="$EXPERIMENT_DIR/state_${CONDITION_TAG}.json"

if [ ! -f "$STATE_FILE" ]; then
  echo '{"total_spent_usd": 0, "runs_completed": 0, "runs": []}' > "$STATE_FILE"
fi

get_spent() {
  python3 -c "import json; print(json.load(open('$STATE_FILE'))['total_spent_usd'])"
}

update_state() {
  local session_cost="$1" condition="$2" task_id="$3"
  python3 -c "
import json, fcntl
with open('$STATE_FILE', 'r+') as f:
    fcntl.flock(f, fcntl.LOCK_EX)
    state = json.load(f)
    state['total_spent_usd'] = round(state['total_spent_usd'] + float('$session_cost'), 6)
    state['runs_completed'] += 1
    state['runs'].append({'condition': '$condition', 'task_id': '$task_id', 'cost': float('$session_cost')})
    f.seek(0)
    f.truncate()
    json.dump(state, f, indent=2)
    fcntl.flock(f, fcntl.LOCK_UN)
"
}

# ── Claude auth detection ─────────────────────────────────────────────────────
CLAUDE_AUTH_MODE=$(python3 -c "
import json, sys, os
d = json.load(open(os.path.expanduser('~/.claude.json')))
if d.get('primaryApiKey'):
    print('apikey')
elif os.path.exists(os.path.expanduser('~/.claude/.credentials.json')):
    print('oauth')
else:
    sys.exit('ERROR: no primaryApiKey or OAuth credentials found')
")

# ── Task list ─────────────────────────────────────────────────────────────────
# Override load_tasks() in your project to return task IDs.
# Default: reads TASKS_FILE (one task ID per line).
TASKS_FILE="${TASKS_FILE:-$EXPERIMENT_DIR/tasks.txt}"

load_tasks() {
  if [ -f "$TASKS_FILE" ]; then
    cat "$TASKS_FILE"
  else
    echo "ERROR: No tasks file at $TASKS_FILE. Create it or override load_tasks()." >&2
    exit 1
  fi
}

NUM_TASKS=$(load_tasks | wc -l)

# ── Prompt rendering ──────────────────────────────────────────────────────────
# Override render_prompt() in your project for custom prompt logic.
# Default: reads AGENT_PROMPT.md.template, substitutes {{TASK_ID}} and {{CONDITION}}.
render_prompt() {
  local condition="$1" task_id="$2"
  if [ ! -f "$TEMPLATE" ]; then
    echo "ERROR: No prompt template at $TEMPLATE" >&2
    exit 1
  fi
  local template
  template=$(<"$TEMPLATE")
  template="${template//\{\{TASK_ID\}\}/$task_id}"
  template="${template//\{\{CONDITION\}\}/$condition}"
  echo "$template"
}

# ── Condition data path ───────────────────────────────────────────────────────
# Override get_data_dir() to customize which files are mounted per condition.
# Default: $DATA_DIR/$condition/
get_data_dir() {
  local condition="$1"
  echo "$DATA_DIR/$condition"
}

echo "=== Containerized Experiment Runner ==="
echo "Conditions: ${CONDITIONS[*]}"
echo "Tasks:      $NUM_TASKS"
echo "Parallel:   $N"
echo "Budget:     \$$BUDGET_USD"
echo "Timeout:    ${AGENT_TIMEOUT}s"
echo "Max turns:  $MAX_TURNS"
echo "Model:      $MODEL"
echo "Auth:       $CLAUDE_AUTH_MODE"
echo "Total runs: $((${#CONDITIONS[@]} * NUM_TASKS))"
echo

if $DRY_RUN; then
  echo "[DRY RUN] Validating setup..."
  echo "  Template:  $TEMPLATE ($(wc -c < "$TEMPLATE" 2>/dev/null || echo 'MISSING') bytes)"
  echo "  Tasks:     $TASKS_FILE ($NUM_TASKS tasks)"
  for cond in "${CONDITIONS[@]}"; do
    local_data=$(get_data_dir "$cond")
    echo "  Condition $cond: $(ls "$local_data" 2>/dev/null | tr '\n' ' ')"
  done
  echo "[DRY RUN] Would run $((${#CONDITIONS[@]} * NUM_TASKS)) agent sessions."
  exit 0
fi

# ── Run a single agent ────────────────────────────────────────────────────────
run_agent() {
  local condition="$1" task_id="$2"
  local exp_name="${condition}-${task_id}"
  local trace_dir="$TRACES_DIR/$condition/$task_id"
  local result_file="$RESULTS_DIR/$condition/${task_id}.jsonl"
  local log_file="$LOGS_DIR/${exp_name}.jsonl"

  mkdir -p "$trace_dir/projects" "$trace_dir/debug" "$(dirname "$result_file")"

  # Skip if already completed
  if [ -f "$result_file" ] && [ -s "$result_file" ]; then
    echo "   [$exp_name] Already completed, skipping."
    return 0
  fi

  # Budget check
  local spent
  spent=$(get_spent)
  if ! python3 -c "import sys; sys.exit(0 if float('$spent') < float('$BUDGET_USD') else 1)" 2>/dev/null; then
    echo "   [$exp_name] Budget exhausted (\$$spent >= \$$BUDGET_USD). Skipping."
    return 1
  fi

  # Render prompt
  local rendered_prompt
  rendered_prompt=$(render_prompt "$condition" "$task_id")
  local prompt_file="$LOGS_DIR/${exp_name}_prompt.md"
  echo "$rendered_prompt" > "$prompt_file"

  echo "   [$exp_name] Starting agent..."

  # Create worktree for this run
  local worktree="$WORKTREE_ROOT/$exp_name"
  if [ -d "$worktree" ]; then
    git -C "$REPO_ROOT" worktree remove --force "$worktree" 2>/dev/null || rm -rf "$worktree"
  fi
  git -C "$REPO_ROOT" worktree add --detach "$worktree" HEAD 2>/dev/null

  # Copy devcontainer config into worktree
  mkdir -p "$worktree/.devcontainer"
  cp "$DEVCONTAINER_DIR/Dockerfile" "$worktree/.devcontainer/"
  cp "$DEVCONTAINER_DIR/devcontainer.json" "$worktree/.devcontainer/"
  cp "$DEVCONTAINER_DIR/ensure-claude-perm-skip.sh" "$worktree/.devcontainer/"
  cp "$DEVCONTAINER_DIR/init-firewall.sh" "$worktree/.devcontainer/"

  # Start devcontainer
  TRACE_DIR="$trace_dir" \
  EXPERIMENT_NAME="$exp_name" \
  devcontainer up \
    --workspace-folder "$worktree" \
    --remove-existing-container \
    > "$LOGS_DIR/${exp_name}_devcontainer.log" 2>&1

  # Find container ID
  local cid
  cid=$(docker ps --format '{{.ID}} {{.Label "devcontainer.local_folder"}}' \
    | awk -v wf="$worktree" '$2==wf {print $1; exit}')

  if [ -z "$cid" ]; then
    echo "   [$exp_name] ERROR: Container not found."
    return 1
  fi

  # Inject Claude credentials
  if [ "$CLAUDE_AUTH_MODE" = "oauth" ]; then
    (cd "$HOME/.claude" && tar cf - .credentials.json) | \
      docker exec -i -u root "$cid" tar xf - -C /home/node/.claude/
    python3 -c "import json; print(json.dumps(json.load(open('$HOME/.claude.json'))['oauthAccount']))" | \
      docker exec -i -u root "$cid" python3 -c "
import json, sys
oauth = json.load(sys.stdin)
path = '/home/node/.claude/.claude.json'
try: d = json.load(open(path))
except: d = {}
d['oauthAccount'] = oauth
json.dump(d, open(path, 'w'))
"
  else
    local api_key
    api_key=$(python3 -c "import json; print(json.load(open('$HOME/.claude.json'))['primaryApiKey'])")
    docker exec -u root "$cid" bash -c "
      python3 -c \"
import json; path='/home/node/.claude/.claude.json'
try: d=json.load(open(path))
except: d={}
d['primaryApiKey']='$api_key'
json.dump(d,open(path,'w'))
\"
    "
  fi

  # Copy condition-gated data into container
  local data_dir
  data_dir=$(get_data_dir "$condition")
  if [ -d "$data_dir" ]; then
    docker exec -u root "$cid" mkdir -p /workspace/data
    docker cp "$data_dir/." "$cid:/workspace/data/"
  fi
  docker exec -u root "$cid" chown -R node:node /workspace

  # Copy Claude settings
  (cd "$HOME/.claude" && tar cf - settings.json 2>/dev/null) | \
    docker exec -i -u root "$cid" tar xf - -C /home/node/.claude/ 2>/dev/null || true
  docker exec -u root "$cid" chown -R node:node /home/node/.claude

  # Run agent
  timeout "$AGENT_TIMEOUT" \
    docker exec -t -u node \
      -e CLAUDE_CODE_MAX_OUTPUT_TOKENS=200000 \
      -e CLAUDECODE= \
      "$cid" bash -lc \
      "claude --dangerously-skip-permissions --verbose --output-format stream-json --max-turns $MAX_TURNS \
              --model $MODEL \
              -p $(printf '%q' "$rendered_prompt")" \
    > "$log_file" 2>&1 || true

  # Collect result: copy the full session log as the result
  cp "$log_file" "$result_file"

  # Extract cost from stream-json logs
  local cost="0"
  cost=$(python3 -c "
import json
total = 0
for line in open('$log_file'):
    line = line.strip()
    if not line: continue
    try:
        obj = json.loads(line)
        if 'cost_usd' in obj:
            total = obj['cost_usd']
        elif isinstance(obj, dict) and obj.get('type') == 'result' and 'cost_usd' in obj:
            total = obj['cost_usd']
    except: pass
print(round(total, 6))
" 2>/dev/null || echo "0")
  echo "   [$exp_name] Cost: \$$cost"

  update_state "$cost" "$condition" "$task_id"

  # Cleanup container; keep worktree for inspection
  docker rm -f "$cid" >/dev/null 2>&1 || true
  docker volume prune -f >/dev/null 2>&1 || true

  # Remove worktree
  git -C "$REPO_ROOT" worktree remove --force "$worktree" 2>/dev/null || rm -rf "$worktree"

  return 0
}

# ── Main execution loop ───────────────────────────────────────────────────────
echo "Starting experiment..."
TOTAL_RUNS=0
FAILED_RUNS=0

for condition in "${CONDITIONS[@]}"; do
  echo "── Condition: $condition ──────────────────────────────────"
  mkdir -p "$RESULTS_DIR/$condition"

  batch_pids=()
  while IFS= read -r task_id; do
    [ -z "$task_id" ] && continue
    run_agent "$condition" "$task_id" &
    batch_pids+=($!)

    if [ ${#batch_pids[@]} -ge $N ]; then
      for pid in "${batch_pids[@]}"; do
        wait "$pid" || FAILED_RUNS=$((FAILED_RUNS + 1))
        TOTAL_RUNS=$((TOTAL_RUNS + 1))
      done
      batch_pids=()
    fi
  done < <(load_tasks)

  # Wait for remaining batch
  for pid in "${batch_pids[@]}"; do
    wait "$pid" || FAILED_RUNS=$((FAILED_RUNS + 1))
    TOTAL_RUNS=$((TOTAL_RUNS + 1))
  done
done

# Final worktree cleanup
git -C "$REPO_ROOT" worktree prune 2>/dev/null

echo
echo "=== Experiment Complete ==="
echo "Total runs:  $TOTAL_RUNS"
echo "Failed runs: $FAILED_RUNS"
echo "Total cost:  \$$(get_spent)"
echo
echo "Results in: $RESULTS_DIR/"
