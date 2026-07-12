#!/usr/bin/env bash
# Install the feedback miner: scripts into ~/.claude/scripts, hooks into settings.json.
#   git clone <repo> ~/claude-feedback-miner && ~/claude-feedback-miner/install.sh
# Idempotent: safe to re-run (e.g. after updating the repo).
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE="$HOME/.claude"
SETT="$CLAUDE/settings.json"
mkdir -p "$CLAUDE/scripts"

echo "→ checking prerequisites"
command -v jq >/dev/null 2>&1 || { echo "  ✗ jq missing — install it first"; exit 1; }
if ! command -v claude >/dev/null 2>&1 \
   && ! ls "$HOME"/.vscode-server/extensions/anthropic.claude-code-*/resources/native-binary/claude >/dev/null 2>&1; then
  echo "  ! claude CLI not found on PATH or in a VS Code extension — the miner will no-op until it is"
fi

echo "→ installing scripts to ~/.claude/scripts"
install -m 0755 "$REPO/extract-user-messages.sh"   "$CLAUDE/scripts/extract-user-messages.sh"
install -m 0755 "$REPO/run-feedback-miner.sh"      "$CLAUDE/scripts/run-feedback-miner.sh"
install -m 0755 "$REPO/feedback-proposals-ping.sh" "$CLAUDE/scripts/feedback-proposals-ping.sh"
install -m 0644 "$REPO/feedback-miner.md"          "$CLAUDE/scripts/feedback-miner.md"

echo "→ wiring SessionStart hooks into settings.json"
[ -f "$SETT" ] || echo '{}' > "$SETT"
if jq -e '.hooks.SessionStart[]?.hooks[]? | select(.command | contains("run-feedback-miner"))' "$SETT" >/dev/null 2>&1; then
  echo "  already wired — skipping"
else
  cp "$SETT" "$SETT.bak"
  tmp="$(mktemp)"
  # APPEND our hook group (never replace the array — other tools' hooks stay intact)
  jq --slurpfile snip "$REPO/settings.snippet.json" \
     '.hooks.SessionStart = ((.hooks.SessionStart // []) + $snip[0].hooks.SessionStart)' \
     "$SETT" > "$tmp" && mv "$tmp" "$SETT"
  echo "  appended (backup: $SETT.bak)"
fi

echo "✓ done — the miner runs in the background once per day, on your first session start."
echo "  tracker: ~/.local/share/claude-feedback/proposals.md"
