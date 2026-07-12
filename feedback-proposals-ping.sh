#!/bin/bash
# SessionStart hook: announce pending feedback proposals at the start of each session.
# Prints nothing when there are none.

PROPOSALS="$HOME/.local/share/claude-feedback/proposals.md"
[ -f "$PROPOSALS" ] || exit 0

# entries in the Pending section only; the miner keeps it sorted by score, so head-1 = top
PENDING=$(awk '/^## Pending/{p=1;next} /^## /{p=0} p && /^### P-/' "$PROPOSALS")
N=$(printf '%s' "$PENDING" | grep -c '^### P-')
[ "$N" -gt 0 ] || exit 0

TOP=$(printf '%s\n' "$PENDING" | head -1 | sed 's/^### //; s/["\\]//g')
printf '{"systemMessage": "%s feedback proposal(s) pending (top: %s). Say: review feedback proposals (tracker: ~/.local/share/claude-feedback/proposals.md)."}\n' "$N" "$TOP"
