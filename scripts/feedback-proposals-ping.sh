#!/bin/bash
# SessionStart hook: announce pending feedback proposals at the start of each session.
# Prints nothing when there are none. Fires once per session per day (resumes and
# compactions stay silent); no readable session id → fail open and notice.

_LIB="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." 2>/dev/null && pwd)/core/lib.sh"
[ -r "$_LIB" ] || exit 0
. "$_LIB"

PROPOSALS="$(mk_tracker_dir)/proposals.md"
[ -f "$PROPOSALS" ] || exit 0

SID=$(mk_session_id)
mk_notice_due "$SID" proposals || exit 0

# entries in the Pending section only; the miner keeps it sorted by score, so head-1 = top
PENDING=$(awk '/^## Pending/{p=1;next} /^## /{p=0} p && /^### P-/' "$PROPOSALS")
N=$(printf '%s' "$PENDING" | grep -c '^### P-')
[ "$N" -gt 0 ] || exit 0

mk_notice_stamp "$SID" proposals   # written only when a notice is actually emitted
TOP=$(printf '%s\n' "$PENDING" | head -1 | sed 's/^### //; s/["\\]//g')
MSG="$N feedback proposal(s) pending (top: $TOP). Say: review feedback proposals (tracker: ~/.local/share/claude-feedback/proposals.md)."
mk_emit_notice "$MSG"
