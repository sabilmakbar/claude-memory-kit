#!/usr/bin/env bash
# hooks/memory-kit-health.sh — SessionStart hook: report a feature that has been
# blocked for a while, once a day, and stay quiet otherwise.
#
# Wire it as:  "$HOME/.claude/memory-kit/hooks/memory-kit-health.sh" 2>/dev/null || true
#
# The kit's background work fails quiet on purpose: a hook cannot tell a machine
# that skips a feature from one that is broken, and a warning on every session
# start becomes noise. So the scripts record WHY they could not run, and this hook
# reads those records. Two things keep it from nagging:
#   - a grace period, so a laptop offline over a weekend never triggers it
#   - one notice per session per day, the same marker rule the other notices use
# A feature that starts working clears its own record, so recovery is silent too.

set -u

KIT="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." 2>/dev/null && pwd)"
[ -r "$KIT/core/lib.sh" ] || exit 0
. "$KIT/core/lib.sh"

GRACE="${MEMORY_KIT_HEALTH_GRACE:-$(mk_conf MEMORY_KIT_HEALTH_GRACE 3 int)}"
case "$GRACE" in ''|*[!0-9]*) GRACE=3 ;; esac   # env half is unvalidated

SID=$(mk_session_id)
mk_notice_due "$SID" health || exit 0

MSG=""
# A knob still set under its old name is reported at once rather than after the
# grace period: it is already being ignored, and the fix is one edit away.
while IFS= read -r legacy; do
    [ -n "$legacy" ] || continue
    MSG="$MSG${MSG:+; }$legacy"
done <<EOF
$(mk_legacy_env)
EOF

for f in "$(mk_health_dir)"/*; do
    [ -f "$f" ] || continue                      # unexpanded glob when nothing is recorded
    blocked=$(mk_health_blocked "$(basename "$f")") || continue
    days=${blocked%% *}; reason=${blocked#* }
    [ "$days" -ge "$GRACE" ] 2>/dev/null || continue
    [ -n "$reason" ] || continue
    case "$days" in 1) age="1 day" ;; *) age="$days days" ;; esac
    MSG="$MSG${MSG:+; }$reason (for $age)"
done
[ -n "$MSG" ] || exit 0

mk_notice_stamp "$SID" health
mk_emit_notice "Memory kit health: $MSG."
