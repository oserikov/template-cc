# Containerized Claude Code Experiments Guide

This guide explains how to run isolated Claude Code agents in Docker containers for reproducible experiments. Each agent gets a firewalled container, condition-gated data, and full tool access. The host collects session traces and results after each run.

---

## 1) What this setup gives you

- **Agent isolation**: each task runs in its own Docker container with no network access beyond the Anthropic API.
- **Full tool access inside the container**: bash, Python, file I/O, grep — agents can write and run arbitrary code.
- **Condition-gated data**: each container receives only the resource files for its experimental condition.
- **Persistent traces on host**: full session logs (JSONL) survive container teardown.
- **Resumable runs**: the orchestrator skips completed tasks on re-run.
- **Concurrent safety**: per-condition state files with file locking.
- **No host-side mutation**: agents cannot modify your repository or reach the internet.

---

## 2) Architecture

```
Host (orchestrator)
  │
  ├── For each (condition × task):
  │     │
  │     ├── Create git worktree from HEAD
  │     ├── Copy .devcontainer/ into worktree
  │     ├── devcontainer up --workspace-folder $worktree
  │     ├── Inject Claude credentials into container
  │     ├── Copy condition data into /workspace/data/
  │     ├── chown -R node:node /workspace
  │     ├── docker exec claude --dangerously-skip-permissions \
  │     │     --output-format stream-json -p "$rendered_prompt"
  │     ├── Collect JSONL session log → experiment/results/
  │     ├── Extract cost from JSONL → state file
  │     ├── docker rm -f container
  │     ├── docker volume prune -f
  │     └── git worktree remove
  │
  └── Final: git worktree prune
```

Key properties:
- Each container is **ephemeral** — created for one task, destroyed after.
- The git **worktree** gives each container a unique `devcontainer.local_folder` label, enabling parallel execution without label collisions.
- **Traces persist** because session logs are copied to the host before container teardown.

---

## 3) Prerequisites

- Docker running
- `devcontainer` CLI: `npm install -g @devcontainers/cli`
- Claude Code CLI with auth configured (`~/.claude.json` with `primaryApiKey` or OAuth credentials in `~/.claude/.credentials.json`)
- Git (for worktrees)
- Python 3 (for cost tracking and prompt rendering)

---

## 4) Quick start

### 4.1 Define your tasks

Create `experiment/tasks.txt` with one task ID per line:

```
sentence_0
sentence_1
sentence_2
```

### 4.2 Place condition-gated data

```bash
mkdir -p experiment/data/my_condition
cp my_resource_file.txt experiment/data/my_condition/
```

Each condition gets its own directory. Only the files in that directory are mounted into the container.

### 4.3 Customize the prompt template

Edit `experiment/AGENT_PROMPT.md.template`. Available placeholders:
- `{{TASK_ID}}` — replaced with the current task ID
- `{{CONDITION}}` — replaced with the current condition name

### 4.4 Run

```bash
./experiment/run_experiment.sh --conditions my_condition --budget 50
```

### 4.5 Results

Session logs land in `experiment/results/{condition}/{task_id}.jsonl`. These are Claude Code's `--output-format stream-json` output — every tool call, every reasoning step, every result.

---

## 5) Parallel execution

Run two conditions simultaneously in separate terminals:

```bash
# Terminal 1:
./experiment/run_experiment.sh --conditions condition_a --n 1 --budget 100

# Terminal 2:
./experiment/run_experiment.sh --conditions condition_b --n 1 --budget 100
```

This is safe because:
- Each condition writes to its own state file (`state_condition_a.json`, `state_condition_b.json`)
- Each container gets a unique worktree path (`/tmp/experiment-worktrees/condition_a-task_0`)
- State updates use `fcntl` file locking

You can also batch tasks within a condition using `--n N` to run N containers concurrently per batch.

---

## 6) Customization points

The orchestrator defines three bash functions you can override by editing `run_experiment.sh` or sourcing a project-specific config:

### `load_tasks`
Returns task IDs, one per line. Default reads `experiment/tasks.txt`.

### `render_prompt condition task_id`
Returns the rendered prompt string. Default reads `AGENT_PROMPT.md.template` and substitutes `{{TASK_ID}}` and `{{CONDITION}}`.

Override this to inject task-specific data (source sentences, context, instructions) into the prompt.

### `get_data_dir condition`
Returns the path to condition-gated data. Default returns `experiment/data/$condition/`.

Override this to dynamically assemble resources per condition.

---

## 7) What happens inside the container

The agent runs as user `node` in `/workspace/`. It has:

