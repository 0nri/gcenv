# gcenv — GCloud Environment Manager
# Source this file in your shell RC file (e.g., ~/.zshrc or ~/.bashrc):
#   source ~/.gcenv/gcenv.sh
#
# Repository: https://github.com/0nri/gcenv
# License: MIT

# gcenv version — bumped on every release using semver (MAJOR.MINOR.PATCH)
GCENV_VERSION="0.1.0"

# Installation root — the directory where gcenv.sh lives.
# Defaults to ~/.gcenv (the installer default). Override if you installed
# gcenv to a different path: export GCENV_ROOT=/path/to/gcenv
GCENV_ROOT="${GCENV_ROOT:-$HOME/.gcenv}"

# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

# _gcenv_validate_name — allowlist check for environment names.
# Names map directly to file paths; restricting to [a-zA-Z0-9_-] prevents
# path traversal attacks and broken filenames.
_gcenv_validate_name() {
  case "$1" in
    *[^a-zA-Z0-9_-]*|"")
      echo "Error: environment name '$1' is invalid." >&2
      echo "Names must contain only letters, numbers, hyphens, and underscores." >&2
      return 1
      ;;
  esac
}

# _gcenv_config_value — wraps gcloud config get-value.
# gcloud prints the literal string "(unset)" when a property has no value;
# naive variable assignment would capture this and corrupt subsequent
# gcloud config set calls. This helper normalises it to an empty string.
_gcenv_config_value() {
  local val
  val=$(gcloud config get-value "$1" 2>/dev/null)
  [ "$val" = "(unset)" ] && val=""
  printf '%s' "$val"
}

# _gcenv_install_file — copy a file with 600 permissions atomically.
# The `install` command (BSD/macOS and GNU coreutils) sets permissions on
# creation, eliminating the cp + chmod race window where credential files
# are briefly world-readable.
_gcenv_install_file() {
  # Usage: _gcenv_install_file <src> <dst>
  install -m 600 "$1" "$2"
}

# _gcenv_restore_global_active_config — restore the on-disk gcloud active config.
# `gcloud config configurations create` silently changes the on-disk active_config
# marker, which breaks shells that do not use CLOUDSDK_ACTIVE_CONFIG_NAME.
# This helper runs activate in a subshell with the env var unset so that only
# the on-disk marker is updated — the current shell's env var is unchanged.
_gcenv_restore_global_active_config() {
  local prev="${1:-}"
  [ -z "$prev" ] && return 0
  (unset CLOUDSDK_ACTIVE_CONFIG_NAME; gcloud config configurations activate "$prev") >/dev/null 2>&1 || true
}

# _gcenv_update — pull the latest gcenv code from git and re-source.
_gcenv_update() {
  local root="${GCENV_ROOT:-$HOME/.gcenv}"

  if [ ! -d "$root/.git" ]; then
    echo "Error: gcenv was not installed via git (no .git found in $root)." >&2
    echo "Re-install using:" >&2
    echo "  curl -fsSL https://raw.githubusercontent.com/0nri/gcenv/main/install.sh | sh" >&2
    return 1
  fi

  echo "Updating gcenv from $(gcenv version)..."
  git -C "$root" pull --ff-only || {
    echo "Error: update failed. Try manually: cd $root && git pull" >&2
    return 1
  }

  # Re-source to pick up the new version in the current shell session.
  # Shell functions are simply redefined; active environment variables
  # (GCENV_ACTIVE, CLOUDSDK_ACTIVE_CONFIG_NAME, etc.) are preserved.
  . "$root/gcenv.sh"
  echo "✅ gcenv updated to $(gcenv version)"
}

# _gcenv_set_terminal_title — set window title and iTerm2 tab badge.
# Only sends escape codes when stdout is a terminal (guards against piped use).
_gcenv_set_terminal_title() {
  local name="${1:-}"
  # Only send escape codes when attached to an interactive terminal
  [ -t 1 ] || return 0

  # xterm OSC 0: sets both icon name and window title.
  # Works in most xterm-compatible terminals (iTerm2, Terminal.app, WezTerm, Ghostty, etc.)
  printf "\033]0;%s\007" "${name:+gcenv:$name}"

  # iTerm2-specific: tab badge (macOS only — guarded by TERM_PROGRAM check).
  # `base64` without flags is the macOS/BSD form and is never called on Linux
  # because iTerm.app is macOS-only.
  # `tr -d '\n'` removes any trailing newline from base64 output for safety.
  if [ "${TERM_PROGRAM:-}" = "iTerm.app" ]; then
    printf "\e]1337;SetBadgeFormat=%s\a" "$(printf '%s' "$name" | base64 | tr -d '\n')"
  fi
}

