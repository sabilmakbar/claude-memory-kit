#!/bin/bash
# Memory review reminder (SessionStart hook). Single source of truth: review-marker
# commits in the memory repo's history — subjects starting `memory review (<label>): `.
#  - a marker by ANY machine silences the synced-memories nag everywhere (history
#    arrives via the pulls the miner and skills already do; this hook stays offline)
#  - mount-local memories still need a marker from THIS machine's label
# No git repo → falls back to the machine-local .last-review stamp (no sync problem
# exists without a remote, so the stamp is not a second source of truth there).
#
# Repeats are bounded: the notice fires once per session per day (resumes and
# compactions stay silent; a new day re-notices). No readable session id → fail
# open and notice, exactly the pre-marker behavior.

SID=""
if [ ! -t 0 ]; then
    SID=$(jq -r '.session_id // empty' 2>/dev/null | tr -cd 'A-Za-z0-9_-')
fi
MARK=""
if [ -n "$SID" ]; then
    MARKDIR="$HOME/.claude/.notice-markers"; mkdir -p "$MARKDIR"
    MARK="$MARKDIR/$SID.review"
    [ "$(cat "$MARK" 2>/dev/null)" = "$(date +%F)" ] && exit 0
    find "$MARKDIR" -type f -mtime +7 -delete 2>/dev/null   # sweep stale session markers
fi

MEM="$HOME/.claude/memory"
WEEK_SECS=$((7 * 24 * 3600))
NOW=$(date +%s)
LABEL="${MEMORY_MACHINE_LABEL:-$(hostname -s)}"

overdue() { # <epoch-or-empty> → "never" | days-overdue | "" (fresh)
    [ -z "$1" ] && { echo never; return; }
    local e=$((NOW - $1))
    [ "$e" -gt "$WEEK_SECS" ] && echo $((e / 86400))
}

if [ -d "$MEM/.git" ]; then
    ANY=$(git -C "$MEM" log --grep='^memory review' -1 --format=%ct 2>/dev/null)
    HERE=$(git -C "$MEM" log --grep="^memory review ($LABEL)" -1 --format=%ct 2>/dev/null)
else
    ANY=""; [ -f "$MEM/.last-review" ] && ANY=$(cat "$MEM/.last-review")
    HERE="$ANY"
fi

MSG=""
case "$(overdue "$ANY")" in
    never) MSG="Memory review due (never recorded on any machine)";;
    "") ;;
    *) MSG="Memory review due ($(overdue "$ANY") days since last, any machine)";;
esac

if ls "$HOME/.claude/memory-mounts"/*/*.md >/dev/null 2>&1; then
    LMSG=""
    case "$(overdue "$HERE")" in
        never) LMSG="mount-local memories never reviewed on this machine";;
        "") ;;
        *) LMSG="mount-local memories on this machine unreviewed for $(overdue "$HERE") days";;
    esac
    if [ -n "$LMSG" ]; then
        if [ -n "$MSG" ]; then MSG="$MSG; $LMSG"; else MSG="Memory review due ($LMSG)"; fi
    fi
fi

[ -z "$MSG" ] && exit 0
[ -n "$MARK" ] && date +%F > "$MARK"   # marker written only when a notice is emitted
MSG="$MSG. Ask me: review my memories and update preferences."
# systemMessage = user-facing toast (not all UIs show it); additionalContext reaches Claude
printf '{"systemMessage": "%s", "hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": "%s Mention this to the user at the start of your next reply."}}\n' "$MSG" "$MSG"
