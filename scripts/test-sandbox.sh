#!/usr/bin/env bash
# Isolated Claude Code sandbox for testing this marketplace + plugin.
#
# Creates a throwaway temp root and launches Claude Code with HOME and
# CLAUDE_CONFIG_DIR pointed inside it, so nothing in your real home is
# touched: no ~/.claude, no ~/.claude.json, no ~/.alvera-ai/, no ~/.ssh,
# no ~/.gitconfig. A snapshot of this repo is copied into the sandbox
# and registered as a local marketplace.
#
# Usage:
#   scripts/test-sandbox.sh             # create sandbox + exec claude inside it
#   scripts/test-sandbox.sh --shell     # create sandbox + drop into a shell instead
#   scripts/test-sandbox.sh --keep      # don't delete on exit (inspect state)
#   scripts/test-sandbox.sh --help
#
# Requires: bash 4+, rsync (fallback: cp -R), claude binary on PATH.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MARKETPLACE_NAME="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["name"])' \
  "$REPO_ROOT/.claude-plugin/marketplace.json")"
PLUGIN_NAME="$(python3 -c '
import json, sys
m = json.load(open(sys.argv[1]))
print(m["plugins"][0]["name"])
' "$REPO_ROOT/.claude-plugin/marketplace.json")"

MODE="claude"   # claude | shell
KEEP=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --shell) MODE="shell"; shift ;;
    --keep)  KEEP=1; shift ;;
    --help|-h)
      sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) echo "unknown flag: $1" >&2; exit 2 ;;
  esac
done

command -v claude >/dev/null || { echo "error: 'claude' not on PATH" >&2; exit 1; }
REAL_CLAUDE="$(command -v claude)"
REAL_HOME="$HOME"

# Use /tmp directly (not $TMPDIR) — shorter path, fewer TUI line-wrap issues
# with /plugin's add-marketplace dialog on macOS.
SANDBOX="$(mktemp -d /tmp/alvera.XXXXXX)"
FAKE_HOME="$SANDBOX/home"
CONFIG_DIR="$SANDBOX/home/.claude"
PROJECT="$SANDBOX/project"
MARKET="$SANDBOX/market"

mkdir -p "$FAKE_HOME/.local/bin" "$CONFIG_DIR" "$PROJECT" "$MARKET"

# Claude Code's "native" install records installMethod: native and checks
# for its own binary at $HOME/.local/bin/claude at startup. With HOME
# redirected, that path resolves inside the sandbox — so mirror the real
# binary there via a symlink.
ln -sf "$REAL_CLAUDE" "$FAKE_HOME/.local/bin/claude"

# Toolchain passthrough: symlink any Node / Rust version-manager state
# from the real HOME into the fake HOME so `npx`, `npm`, `pnpm`, `node`
# etc. keep working inside the sandbox. Shims are absolute paths in the
# inherited PATH; their internals look up config relative to $HOME, so
# without these links the shims exit with "no version set" or similar.
toolchain_paths=(
  ".asdf"           # asdf: plugins, installs, shims, global .tool-versions
  ".tool-versions"  # project-agnostic fallback
  ".config/mise"    # mise config (alternate asdf)
  ".local/share/mise"
  ".nvm"            # nvm install root (if user uses nvm)
  ".npm"            # npm cache + global prefix default
  ".npmrc"          # npm config
  ".pnpm"
  ".pnpm-store"
)
for p in "${toolchain_paths[@]}"; do
  [[ -e "$REAL_HOME/$p" ]] || continue
  mkdir -p "$(dirname "$FAKE_HOME/$p")"
  ln -sf "$REAL_HOME/$p" "$FAKE_HOME/$p"
done

# Silence noisy dotfile sources from user shell rc files. These don't
# affect the skill — they just make `pwd` etc. print a spurious error
# when the user's ~/.zshenv sources a file that doesn't exist in the
# fake HOME. Touch empty stubs rather than symlinking the real dirs.
mkdir -p "$FAKE_HOME/.cargo"
: > "$FAKE_HOME/.cargo/env"

# Write an `activate.sh` the user can `source` in another terminal to
# join the same isolated environment (same fake HOME, same
# CLAUDE_CONFIG_DIR, same cwd). Values are baked in at sandbox-creation
# time so no lookups against the real HOME are needed.
cat > "$SANDBOX/activate.sh" <<EOF
# Source this file (do not execute) in another terminal to enter the
# Alvera sandbox at $SANDBOX. Example:
#   source $SANDBOX/activate.sh
#
# When you're done, \`exit\` or open a fresh shell — the activation is
# scoped to whatever shell sourced this file.

if [[ "\${BASH_SOURCE[0]:-\$0}" == "\$0" ]]; then
  echo "activate.sh must be sourced, not executed:" >&2
  echo "  source \$0" >&2
  exit 1
fi