# ---------------------------------------------------------------------------
# Prompt integration helpers
# ---------------------------------------------------------------------------

# gcenv_prompt_zsh — call from PROMPT in .zshrc.
# printf %% → literal %, producing %F{cyan}...%f which zsh expands as a
# color sequence when rendering PROMPT. Do not change %% to %.
gcenv_prompt_zsh() {
  [ -n "${GCENV_ACTIVE:-}" ] && printf "%%F{cyan}(gcp:%s)%%f " "$GCENV_ACTIVE"
}

# gcenv_prompt_bash — call from PS1 in .bashrc.
# \001 and \002 are the correct non-printing character markers for PS1 functions
# called via $(). The familiar \[ and \] are only processed when they appear
# literally in PS1 itself, not in output of command substitutions; using them
# here would cause bash to miscalculate line width and corrupt line editing.
gcenv_prompt_bash() {
  [ -n "${GCENV_ACTIVE:-}" ] && \
    printf '\001\033[0;36m\002(gcp:%s)\001\033[0m\002 ' "$GCENV_ACTIVE"
}

# ---------------------------------------------------------------------------
# Command implementations
# ---------------------------------------------------------------------------

# _gcenv_init — create a named gcloud configuration and authenticate.
_gcenv_init() {
  local name="${1:-}"
  local project=""
  local do_login=true

  if [ -z "$name" ]; then
    echo "Usage: gcenv init <name> <project>   (authenticate + capture ADC)" >&2
    echo "       gcenv init <name> --no-login   (create config only, skip auth)" >&2
    return 1
  fi
  _gcenv_validate_name "$name" || return 1

  # Parse remaining positional and flag args
  shift
  for arg in "$@"; do
    case "$arg" in
      --no-login) do_login=false ;;
      *)          project="$arg" ;;
    esac
  done

  # Require a project when logging in — without one, gcloud auth application-default
  # login cannot set a quota project, and ADC-based API calls will fail with quota errors.
  # Use --no-login to skip authentication entirely (e.g. for service account key environments).
  if $do_login && [ -z "$project" ]; then
    echo "Error: project ID required when authenticating." >&2
    echo "Usage: gcenv init $name <PROJECT_ID>" >&2
    echo "       gcenv init $name --no-login   (skip auth; configure later with 'gcenv set-adc')" >&2
    return 1
  fi

  # Save the on-disk active config so non-gcenv shells are unaffected.
  # gcloud config configurations create silently changes the on-disk active
  # marker; we restore it immediately after so other terminals/IDEs stay put.
  local prev_global
  prev_global=$( (unset CLOUDSDK_ACTIVE_CONFIG_NAME; gcloud config configurations list --filter='is_active=true' --format='value(name)' 2>/dev/null) | head -1 )

  # 1. Create the gcloud configuration if it doesn't exist
  if ! gcloud config configurations describe "$name" >/dev/null 2>&1; then
    gcloud config configurations create "$name"
    echo "Created gcloud configuration: $name"
  else
    echo "Configuration '$name' already exists."
  fi

  # Restore the global on-disk active config immediately so non-gcenv shells
  # are not affected by the create command's side effect.
  _gcenv_restore_global_active_config "$prev_global"

  # 2. Activate in this shell only (via env var, not the on-disk marker)
  export CLOUDSDK_ACTIVE_CONFIG_NAME="$name"
  export GCENV_ACTIVE="$name"

  # 3. Set project if provided
  if [ -n "$project" ]; then
    gcloud config set project "$project"
  fi

  # 4. Authenticate or skip for SA key path.
  # Returns 1 on login failure so scripts can detect it (gcenv init || exit 1).
  # The gcloud config is already created at this point regardless.
  if $do_login; then
    echo ""
    if ! _gcenv_login; then
      echo ""
      echo "⚠️  Authentication failed or was cancelled. Configuration '$name' was still created."
      echo "    Run 'gcenv login' to authenticate, or 'gcenv set-adc $name <path>' for a service account key."
      return 1
    fi
  else
    echo "Skipping authentication (--no-login). Run 'gcenv set-adc $name <path>' to configure credentials."
  fi
}

