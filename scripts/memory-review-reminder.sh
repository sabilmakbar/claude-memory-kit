#!/bin/bash
# Shows a memory review reminder banner if 7+ days have passed since last review.
# Runs via SessionStart hook. Outputs JSON systemMessage when reminder is due.

LAST_REVIEW="$HOME/.claude/memory/.last-review"
WEEK_SECS=$((7 * 24 * 3600))
NOW=$(date +%s)

if [ ! -f "$LAST_REVIEW" ]; then
    ELAPSED=$((WEEK_SECS + 1))
else
    LAST=$(cat "$LAST_REVIEW")
    ELAPSED=$((NOW - LAST))
fi

if [ "$ELAPSED" -gt "$WEEK_SECS" ]; then
    DAYS=$(( ELAPSED / 86400 ))
    MSG="Memory review due (${DAYS} days since last). Ask me: review my memories and update preferences."
    # systemMessage = user-facing toast (not all UIs show it); additionalContext reaches Claude
    printf '{"systemMessage": "%s", "hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": "%s Mention this to the user at the start of your next reply."}}\n' "$MSG" "$MSG"
fi
