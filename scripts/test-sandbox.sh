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

TMP_BASE="${TMPDIR:-/tmp}"
TMP_BASE="${TMP_BASE%/}"   # strip trailing slash (macOS $TMPDIR has one)
SANDBOX="$(mktemp -d "$TMP_BASE/alvera-sandbox.XXXXXX")"
FAKE_HOME="$SANDBOX/home"
CONFIG_DIR="$SANDBOX/home/.claude"
PROJECT="$SANDBOX/project"
MARKET="$SANDBOX/marketplace"

mkdir -p "$FAKE_HOME" "$CONFIG_DIR" "$PROJECT" "$MARKET"

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

Exit Claude to clean up the sandbox ($([[ $KEEP -eq 1 ]] && echo 'kept' || echo 'auto-deleted')).
────────────────────────────────────────────────────────────────────────
INFO

# Minimal env — drop anything that could leak host config.
# Keep PATH so `claude`, `npx`, `node`, etc. resolve.
cd "$PROJECT"
if [[ "$MODE" == "shell" ]]; then
  exec env -i \
    HOME="$FAKE_HOME" \
    CLAUDE_CONFIG_DIR="$CONFIG_DIR" \
    PATH="$PATH" \
    TERM="${TERM:-xterm-256color}" \
    SHELL="${SHELL:-/bin/bash}" \
    PS1='(sandbox) \w $ ' \
    "${SHELL:-/bin/bash}"
else
  exec env -i \
    HOME="$FAKE_HOME" \
    CLAUDE_CONFIG_DIR="$CONFIG_DIR" \
    PATH="$PATH" \
    TERM="${TERM:-xterm-256color}" \
    claude
fi