# _gcenv_import — snapshot current gcloud state into a new named environment.
_gcenv_import() {
  local name="${1:-}"

  if [ -z "$name" ]; then
    echo "Usage: gcenv import <name>" >&2
    return 1
  fi
  _gcenv_validate_name "$name" || return 1

  if gcloud config configurations describe "$name" >/dev/null 2>&1; then
    echo "Error: configuration '$name' already exists. Choose a different name." >&2
    return 1
  fi

  # Warn if a gcenv environment is already active — import captures the CURRENT
  # shell's gcloud state, which in this case is the active gcenv env, not the
  # system default. User should run 'gcenv deactivate' first if that's not intended.
  if [ -n "${GCENV_ACTIVE:-}" ]; then
    echo "⚠️  Note: current shell has '$GCENV_ACTIVE' active. Importing its state."
    echo "    Run 'gcenv deactivate' first to import your system default gcloud config."
  fi

  # Read current state using _gcenv_config_value to handle (unset) properties cleanly
  local project account region zone
  project=$(_gcenv_config_value project)
  account=$(_gcenv_config_value account)
  region=$(_gcenv_config_value compute/region)
  zone=$(_gcenv_config_value compute/zone)

  # Save the on-disk active config so non-gcenv shells are unaffected.
  local prev_global
  prev_global=$( (unset CLOUDSDK_ACTIVE_CONFIG_NAME; gcloud config configurations list --filter='is_active=true' --format='value(name)' 2>/dev/null) | head -1 )

  # Create new named configuration
  gcloud config configurations create "$name"

  # Restore the global on-disk active config immediately so non-gcenv shells
  # are not affected by the create command's side effect.
  _gcenv_restore_global_active_config "$prev_global"

  # Activate to configure it (env var only — does not touch on-disk marker)
  export CLOUDSDK_ACTIVE_CONFIG_NAME="$name"

  # Copy non-empty properties into the new config
  [ -n "$project" ] && gcloud config set project "$project"
  [ -n "$account" ] && gcloud config set account "$account"
  [ -n "$region" ]  && gcloud config set compute/region "$region"
  [ -n "$zone" ]    && gcloud config set compute/zone "$zone"

  # Copy existing ADC if present, atomically with 600 permissions
  local adc_dir="$HOME/.config/gcenv/adc"
  mkdir -p "$adc_dir"
  local adc_path="$adc_dir/${name}.json"
  local global_adc="$HOME/.config/gcloud/application_default_credentials.json"
  if [ -f "$global_adc" ]; then
    _gcenv_install_file "$global_adc" "$adc_path"
    export GOOGLE_APPLICATION_CREDENTIALS="$adc_path"
    echo "✅ ADC captured."
  else
    echo "⚠️  No global ADC found. Run 'gcenv login' to generate credentials."
  fi

  export GCENV_ACTIVE="$name"
  _gcenv_set_terminal_title "$name"

  echo "✅ Imported current state as '$name'"
  [ -n "$project" ] && echo "   Project: $project"
  [ -n "$account" ] && echo "   Account: $account"
}

# _gcenv_use — activate a named environment in the current shell.
_gcenv_use() {
  local name="${1:-}"

  if [ -z "$name" ]; then
    echo "Usage: gcenv use <name>" >&2
    return 1
  fi
  _gcenv_validate_name "$name" || return 1

  if ! gcloud config configurations describe "$name" >/dev/null 2>&1; then
    echo "Error: gcloud configuration '$name' does not exist." >&2
    echo "Run 'gcenv init $name' to create it, or 'gcenv list' to see available environments." >&2
    return 1
  fi

  export CLOUDSDK_ACTIVE_CONFIG_NAME="$name"
  export GCENV_ACTIVE="$name"

  local adc_path="$HOME/.config/gcenv/adc/${name}.json"
  if [ -f "$adc_path" ]; then
    export GOOGLE_APPLICATION_CREDENTIALS="$adc_path"
  else
    unset GOOGLE_APPLICATION_CREDENTIALS
    echo "⚠️  No ADC for '$name'. Run 'gcenv login' or 'gcenv set-adc $name <path>'."
  fi

  _gcenv_set_terminal_title "$name"
  echo "✅ Active: $name"
}

