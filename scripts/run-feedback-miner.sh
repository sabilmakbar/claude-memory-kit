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
    # remote/Linux VS Code uses ~/.vscode-server; desktop (incl. macOS) uses ~/.vscode
    CLAUDE_BIN=$(ls -t "$HOME"/.vscode-server/extensions/anthropic.claude-code-*/resources/native-binary/claude \
                       "$HOME"/.vscode/extensions/anthropic.claude-code-*/resources/native-binary/claude 2>/dev/null | head -1)
fi
[ -x "$CLAUDE_BIN" ] || exit 0
[ -f "$MINER_DOC" ] || exit 0

today=$(date +%F)
[ -f "$STAMP" ] && [ "$(cat "$STAMP")" = "$today" ] && exit 0
mkdir "$LOCK" 2>/dev/null || exit 0          # concurrent-session mutex
trap 'rmdir "$LOCK" 2>/dev/null' EXIT
echo "$today" > "$STAMP"                     # stamp BEFORE spawning: miner session can't re-trigger

# sync memory from remote first so the complementarity check sees other machines'
# memories, not yesterday's local copy. Never blocks the run: ff-only (no merges),
# no credential prompts, quiet failure on offline / dirty tree / not-a-repo.
GIT_TERMINAL_PROMPT=0 git -C "$HOME/.claude/memory" pull --ff-only --quiet >/dev/null 2>&1 || true

# window = since last successful extract; first run defaults to 26h back
now=$(date +%s)
if [ -f "$STATE" ]; then since=$(cat "$STATE"); else since=$(( now - 93600 )); fi

"$SCRIPT_DIR/extract-user-messages.sh" "$since" > "$PROP/digest-latest.txt"
if [ ! -s "$PROP/digest-latest.txt" ]; then
    echo "$now" > "$STATE"                   # nothing to mine; advance window
    exit 0
fi

cd "$PROP" || exit 0
TIMEOUT=""; command -v timeout >/dev/null 2>&1 && TIMEOUT="timeout 600"  # absent on stock macOS
$TIMEOUT "$CLAUDE_BIN" -p "Read $MINER_DOC and follow it exactly. [feedback-miner]" \
      --model "$MODEL" --allowedTools "Read,Write,Edit" \
      >> "$PROP/miner.log" 2>&1
# success = the tracker was actually (re)written this run — exit code alone lies
# (a session can exit 0 with its Write denied). Only then advance the extract window.
tracker_mtime=$(stat -c %Y "$PROP/proposals.md" 2>/dev/null || stat -f %m "$PROP/proposals.md" 2>/dev/null || echo 0)
if [ "$tracker_mtime" -ge "$now" ]; then
    echo "$now" > "$STATE"                   # promote window only on success — no lost messages
else
    echo "[$(date +%Y-%m-%dT%H:%M:%S%z)] miner run left no updated tracker; window not advanced" >> "$PROP/miner.log"
fi
