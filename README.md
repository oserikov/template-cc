# template-cc

A template repository for Python projects with nix/direnv/uv.

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
git commit           # checks format, lints, and type checks via pre-commit
```

### Files to know

- `flake.nix` — system dependencies (uv, git, nix tools)
- `pyproject.toml` — Python dependencies and ruff config
- `.envrc` — direnv config that activates nix + uv
- `.pre-commit-config.yaml` — commit hooks (ruff, ty, nixfmt, uv-lock)