# _gcenv_deactivate — return the current shell to system default gcloud state.
_gcenv_deactivate() {
  unset CLOUDSDK_ACTIVE_CONFIG_NAME
  unset GOOGLE_APPLICATION_CREDENTIALS
  unset GCENV_ACTIVE
  _gcenv_set_terminal_title ""
  echo "gcenv deactivated. Using system default gcloud configuration."
}

# _gcenv_login — re-authenticate the active environment and capture ADC.
_gcenv_login() {
  if [ -z "${GCENV_ACTIVE:-}" ]; then
    echo "Error: No environment active. Run 'gcenv use <name>' first." >&2
    return 1
  fi

  local env_name="$GCENV_ACTIVE"
  local adc_dir="$HOME/.config/gcenv/adc"
  local adc_path="$adc_dir/${env_name}.json"
  local global_adc="$HOME/.config/gcloud/application_default_credentials.json"
  local adc_backup="${global_adc}.gcenv_backup"
  mkdir -p "$adc_dir"

  # Step 1: gcloud CLI authentication (browser open #1).
  echo "ℹ️  This will open your browser twice: once for gcloud CLI, once for ADC."
  echo ""
  echo "🔑 Authenticating gcloud CLI for '$env_name'..."
  gcloud auth login || return 1

  # Step 2: Anchor the newly authenticated account to this configuration.
  # Use gcloud auth list (not gcloud config get-value account) because config
  # get-value reads the old property value; it is not updated by auth login.
  local account
  account=$(gcloud auth list --filter='status:ACTIVE' --format='value(account)' 2>/dev/null | head -1)
  if [ -n "$account" ]; then
    gcloud config set account "$account"
    echo "   Account: $account"
  fi

  # Step 3: Generate ADC with quota project from this environment's config.
  # Uses _gcenv_config_value to avoid assigning the literal string "(unset)".
  echo ""
  echo "🔑 Generating Application Default Credentials... (browser open #2)"
  local project
  project=$(_gcenv_config_value project)

  # Backup the global ADC so we can restore it after — this keeps IDEs and
  # non-gcenv shells pointing at whatever credentials they had before.
  # gcloud auth application-default login always overwrites the global file.
  local had_global_adc=false
  if [ -f "$global_adc" ]; then
    had_global_adc=true
    cp "$global_adc" "$adc_backup"
  fi

  # Temporarily unset GOOGLE_APPLICATION_CREDENTIALS before calling ADC login.
  # If it is set, gcloud detects it and emits a confusing warning plus an
  # interactive "Do you want to continue (Y/n)?" prompt — even though gcenv
  # is about to copy the result to a different path anyway.
  local prev_gac="${GOOGLE_APPLICATION_CREDENTIALS:-}"
  unset GOOGLE_APPLICATION_CREDENTIALS

  local adc_login_ok=true
  if [ -n "$project" ]; then
    gcloud auth application-default login --project "$project" || adc_login_ok=false
  else
    gcloud auth application-default login || adc_login_ok=false
    echo "⚠️  No project set. Run 'gcloud config set project <PROJECT_ID>' and re-run 'gcenv login' to set quota project."
  fi

  # Step 4: Copy ADC to isolated path, then restore the global ADC to its
  # pre-login state so IDEs and non-gcenv shells are completely unaffected.
  if $adc_login_ok && [ -f "$global_adc" ]; then
    _gcenv_install_file "$global_adc" "$adc_path"
    # Restore global ADC: put back the original, or remove if there was none.
    if $had_global_adc; then
      mv "$adc_backup" "$global_adc"
    else
      rm -f "$global_adc"
    fi
    export GOOGLE_APPLICATION_CREDENTIALS="$adc_path"
    echo "✅ ADC isolated: $adc_path"
  else
    # Restore even on failure so we don't leave the global ADC in a broken state.
    if $had_global_adc; then
      mv "$adc_backup" "$global_adc" 2>/dev/null || true
    fi
    # Restore GOOGLE_APPLICATION_CREDENTIALS to its pre-login value.
    if [ -n "$prev_gac" ]; then
      export GOOGLE_APPLICATION_CREDENTIALS="$prev_gac"
    fi
    echo "Error: ADC file not generated. Login may have been cancelled." >&2
    return 1
  fi
}

