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
MSG="$N feedback proposal(s) pending (top: $TOP). Say: review feedback proposals (tracker: ~/.local/share/claude-feedback/proposals.md)."
# emit both: systemMessage = user-facing toast (not all UIs show it);
# additionalContext = injected into Claude's context so it can relay the ping in-reply
printf '{"systemMessage": "%s", "hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": "%s Mention this to the user at the start of your next reply."}}\n' "$MSG" "$MSG"
