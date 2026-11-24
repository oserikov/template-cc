#!/usr/bin/env bash
# Blocks when a pipeline spec (spec-*.md) exists but research-config.yaml is missing or invalid.
# Usage: research-config-gate.sh stop|bash   (Claude Code hook JSON arrives on stdin)
root="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null)}"
[ -n "$root" ] && compgen -G "$root/spec-*.md" >/dev/null || exit 0

input="$(cat)"
case "$1" in
  stop)
    # One retry, like the global test gate: never block a second time in a row.
    [ "$(jq -r '.stop_hook_active // false' <<<"$input")" = "true" ] && exit 0 ;;
  bash)
    # Gate only commands that run an experiment, so fixing the config stays possible.
    cmd="$(jq -r '.tool_input.command // ""' <<<"$input")"
    grep -Eq 'inspect eval|run_experiment|experiment/|python[^|;&]*(run|eval|experiment)' <<<"$cmd" || exit 0 ;;
esac

out="$(cd "$root" && uv run --quiet --with pyyaml python scripts/check_research_config.py 2>&1)" && exit 0
echo "$out" >&2
exit 2
