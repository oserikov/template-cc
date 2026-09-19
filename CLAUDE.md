# CLAUDE.md or AGENTS.md whatever you call it.

Ensure `direnv` is active before working — run `direnv allow` if the shell env looks wrong.
Use `uv` for Python dependency management; run scripts with `uv run <script>`.
Run `ninja` from the repo root to compile the Typst paper (`paper-typst/main.typ` → `paper-typst/main.pdf`).
The paper lives in `paper-typst/main.typ`; rebuild with `ninja` after editing to check it compiles.
`paper-typst/main.pdf` is gitignored — it's a rebuildable artifact, not committed. Don't add it back
to source control: a tracked compiled PDF collides with todoai-watch's worktree-merge machinery,
which treats an uncommitted local rebuild in the main tree as a conflict and aborts the merge.
Use `ruff` for linting/formatting Python code.
Do not commit `.direnv/`, `.venv/`, `.cursor/`, `.ninja_log`, or `paper-typst/main.pdf`.

## Running Containerized Experiments

The `experiment/` directory contains a harness for running Claude Code agents in isolated devcontainers.

### Setup

1. Place task IDs in `experiment/tasks.txt` (one per line)
2. Place condition-gated data in `experiment/data/{condition}/`
3. Customize `experiment/AGENT_PROMPT.md.template` (uses `{{TASK_ID}}` and `{{CONDITION}}` placeholders)
4. Run: `./experiment/run_experiment.sh --conditions cond1,cond2`

### Key files

- `experiment/run_experiment.sh` — orchestrator (worktrees, containers, credentials, cost tracking)
- `experiment/AGENT_PROMPT.md.template` — agent prompt with `{{TASK_ID}}` and `{{CONDITION}}` placeholders
- `experiment/.devcontainer/` — Dockerfile, firewall, permission bypass
- `experiment/data/{condition}/` — resource files mounted per condition
- `experiment/results/{condition}/{task_id}.jsonl` — full agent session logs
- `experiment/logs/` — per-run logs, devcontainer logs, rendered prompts

### Critical gotchas

- **CLAUDECODE env var**: cleared via `-e CLAUDECODE=` in docker exec so agents can run inside Claude Code sessions.
- **Workspace permissions**: orchestrator runs `chown -R node:node /workspace` after copying data.
- **State files**: per-condition with `fcntl` locking for concurrent safety.
- **Time budget**: agents must write `/workspace/result.json` by turn 12. Without this, agents research indefinitely.
- **Docker Hub rate limits**: pre-pull `node:20-bookworm` before long runs.

### Customization points

Override these bash functions before the main loop to customize behavior:
- `load_tasks` — return task IDs (default: reads `experiment/tasks.txt`)
- `render_prompt` — render the prompt for a given condition + task_id
- `get_data_dir` — return the data directory for a given condition
