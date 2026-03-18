# template-cc

A template repository for Python projects with nix/direnv/uv and containerized Claude Code experiments.

## Development

<details>
  <summary>System setup (one-time)</summary>

```bash
# Install Nix
sh <(curl -L https://nixos.org/nix/install) --daemon
mkdir -p ~/.config/nix
echo "experimental-features = nix-command flakes" >> ~/.config/nix/nix.conf
exit # the commands below need a fresh shell

# Install direnv
nix profile install nixpkgs#direnv nixpkgs#nix-direnv

# Install direnv shell hook
if [[ "$SHELL" == *"/zsh" ]]; then
    echo 'eval "$(direnv hook zsh)"' >> ~/.zshrc
elif [[ "$SHELL" == *"/bash" ]]; then
    echo 'eval "$(direnv hook bash)"' >> ~/.bashrc
elif [[ "$SHELL" == *"/fish" ]]; then
    echo 'direnv hook fish | source' >> ~/.config/fish/config.fish
else
    echo "Can't set up direnv hook for your $SHELL, please set it up manually"
fi

# Setup nix-direnv
mkdir -p ~/.config/direnv
echo 'source $HOME/.nix-profile/share/nix-direnv/direnvrc' >> ~/.config/direnv/direnvrc

# Install pre-commit
nix profile install nixpkgs#pre-commit
```

</details>

### Project setup

After cloning, copy `.env.example` to `.env` and fill in any keys.

```bash
direnv allow
pre-commit install && pre-commit run --all-files
```

### Daily workflow

```bash
cd my-project       # automatically loads environment via direnv
uv run my_script.py # run Python scripts
uv add requests     # add dependencies
ninja               # builds the paper (paper-typst/main.typ → paper-typst/main.pdf)
git commit           # checks format, lints, and type checks via pre-commit
```

### Files to know

- `flake.nix` — system dependencies (uv, typst, ninja, nix tools)
- `pyproject.toml` — Python dependencies and ruff config
- `.envrc` — direnv config that activates nix + uv
- `.pre-commit-config.yaml` — commit hooks (ruff, ty, nixfmt, uv-lock)
- `build.ninja` — build targets (`ninja paper` compiles the Typst paper)
- `paper-typst/main.typ` — paper source
- `.github/workflows/paper.yml` — CI: builds paper, uploads as release on main
- `experiment/run_experiment.sh` — containerized experiment runner (devcontainers + Claude Code agents)
- `experiment/.devcontainer/` — Dockerfile, firewall, permission bypass for agent containers
- `experiment/AGENT_PROMPT.md.template` — prompt template with `{{TASK_ID}}` and `{{CONDITION}}` placeholders

### Running experiments

```bash
# 1. Define tasks (one ID per line)
echo -e "task1\ntask2\ntask3" > experiment/tasks.txt

# 2. Place data per condition
mkdir -p experiment/data/my_condition
cp my_resources.txt experiment/data/my_condition/

# 3. Customize the prompt template
vim experiment/AGENT_PROMPT.md.template

# 4. Run
./experiment/run_experiment.sh --conditions my_condition --budget 50

# 5. Results are in experiment/results/my_condition/*.jsonl
```

Each agent runs in a firewalled Docker container (no internet) with full tool access (bash, Python, file I/O). Agents use Claude Opus 4.6 with `--dangerously-skip-permissions`. See `CLAUDE.md` for details and gotchas.
