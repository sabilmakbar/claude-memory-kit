#!/bin/bash
# SessionStart hook: announce pending feedback proposals at the start of each session.
# Prints nothing when there are none. Fires once per session per day (resumes and
# compactions stay silent); no readable session id → fail open and notice.

PROPOSALS="$HOME/.local/share/claude-feedback/proposals.md"
[ -f "$PROPOSALS" ] || exit 0

SID=""
if [ ! -t 0 ]; then
    SID=$(jq -r '.session_id // empty' 2>/dev/null | tr -cd 'A-Za-z0-9_-')
fi
MARK=""
if [ -n "$SID" ]; then
    MARKDIR="$HOME/.claude/.notice-markers"; mkdir -p "$MARKDIR"
    MARK="$MARKDIR/$SID.proposals"
    [ "$(cat "$MARK" 2>/dev/null)" = "$(date +%F)" ] && exit 0
    find "$MARKDIR" -type f -mtime +7 -delete 2>/dev/null   # sweep stale session markers
fi

# entries in the Pending section only; the miner keeps it sorted by score, so head-1 = top
PENDING=$(awk '/^## Pending/{p=1;next} /^## /{p=0} p && /^### P-/' "$PROPOSALS")
N=$(printf '%s' "$PENDING" | grep -c '^### P-')
[ "$N" -gt 0 ] || exit 0

[ -n "$MARK" ] && date +%F > "$MARK"   # marker written only when a notice is emitted
TOP=$(printf '%s\n' "$PENDING" | head -1 | sed 's/^### //; s/["\\]//g')
MSG="$N feedback proposal(s) pending (top: $TOP). Say: review feedback proposals (tracker: ~/.local/share/claude-feedback/proposals.md)."
# emit both: systemMessage = user-facing toast (not all UIs show it);
# additionalContext = injected into Claude's context so it can relay the ping in-reply
printf '{"systemMessage": "%s", "hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": "%s Mention this to the user at the start of your next reply."}}\n' "$MSG" "$MSG"
