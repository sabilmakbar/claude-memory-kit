#!/bin/bash
# Daily feedback miner: extracts user messages since last successful run, then has a
# headless Claude update the proposals tracker per feedback-miner.md.
# Invoked (backgrounded) from a SessionStart hook; guards make it run ≤ once per day.
# Tracker lives OUTSIDE ~/.claude — headless sessions can't write there (sensitive-file rule).

PROP="$HOME/.local/share/claude-feedback"
STAMP="$PROP/.last-run-date"
STATE="$PROP/.last-extract-epoch"
LOCK="$PROP/.lock"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MINER_DOC="$SCRIPT_DIR/feedback-miner.md"    # installed alongside this script
MODEL="${FEEDBACK_MINER_MODEL:-sonnet}"
mkdir -p "$PROP"

# resolve the claude CLI: PATH first, else the newest VS Code extension's bundled binary
CLAUDE_BIN=$(command -v claude 2>/dev/null)
if [ -z "$CLAUDE_BIN" ]; then
    CLAUDE_BIN=$(ls -t "$HOME"/.vscode-server/extensions/anthropic.claude-code-*/resources/native-binary/claude 2>/dev/null | head -1)
fi
[ -x "$CLAUDE_BIN" ] || exit 0
[ -f "$MINER_DOC" ] || exit 0

today=$(date +%F)
[ -f "$STAMP" ] && [ "$(cat "$STAMP")" = "$today" ] && exit 0
mkdir "$LOCK" 2>/dev/null || exit 0          # concurrent-session mutex
trap 'rmdir "$LOCK" 2>/dev/null' EXIT
echo "$today" > "$STAMP"                     # stamp BEFORE spawning: miner session can't re-trigger

# window = since last successful extract; first run defaults to 26h back
now=$(date +%s)
if [ -f "$STATE" ]; then since=$(cat "$STATE"); else since=$(( now - 93600 )); fi

"$SCRIPT_DIR/extract-user-messages.sh" "$since" > "$PROP/digest-latest.txt"
if [ ! -s "$PROP/digest-latest.txt" ]; then
    echo "$now" > "$STATE"                   # nothing to mine; advance window
    exit 0
fi

cd "$PROP" || exit 0
timeout 600 "$CLAUDE_BIN" -p "Read $MINER_DOC and follow it exactly. [feedback-miner]" \
      --model "$MODEL" --allowedTools "Read,Write,Edit" \
      >> "$PROP/miner.log" 2>&1
# success = the tracker was actually (re)written this run — exit code alone lies
# (a session can exit 0 with its Write denied). Only then advance the extract window.
if [ -f "$PROP/proposals.md" ] && [ "$(stat -c %Y "$PROP/proposals.md")" -ge "$now" ]; then
    echo "$now" > "$STATE"                   # promote window only on success — no lost messages
else
    echo "[$(date -Is)] miner run left no updated tracker; window not advanced" >> "$PROP/miner.log"
fi
