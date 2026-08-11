#!/bin/bash
# Daily feedback miner: extracts user messages since last successful run, then has a
# headless Claude update the proposals tracker per feedback-miner.md.
# Invoked (backgrounded) from a SessionStart hook; guards make it run ≤ once per day.
# Tracker lives OUTSIDE ~/.claude — headless sessions can't write there (sensitive-file rule).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_LIB="$SCRIPT_DIR/../core/lib.sh"
[ -r "$_LIB" ] || exit 0
. "$_LIB"

PROP="$(mk_tracker_dir)"
STAMP="$PROP/.last-run-date"
STATE="$PROP/.last-extract-epoch"
LOCK="$PROP/.lock"
MINER_DOC="$SCRIPT_DIR/feedback-miner.md"    # ships alongside this script
MODEL="${MEMORY_KIT_MINER_MODEL:-$(mk_conf MEMORY_KIT_MINER_MODEL sonnet)}"
mkdir -p "$PROP"

# A machine can skip the miner on purpose. Saying so explicitly is what lets the
# health notice treat every other silence as a fault worth reporting.
if ! mk_conf_off "${MEMORY_KIT_NO_MINER:-$(mk_conf MEMORY_KIT_NO_MINER '')}"; then
    mk_health_clear miner
    exit 0
fi

CLAUDE_BIN=$(mk_claude_bin) || {
    mk_health_record miner "the feedback miner cannot run: no claude CLI on PATH or in a VS Code extension"
    exit 0
}
[ -f "$MINER_DOC" ] || {
    mk_health_record miner "the feedback miner cannot run: its brief is missing from the kit"
    exit 0
}

today=$(date +%F)
[ -f "$STAMP" ] && [ "$(cat "$STAMP")" = "$today" ] && exit 0
mkdir "$LOCK" 2>/dev/null || exit 0          # concurrent-session mutex
trap 'rmdir "$LOCK" 2>/dev/null' EXIT
echo "$today" > "$STAMP"                     # stamp BEFORE spawning: miner session can't re-trigger

# sync memory from remote first so the complementarity check sees other machines'
# memories, not yesterday's local copy. Never blocks the run: ff-only (no merges),
# no credential prompts. A failure is recorded rather than swallowed, because an
# unreachable remote looks exactly like a healthy one from in here.
if sync_reason=$(mk_memory_pull); then
    mk_health_clear sync
else
    mk_health_record sync "$sync_reason"
fi

# window = since last successful extract; first run defaults to 26h back
now=$(date +%s)
if [ -f "$STATE" ]; then since=$(cat "$STATE"); else since=$(( now - 93600 )); fi

"$SCRIPT_DIR/extract-user-messages.sh" "$since" > "$PROP/digest-latest.txt"
if [ ! -s "$PROP/digest-latest.txt" ]; then
    echo "$now" > "$STATE"                   # nothing to mine; advance window
    mk_health_clear miner                    # it ran fine, there was just nothing to do
    exit 0
fi

cd "$PROP" || exit 0
# one run of log history, bounded: previous run's log -> miner.log.1, fresh log this run
[ -f "$PROP/miner.log" ] && mv -f "$PROP/miner.log" "$PROP/miner.log.1"
TIMEOUT=""; command -v timeout >/dev/null 2>&1 && TIMEOUT="timeout 600"  # absent on stock macOS
# stream-json --verbose = full turn-by-turn trace in the log (plain --verbose adds
# nothing in text mode); this is what makes the session transcript redundant below
$TIMEOUT "$CLAUDE_BIN" -p "Read $MINER_DOC and follow it exactly. [feedback-miner]" \
      --model "$MODEL" --allowedTools "Read,Write,Edit" \
      --output-format stream-json --verbose \
      >> "$PROP/miner.log" 2>&1
# success = the tracker was actually (re)written this run — exit code alone lies
# (a session can exit 0 with its Write denied). Only then advance the extract window.
tracker_mtime=$(mk_mtime "$PROP/proposals.md")
if [ "$tracker_mtime" -ge "$now" ]; then
    echo "$now" > "$STATE"                   # promote window only on success — no lost messages
    mk_health_clear miner
else
    echo "[$(date +%Y-%m-%dT%H:%M:%S%z)] miner run left no updated tracker; window not advanced" >> "$PROP/miner.log"
    mk_health_record miner "the feedback miner ran but wrote no tracker update; see miner.log"
fi

# the headless run above wrote a session transcript that is title-less, byte-identical
# to every other miner session, and fully redundant with the verbose log — delete, so
# miner runs never clutter session listings. Covers both project-dir encodings ('.'
# kept vs mapped to '-'; varies by Claude Code version). All sessions in these dirs
# are miner-owned: the tracker dir is the miner's cwd and nothing else runs there.
for enc in "$(echo "$PROP" | tr '/' '-')" "$(echo "$PROP" | tr '/.' '--')"; do
    rm -f "$HOME/.claude/projects/$enc"/*.jsonl 2>/dev/null
done
