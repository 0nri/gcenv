# gcenv — gcloud Environment Manager

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Shell: bash 3.2+ / zsh 5.x](https://img.shields.io/badge/shell-bash%203.2%2B%20%2F%20zsh%205.x-blue)](gcenv.sh)

Make [`gcloud` CLI](https://docs.cloud.google.com/sdk/gcloud) environment activation **per-shell-session** — no daemon, no config files, no lock-in.

---

## The Problem

`gcloud` is globally stateful. Running `gcloud config configurations activate prod` changes the environment for **every open terminal**. Application Default Credentials (ADC) are equally global, stored in a single file. Switching environments in one tab silently contaminates parallel tabs — a misconfigured command can write to the wrong project with no obvious error.

**`gcenv`** fixes this by setting two native environment variables (`CLOUDSDK_ACTIVE_CONFIG_NAME` and `GOOGLE_APPLICATION_CREDENTIALS`) in the current shell process. Child processes inherit them; sibling terminals do not. Isolation is complete and automatic.

---

## Installation

### One-liner (recommended)

```sh
curl -fsSL https://raw.githubusercontent.com/0nri/gcenv/main/install.sh | sh
```

The installer:
1. Verifies `gcloud` is installed
2. Clones the repo to `~/.gcenv` (updates if already installed)
3. Adds a `source` line to `~/.zshrc` or `~/.bashrc`

Restart your shell, or run the source line printed by the installer.

### Manual install

```sh
git clone --depth=1 https://github.com/0nri/gcenv.git ~/.gcenv
# Add to ~/.zshrc or ~/.bashrc:
source ~/.gcenv/gcenv.sh
```

### Prerequisites

- [`gcloud` CLI](https://cloud.google.com/sdk/docs/install) — required
- [`jq`](https://stedolan.github.io/jq/) — required for `gcenv set-adc` (JSON validation)

---

## Quick Start

### New user account environment

```sh
# Create a named environment, authenticate, and capture ADC in one step
gcenv init dev my-dev-project   # project ID is required

# Activate it in the current shell
gcenv use dev

# See what's active
gcenv status
```

### Import your existing state

Already working in a GCP project? Capture your current state without any browser interaction:

```sh
gcenv import staging
gcenv use staging
```

### Service account / CI environments

```sh
gcenv init ci my-ci-project --no-login
gcenv set-adc ci /path/to/sa-key.json
gcenv use ci
```

### See all environments

```sh
gcenv list
```

### Return to system defaults

```sh
gcenv deactivate
```

---

## Command Reference

| Command | Args | Description |
|---------|------|-------------|
| `gcenv init` | `<name> <project>` | Create a gcloud config, authenticate (browser), and capture ADC with quota project. Project ID is required. |
| `gcenv init` | `<name> --no-login` | Create a gcloud config only, skip authentication. Use `gcenv set-adc` afterward for service account key environments. |
| `gcenv import` | `<name>` | Snapshot the current shell's gcloud config (project, account, region, zone) and ADC into a new named environment. Zero browser interaction. |
| `gcenv use` | `<name>` | Activate a named environment in the current shell by setting `CLOUDSDK_ACTIVE_CONFIG_NAME` and `GOOGLE_APPLICATION_CREDENTIALS`. |
| `gcenv deactivate` | | Unset all `gcenv`-managed variables, returning the shell to the system default `gcloud` configuration. |
| `gcenv login` | | Re-authenticate the active environment. Runs `gcloud auth login` and `gcloud auth application-default login`, then re-captures the ADC. |
| `gcenv set-adc` | `<name> <path>` | Copy a service account key JSON file as the ADC for the named environment. File is validated with `jq` and written with `600` permissions. |
| `gcenv list` | | Show all `gcloud config configurations` and overlay each environment's ADC status from `~/.config/gcenv/adc/`. |
| `gcenv status` | | Show the active environment name, environment variables, and full `gcloud config list` output. |
| `gcenv delete` | `<name>` | Prompt for confirmation, then remove the gcloud configuration and its ADC file. Automatically deactivates the current shell if the deleted env was active. |
| `gcenv update` | | Pull the latest gcenv from git (`git pull --ff-only`) and re-source in the current shell. Requires a git-based install. |
| `gcenv version` | | Print the gcenv version string (e.g., `gcenv 0.1.0`). Also responds to `--version`. |
| `gcenv help` | | Show usage summary and active environment. Also responds to `--help` and `-h`. |

---

## Storage Layout

```
~/.config/gcenv/
└── adc/
    ├── dev.json        # User ADC or service account key — permissions 600
    ├── staging.json
    └── prod.json
```

`gcenv` writes ADC files using `install -m 600` — permissions are set atomically on creation, with no world-readable window. The global ADC at `~/.config/gcloud/application_default_credentials.json` is **copied**, never moved, so IDEs and other tools continue to work.

---

## Prompt Integration

Show the active environment in your shell prompt.

### Zsh

Add after sourcing `gcenv.sh` in `~/.zshrc`:

```zsh
source ~/.gcenv/gcenv.sh
PROMPT='$(gcenv_prompt_zsh)'$PROMPT
```

### Bash

Add after sourcing `gcenv.sh` in `~/.bashrc`:

```bash
source ~/.gcenv/gcenv.sh
PS1='$(gcenv_prompt_bash)'$PS1
```

Both prompt functions render as `(gcp:envname)` in cyan when an environment is active, and produce no output otherwise.

---

## Tab Completions

### Zsh

```zsh
# Add completions directory to fpath before compinit:
fpath=(~/.gcenv/completions $fpath)
autoload -Uz compinit && compinit
```

Or manually source:

```zsh
source ~/.gcenv/completions/gcenv.zsh
```

### Bash

```bash
source ~/.gcenv/completions/gcenv.bash
```

Tab completion covers all subcommands, and completes environment names (from `gcloud config configurations list`) for `use`, `import`, `delete`, and `set-adc`.

---

## iTerm2 Integration

iTerm2 Profiles can open a terminal tab pre-configured for a specific `gcenv` environment — one click to open a GCP-isolated terminal with the right project, credentials, and a color-coded background.

See [examples/iterm2-profiles.md](examples/iterm2-profiles.md) for the step-by-step setup guide.

`gcenv` also automatically sets the iTerm2 tab badge to the active environment name.

---

## How It Works

Two native environment variables provide complete, tab-isolated GCP sessions:

| Variable | Controls |
|----------|----------|
| `CLOUDSDK_ACTIVE_CONFIG_NAME` | Which `gcloud config configuration` is active in this shell |
| `GOOGLE_APPLICATION_CREDENTIALS` | Which ADC JSON file GCP client libraries use |

Setting these via `export` in the current shell process means isolation is automatic — child processes inherit them, but sibling terminals do not. No daemon, no file locking, no global state mutation.

`gcenv` follows a **convention over configuration** philosophy:
- **gcloud owns**: All named configurations, credential tokens, configuration properties
- **gcenv owns**: One directory of per-environment ADC copies at `~/.config/gcenv/adc/<name>.json`

---

## License

[MIT](LICENSE) © 2025 gcenv contributors