# _gcenv_set_adc — point an environment at a service account key file.
_gcenv_set_adc() {
  local name="${1:-}"
  local key_path="${2:-}"

  if [ -z "$name" ] || [ -z "$key_path" ]; then
    echo "Usage: gcenv set-adc <name> <path>" >&2
    return 1
  fi
  _gcenv_validate_name "$name" || return 1

  if [ ! -f "$key_path" ]; then
    echo "Error: File not found: $key_path" >&2
    return 1
  fi

  # Validate JSON structure using jq
  if ! jq empty "$key_path" >/dev/null 2>&1; then
    echo "Error: '$key_path' is not valid JSON." >&2
    return 1
  fi

  local adc_dir="$HOME/.config/gcenv/adc"
  mkdir -p "$adc_dir"
  local adc_path="$adc_dir/${name}.json"
  _gcenv_install_file "$key_path" "$adc_path"
  echo "✅ ADC set for '$name': $adc_path"

  # Update active session if this env is currently active
  if [ "${GCENV_ACTIVE:-}" = "$name" ]; then
    export GOOGLE_APPLICATION_CREDENTIALS="$adc_path"
    echo "   Updated active session."
  fi
}

# _gcenv_list — show all environments and their ADC status.
_gcenv_list() {
  # When a gcenv env is active, IS_ACTIVE reflects CLOUDSDK_ACTIVE_CONFIG_NAME.
  # When no gcenv env is active, IS_ACTIVE reflects the on-disk system default —
  # gcloud always considers exactly one configuration active.
  if [ -n "${GCENV_ACTIVE:-}" ]; then
    echo "GCP Configurations (gcenv active: $GCENV_ACTIVE):"
  else
    echo "GCP Configurations (no gcenv environment active — IS_ACTIVE shows system default):"
  fi
  gcloud config configurations list
  echo ""
  echo "ADC Files (~/.config/gcenv/adc/):"
  local adc_dir="$HOME/.config/gcenv/adc"
  local found=0
  if [ -d "$adc_dir" ]; then
    for f in "$adc_dir"/*.json; do
      # Guard handles the case where the glob matches nothing (bash: literal *.json;
      # zsh without nullglob: same behaviour).
      [ -f "$f" ] || continue
      found=1
      # Combine declaration and assignment on one line to prevent bare-assignment
      # output in shells with certain trace/hook configurations.
      local env_name=$(basename "$f" .json)
      local marker=""
      [ "${GCENV_ACTIVE:-}" = "$env_name" ] && marker=" ← active in this shell"
      echo "  ${env_name}.json${marker}"
    done
  fi
  if [ "$found" -eq 0 ]; then
    echo "  (none — run 'gcenv init <name> <project>' to create an environment)"
  elif [ -z "${GCENV_ACTIVE:-}" ]; then
    echo "  (no ADC active — run 'gcenv use <name>' to activate an environment)"
  fi
}

# _gcenv_status — show details of the currently active environment.
_gcenv_status() {
  if [ -z "${GCENV_ACTIVE:-}" ]; then
    echo "No gcenv environment active in this shell."
    echo "Run 'gcenv use <name>' or 'gcenv list' to see available environments."
    return 0
  fi

  echo "Environment:  $GCENV_ACTIVE"
  echo "Config var:   CLOUDSDK_ACTIVE_CONFIG_NAME=$CLOUDSDK_ACTIVE_CONFIG_NAME"
  echo "ADC:          ${GOOGLE_APPLICATION_CREDENTIALS:-(not set — run gcenv login)}"
  echo ""
  gcloud config list 2>/dev/null
}

# _gcenv_delete — remove an environment and its ADC file.
_gcenv_delete() {
  local name="${1:-}"

  if [ -z "$name" ]; then
    echo "Usage: gcenv delete <name>" >&2
    return 1
  fi
  _gcenv_validate_name "$name" || return 1

  printf "Delete environment '%s' and its ADC? This cannot be undone. [y/N] " "$name"
  read -r confirm
  case "$confirm" in
    y|Y) ;;
    *) echo "Aborted."; return 0 ;;
  esac

  # Track whether this env was active before we unset variables
  local was_active=false
  [ "${GCENV_ACTIVE:-}" = "$name" ] && was_active=true

  # Unset CLOUDSDK_ACTIVE_CONFIG_NAME BEFORE calling gcloud delete.
  if $was_active; then
    unset CLOUDSDK_ACTIVE_CONFIG_NAME
  fi

  # gcloud refuses to delete the configuration it considers "active", checking
  # BOTH the env var (unset above) AND the on-disk active_config marker.
  # If the on-disk marker still points to the config being deleted, switch it
  # away first — otherwise gcloud refuses to delete and the failure is silent.
  local ondisk_active
  ondisk_active=$( (unset CLOUDSDK_ACTIVE_CONFIG_NAME; gcloud config configurations list --filter='is_active=true' --format='value(name)' 2>/dev/null) | head -1 )
  if [ "$ondisk_active" = "$name" ]; then
    local fallback
    fallback=$( (unset CLOUDSDK_ACTIVE_CONFIG_NAME; gcloud config configurations list --format='value(name)' 2>/dev/null) | grep -v "^${name}$" | head -1 )
    if [ -n "$fallback" ]; then
      # Switch the on-disk active marker to another existing config.
      (unset CLOUDSDK_ACTIVE_CONFIG_NAME; gcloud config configurations activate "$fallback") >/dev/null 2>&1 || true
    else
      # No other config exists (user started fresh with only gcenv configs).
      # Create 'default' so gcloud has a safe landing spot.
      # gcloud config configurations create activates the new config on disk
      # automatically, so no separate activate call is needed.
      (unset CLOUDSDK_ACTIVE_CONFIG_NAME; gcloud config configurations create default) >/dev/null 2>&1 || true
    fi
  fi

  # --quiet suppresses the interactive confirmation prompt.
  # 2>/dev/null intentionally removed — real errors (e.g. "cannot delete the
  # active configuration") must be visible rather than silently swallowed.
  gcloud config configurations delete "$name" --quiet || \
    echo "⚠️  gcloud configuration '$name' not found or already deleted."
  rm -f "$HOME/.config/gcenv/adc/${name}.json"

  # Complete the deactivation for shells that had this env active
  if $was_active; then
    unset GOOGLE_APPLICATION_CREDENTIALS
    unset GCENV_ACTIVE
    _gcenv_set_terminal_title ""
    echo "Active environment deactivated."
  fi

  echo "✅ Deleted environment: $name"
}

# ---------------------------------------------------------------------------
# Main router
# ---------------------------------------------------------------------------

gcenv() {
  local cmd="${1:-help}"
  shift 2>/dev/null || true

  case "$cmd" in
    init)        _gcenv_init "$@" ;;
    import)      _gcenv_import "$@" ;;
    use)         _gcenv_use "$@" ;;
    deactivate)  _gcenv_deactivate "$@" ;;
    login)       _gcenv_login "$@" ;;
    set-adc)     _gcenv_set_adc "$@" ;;
    list)        _gcenv_list "$@" ;;
    status)      _gcenv_status "$@" ;;
    delete)      _gcenv_delete "$@" ;;
    update)      _gcenv_update "$@" ;;
    version|--version)
      echo "gcenv $GCENV_VERSION"
      return 0
      ;;
    help|--help|-h)
      echo "Usage: gcenv <command> [args]"
      echo ""
      echo "Commands:"
      echo "  init <name> <project>                 Create config + authenticate + capture ADC"
      echo "  init <name> --no-login               Create config only, skip authentication"
      echo "  import <name>                         Snapshot current gcloud state"
      echo "  use <name>                            Activate environment in this shell"
      echo "  deactivate                            Return to system default gcloud state"
      echo "  login                                 Re-authenticate the active environment"
      echo "  set-adc <name> <path>                 Use a service account key file"
      echo "  list                                  Show environments and ADC status"
      echo "  status                                Show active environment details"
      echo "  delete <name>                         Remove environment and its ADC"
      echo "  update                                Pull latest gcenv from git and re-source"
      echo "  version                               Print gcenv version"
      echo ""
      [ -n "${GCENV_ACTIVE:-}" ] && echo "Active: $GCENV_ACTIVE" || echo "No environment active."
      return 0
      ;;
    *)
      echo "gcenv: unknown command '$cmd'. Run 'gcenv help'." >&2
      return 1
      ;;
  esac
}