unset ALVERA_PROFILE ALVERA_BASE_URL ALVERA_TENANT ALVERA_EMAIL \\
      ALVERA_PASSWORD ALVERA_SESSION_TOKEN
export HOME='$FAKE_HOME'
export CLAUDE_CONFIG_DIR='$CONFIG_DIR'
EOF

# Pin toolchain env vars into activate.sh if the corresponding paths
# were detected on the real HOME. Conditional writes keep the activate
# script minimal and easy to inspect.
if [[ -d "$REAL_HOME/.asdf" ]]; then
  echo "export ASDF_DATA_DIR='$REAL_HOME/.asdf'" >> "$SANDBOX/activate.sh"
fi
if [[ -d "$REAL_HOME/.nvm" ]]; then
  echo "export NVM_DIR='$REAL_HOME/.nvm'" >> "$SANDBOX/activate.sh"
fi

cat >> "$SANDBOX/activate.sh" <<EOF
cd '$PROJECT'
export PS1='(sandbox) \\w \$ '
echo "Entered Alvera sandbox:"
echo "  HOME=\$HOME"
echo "  cwd=\$(pwd)"
echo "  CLAUDE_CONFIG_DIR=\$CLAUDE_CONFIG_DIR"
EOF

# Snapshot this repo (excluding VCS, node_modules, and .claude local state).
if command -v rsync >/dev/null; then
  rsync -a \
    --exclude='.git/' \
    --exclude='node_modules/' \
    --exclude='.claude/' \
    --exclude='.DS_Store' \
    "$REPO_ROOT/" "$MARKET/"
else
  cp -R "$REPO_ROOT/." "$MARKET/"
  rm -rf "$MARKET/.git" "$MARKET/node_modules" "$MARKET/.claude"
fi

cleanup() {
  if [[ $KEEP -eq 1 ]]; then
    printf '\nSandbox kept at: %s\n' "$SANDBOX" >&2
  else
    rm -rf "$SANDBOX"
  fi
}
trap cleanup EXIT

cat >&2 <<INFO
────────────────────────────────────────────────────────────────────────
Claude Code sandbox ready.

  sandbox root : $SANDBOX
  fake HOME    : $FAKE_HOME
  config dir   : $CONFIG_DIR
  cwd          : $PROJECT
  marketplace  : $MARKET  (local snapshot of $REPO_ROOT)

Inside Claude, run:

  /plugin marketplace add $MARKET
  /plugin install $PLUGIN_NAME@$MARKETPLACE_NAME
  /plugin list

Then exercise the guided skill normally. Credentials written by
\`alvera login\` will land in $FAKE_HOME/.alvera-ai/ — not your real home.

To open a second terminal inside the SAME sandbox (e.g. to run
\`alvera login\` yourself while Claude is running), open a new shell
and run:

  source $SANDBOX/activate.sh

The second shell will inherit HOME, CLAUDE_CONFIG_DIR, and the cwd.
Exit the shell to leave the sandbox (it only affects the shell that
sourced it).

Cleanup: sandbox will be $([[ $KEEP -eq 1 ]] && echo 'kept (delete with: rm -rf '"$SANDBOX"')' || echo 'auto-deleted when this Claude session exits — pass --keep if you want multi-terminal use').
────────────────────────────────────────────────────────────────────────
INFO

# Env strategy: inherit the parent shell environment (so asdf / rtx / nvm
# / mise shims keep working and `npx` resolves), but override HOME and
# CLAUDE_CONFIG_DIR, and wipe ALVERA_* so a stray token in the parent
# shell can't bypass `alvera login` inside the sandbox.
cd "$PROJECT"
unset ALVERA_PROFILE ALVERA_BASE_URL ALVERA_TENANT ALVERA_EMAIL \
      ALVERA_PASSWORD ALVERA_SESSION_TOKEN
export HOME="$FAKE_HOME"
export CLAUDE_CONFIG_DIR="$CONFIG_DIR"

# Some toolchains honor explicit root env vars over $HOME lookups — set
# them when their real paths are present so shims resolve even if the
# symlink step above is disabled or fails silently.
# ASDF_DIR = where asdf's own code lives (homebrew: /opt/homebrew/opt/asdf/libexec).
# ASDF_DATA_DIR = where plugins, installs, shims live (~/.asdf).
# Inherit ASDF_DIR from parent env — overriding it breaks homebrew asdf.
# Only pin ASDF_DATA_DIR to the real home so plugin/install lookups work.
[[ -d "$REAL_HOME/.asdf" ]] && export ASDF_DATA_DIR="$REAL_HOME/.asdf"
[[ -d "$REAL_HOME/.nvm"  ]] && export NVM_DIR="$REAL_HOME/.nvm"

if [[ "$MODE" == "shell" ]]; then
  export PS1='(sandbox) \w $ '
  exec "${SHELL:-/bin/bash}"
else
  exec "$REAL_CLAUDE"
fi
