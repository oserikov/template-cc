# CLAUDE.md

Ensure `direnv` is active before working — run `direnv allow` if the shell env looks wrong.
Use `uv` for Python dependency management; run scripts with `uv run <script>`.
Run `ninja` from the repo root to compile the Typst paper (`paper-typst/main.typ` → `paper-typst/main.pdf`).
The paper lives in `paper-typst/main.typ`; always rebuild with `ninja` after editing and commit the updated PDF alongside the source.
Use `ruff` for linting/formatting Python code.
Do not commit `.direnv/`, `.venv/`, `.cursor/`, or `.ninja_log`.
