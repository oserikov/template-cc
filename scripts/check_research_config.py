"""Check research-config.yaml, the single source of truth for an experiment's setup.

Exits 0 when the repo has no spec-*.md (not a pipeline project) or the config is valid.
Exits 1 and lists every problem otherwise. Run from the repo root:

    uv run python scripts/check_research_config.py
"""

import os
import sys
from pathlib import Path

import yaml

MODEL_FIELDS = (
    "role",
    "provider",
    "model_id",
    "api_key_env",
    "thinking",
    "temperature",
    "max_tokens",
)
LOG_FORMATS = {"inspect-eval", "jsonl"}
PLACEHOLDERS = {"", "todo", "tbd", "?", "none", "null"}


def blank(value):
    if value is None or value == [] or value == {}:
        return True
    text = str(value).strip()
    return text.lower() in PLACEHOLDERS or (text.startswith("<") and text.endswith(">"))


def dotenv_keys(root):
    path = root / ".env"
    if not path.exists():
        return set()
    keys = set()
    for line in path.read_text().splitlines():
        line = line.strip().removeprefix("export ")
        if "=" in line and not line.startswith("#"):
            key, value = line.split("=", 1)
            if value.strip():
                keys.add(key.strip())
    return keys


def check(root):
    path = root / "research-config.yaml"
    if not path.exists():
        return [
            "research-config.yaml is missing, but the repo has a spec-*.md. Write it from the spec."
        ]
    try:
        cfg = yaml.safe_load(path.read_text()) or {}
    except yaml.YAMLError as e:
        return [f"research-config.yaml is not valid YAML: {e}"]
    if not isinstance(cfg, dict):
        return [
            "research-config.yaml must be a mapping with models, prompts, data and logs."
        ]

    problems = []
    env = set(os.environ) | dotenv_keys(root)

    models = cfg.get("models")
    if not isinstance(models, list) or not models:
        problems.append("models: list at least one model.")
    for i, m in enumerate(models if isinstance(models, list) else []):
        m = m if isinstance(m, dict) else {}
        problems += [
            f"models[{i}].{f}: empty or placeholder."
            for f in MODEL_FIELDS
            if blank(m.get(f))
        ]
        key = m.get("api_key_env")
        if not blank(key) and key not in env:
            problems.append(
                f"models[{i}].api_key_env: {key} is not set in the environment or .env."
            )

    prompts = cfg.get("prompts")
    if not isinstance(prompts, list) or not prompts:
        problems.append("prompts: list at least one prompt file.")
    for i, p in enumerate(prompts if isinstance(prompts, list) else []):
        p = p if isinstance(p, dict) else {}
        if blank(p.get("id")):
            problems.append(f"prompts[{i}].id: empty or placeholder.")
        if blank(p.get("path")):
            problems.append(f"prompts[{i}].path: empty or placeholder.")
        elif not (root / str(p["path"])).is_file():
            problems.append(f"prompts[{i}].path: {p['path']} does not exist.")

    data = cfg.get("data")
    data = data if isinstance(data, dict) else {}
    problems += [
        f"data.{f}: empty or placeholder."
        for f in ("dataset", "n", "seeds")
        if blank(data.get(f))
    ]

    logs = cfg.get("logs")
    logs = logs if isinstance(logs, dict) else {}
    if blank(logs.get("dir")):
        problems.append("logs.dir: empty or placeholder.")
    if logs.get("format") not in LOG_FORMATS:
        problems.append(
            f"logs.format: must be one of {sorted(LOG_FORMATS)}, got {logs.get('format')!r}."
        )
    return problems


def main():
    root = Path.cwd()
    if not any(root.glob("spec-*.md")):
        return 0
    problems = check(root)
    if not problems:
        return 0
    print("research-config.yaml check failed:", file=sys.stderr)
    for p in problems:
        print(f"  - {p}", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
