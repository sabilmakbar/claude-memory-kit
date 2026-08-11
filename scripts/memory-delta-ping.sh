#!/usr/bin/env bash
# UserPromptSubmit hook: tell a running session when memory files changed since its
# last check (issue #5). Zero cost when nothing changed:
#   - notices only fire when a memory file actually changed since this session's marker
#   - the marker advances on notice, so a change is announced once, not every turn
#   - at most one notice per THROTTLE seconds (default 1h) — bursts collapse into one
# stdout (exit 0) is appended to the prompt context by the harness.

_LIB="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." 2>/dev/null && pwd)/core/lib.sh"
[ -r "$_LIB" ] || exit 0
. "$_LIB"

sid=$(mk_session_id)
[ -z "$sid" ] && exit 0

MEM="$(mk_memory_dir)"
MOUNTS="$(mk_mounts_dir)"
MARKERS="$HOME/.claude/.memory-delta"
THROTTLE="${MEMORY_KIT_DELTA_THROTTLE:-$(mk_conf MEMORY_KIT_DELTA_THROTTLE 3600 int)}"
mkdir -p "$MARKERS"

marker="$MARKERS/$sid"
# first prompt of a session: set the baseline silently
if [ ! -f "$marker" ]; then
    touch "$marker"
    find "$MARKERS" -type f -mtime +7 -delete 2>/dev/null   # sweep stale session markers
    exit 0
fi

now=$(date +%s)
last=$(mk_mtime "$marker")
[ $((now - last)) -lt "$THROTTLE" ] && exit 0

# MEMORY.md is excluded — it regenerates every prompt and would fire forever
changed=$(find "$MEM" "$MOUNTS" -maxdepth 2 -name '*.md' ! -name 'MEMORY.md' -newer "$marker" 2>/dev/null \
    | sed "s|$HOME/.claude/||" | LC_ALL=C sort -u | paste -sd, - | sed 's/,/, /g')
[ -z "$changed" ] && exit 0

touch "$marker"
echo "Memory files changed since this session's last check: $changed — re-read the changed file(s) before relying on their content; the changed versions override what was loaded at session start."
