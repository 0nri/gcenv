#!/bin/sh
# gcenv — GCloud Environment Manager
# Installer script — safe to pipe to sh:
#   curl -fsSL https://raw.githubusercontent.com/0nri/gcenv/main/install.sh | sh
#
# Environment variable overrides:
#   GCENV_INSTALL_DIR — override the installation directory (default: ~/.gcenv)
set -eu

INSTALL_DIR="${GCENV_INSTALL_DIR:-$HOME/.gcenv}"
REPO="https://github.com/0nri/gcenv"

# Verify gcloud is installed before proceeding — gcenv is useless without it.
if ! command -v gcloud >/dev/null 2>&1; then
  echo "Error: gcloud CLI is not installed or not on PATH." >&2
  echo "Install it from: https://cloud.google.com/sdk/docs/install" >&2
  exit 1
fi

echo "Installing gcenv to $INSTALL_DIR..."

# Clone or update — check for existing .git before clone to avoid failing
# on a non-empty directory.
if [ -d "$INSTALL_DIR/.git" ]; then
  echo "Existing installation found. Updating..."
  git -C "$INSTALL_DIR" pull --ff-only
elif command -v git >/dev/null 2>&1; then
  git clone --depth=1 "$REPO.git" "$INSTALL_DIR"
else
  mkdir -p "$INSTALL_DIR"
  curl -fsSL "$REPO/archive/refs/heads/main.tar.gz" | \
    tar xz --strip-components=1 -C "$INSTALL_DIR"
fi

# Detect shell and write the appropriate source line.
# Bash and zsh understand `source`; POSIX sh (dash on Ubuntu) requires `.`.
SHELL_RC=""
SOURCE_CMD="."
case "${SHELL:-}" in
  */zsh)
    SHELL_RC="$HOME/.zshrc"
    SOURCE_CMD="source"
    ;;
  */bash)
    SHELL_RC="$HOME/.bashrc"
    SOURCE_CMD="source"
    ;;
esac

if [ -n "$SHELL_RC" ]; then
  SOURCE_LINE="${SOURCE_CMD} \"$INSTALL_DIR/gcenv.sh\""
  if ! grep -qF "$SOURCE_LINE" "$SHELL_RC" 2>/dev/null; then
    printf '\n# gcenv — GCloud Environment Manager\n%s\n' "$SOURCE_LINE" >> "$SHELL_RC"
    echo "Added to $SHELL_RC"
  else
    echo "Already configured in $SHELL_RC"
  fi
else
  echo "Shell not detected. Manually add the following to your shell RC file:"
  echo "  . \"$INSTALL_DIR/gcenv.sh\""
fi

echo ""
echo "✅ gcenv installed. Restart your shell or run:"
echo "   . $INSTALL_DIR/gcenv.sh"
