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

_LIB="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." 2>/dev/null && pwd)/core/lib.sh"
[ -r "$_LIB" ] || exit 0
. "$_LIB"

SID=$(mk_session_id)
mk_notice_due "$SID" review || exit 0

MEM="$(mk_memory_dir)"
WEEK_SECS=$((7 * 24 * 3600))
NOW=$(date +%s)
LABEL="${MEMORY_MACHINE_LABEL:-$(mk_conf MEMORY_MACHINE_LABEL "$(hostname -s)")}"

overdue() { # <epoch-or-empty> → "never" | days-overdue | "" (fresh)
    [ -z "$1" ] && { echo never; return; }
    local e=$((NOW - $1))
    [ "$e" -gt "$WEEK_SECS" ] && echo $((e / 86400))
}

UNREADABLE=""
if [ -d "$MEM/.git" ]; then
    # probe with rev-parse, not log: it answers "can git read this repo" without
    # needing a commit to exist, so a fresh repo still reports an honest "never"
    if git -C "$MEM" rev-parse --git-dir >/dev/null 2>&1; then
        ANY=$(git -C "$MEM" log --grep='^memory review' -1 --format=%ct 2>/dev/null)
        HERE=$(git -C "$MEM" log --grep="^memory review ($LABEL)" -1 --format=%ct 2>/dev/null)
    else
        # git missing or the repo unreadable. Claiming "never reviewed" here would
        # be a guess dressed as a fact, so say what is actually wrong instead.
        UNREADABLE=1
    fi
else
    ANY=""; [ -f "$MEM/.last-review" ] && ANY=$(cat "$MEM/.last-review")
    HERE="$ANY"
fi

if [ -n "$UNREADABLE" ]; then
    MSG="Memory review status unknown: the review history in ~/.claude/memory could not be read (git is missing or the repo is unreadable)"
    mk_health_record review "review history in ~/.claude/memory cannot be read, so review reminders are guessing"
    mk_notice_stamp "$SID" review
    mk_emit_notice "$MSG"
    exit 0
fi
mk_health_clear review

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
mk_notice_stamp "$SID" review   # written only when a notice is actually emitted
MSG="$MSG. Ask me: review my memories and update preferences."
mk_emit_notice "$MSG"