- **Tool access**: bash, Python, file read/write, grep — unrestricted within the container
- **No network**: iptables firewall blocks everything except the Anthropic API, GitHub, PyPI, and npm
- **No test answers**: only the condition-specific resource files are mounted
- **Bypass permissions**: `--dangerously-skip-permissions` mode, no tool approval prompts
- **Time budget**: the prompt template instructs agents to write results by turn 12 out of 30

The agent's job is to read the resource files, devise a strategy, and write its output to `/workspace/result.json` (or whatever your prompt specifies).

---

## 8) Critical gotchas

### CLAUDECODE environment variable
Claude Code refuses to start inside another Claude Code session (nesting detection). The orchestrator clears this with `-e CLAUDECODE=` on the `docker exec` call. If you run the orchestrator from a Claude Code agent session (e.g., via agent teammates), this is essential.

### /workspace permissions
The devcontainer creates `/workspace` owned by uid 1000, but the `node` user may have a different uid. The orchestrator runs `chown -R node:node /workspace` after copying data. If you skip this, agents will spend all their turns hitting permission errors trying to write `result.json`.

### Docker Hub rate limits
Long experiments (50+ containers) hit Docker Hub pull rate limits. Solutions:
- Pre-pull `node:20-bookworm` once before the run
- Use a mirror: `public.ecr.aws/docker/library/node:20-bookworm`
- Tag locally after first pull so subsequent containers use the cache

### Agent time management
Without explicit time-budget instructions, agents will research indefinitely and never commit to an answer. The default prompt template enforces a phased approach:
- Turns 1–8: research
- Turns 9–12: write result file (mandatory)
- Remaining: refine

This was learned the hard way: 80% of initial experiment runs timed out without producing output before the phased prompt was introduced.

### State file race conditions
Never share a state file between concurrent orchestrator instances. The per-condition naming (`state_{condition}.json`) with `fcntl` locking prevents this. If you see false "budget exhausted" errors, check that two instances aren't writing to the same state file.

### OAuth token expiration
For long runs (4+ hours), OAuth tokens may expire. If a container fails with auth errors:
1. Re-authenticate on the host: `claude` (interactive, triggers OAuth refresh)
2. The orchestrator re-injects credentials for each new container, so subsequent runs pick up the refreshed token

---

## 9) Cost and time

- **Per agent session**: ~$1–3 (Claude Opus 4.6, ~30 turns)
- **Per session wall clock**: ~5–10 minutes
- **50 tasks sequential**: ~4–8 hours per condition
- **Budget recommendation**: $200 per 50-task condition (generous margin)

The orchestrator tracks cumulative cost in the state file and skips remaining tasks when the budget is exhausted.

---

## 10) Collecting and analyzing results

Session logs are JSONL files. Each line is a JSON object. Key event types:

```python
import json

for line in open("experiment/results/my_condition/task_0.jsonl"):
    obj = json.loads(line)

    if obj.get("type") == "assistant":
        # Agent reasoning and tool calls
        for block in obj["message"]["content"]:
            if block["type"] == "text":
                print("REASONING:", block["text"][:100])
            elif block["type"] == "tool_use":
                print(f"TOOL: {block['name']}({block['input']})")

    elif obj.get("type") == "result":
        # Session summary
        print(f"Cost: ${obj['total_cost_usd']:.4f}")
        print(f"Turns: {obj['num_turns']}")
        print(f"Stop reason: {obj['subtype']}")
```

If your agents write `/workspace/result.json`, you can also `docker cp` it out before container teardown — the orchestrator does not do this by default since the JSONL log contains the full session including any file writes.

---

## 11) Teardown

The orchestrator cleans up containers and worktrees after each task. For manual cleanup after interrupted runs:

```bash
# Kill all experiment containers
docker ps --format '{{.ID}} {{.Label "devcontainer.local_folder"}}' \
  | grep experiment-worktrees | awk '{print $1}' \
  | xargs -r docker rm -f

# Prune worktrees
git worktree prune

# Prune Docker volumes
docker volume prune -f

# Remove temp worktree directory
rm -rf /tmp/experiment-worktrees
```

Session logs in `experiment/results/` and `experiment/logs/` survive all of the above — they live on the host, not in containers.

---

## 12) Checklist before a long run

- [ ] Docker running, `devcontainer` CLI installed
- [ ] Claude auth working (`claude -p "say hi"` succeeds on host)
- [ ] `experiment/tasks.txt` populated
- [ ] `experiment/data/{condition}/` populated with resource files
- [ ] `experiment/AGENT_PROMPT.md.template` customized
- [ ] `node:20-bookworm` pre-pulled (`docker pull node:20-bookworm`)
- [ ] No stale containers or worktrees from previous runs
- [ ] Budget set appropriately (`--budget N`)
- [ ] Prompt includes time-budget instructions (write result by turn 12)
