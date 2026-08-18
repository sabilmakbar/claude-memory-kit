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
# The kit's own dependencies come first, because a missing one silences everything
# else including the recording that this hook reports. Every other hook exits quietly
# without jq, so the fault would never be written down for the grace period to notice.
# This hook can say it because it uses no jq itself: reporting must not depend on the
# thing that broke.
command -v jq >/dev/null 2>&1 \
  || MSG="jq is not on PATH, so most of the memory kit is not running: the write guard, the version check and the edit-over-write guard all exit silently without it"

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

# Files left staged by an unfinished consolidation (DESIGN-memory.md D10). Staged
# files are deliberately invisible to the index, so these are memories the user HAS
# and that no session loads. install names the skill once and nothing repeats it, so
# without this the folder can sit for months holding memory nobody can reach. That is
# worse than an unfinished chore, which is why it is reported rather than left to
# whoever happens to remember.
_mk_staged="$(mk_memory_dir)/.staged"
if [ -d "$_mk_staged" ]; then
    _mk_n=$(find "$_mk_staged" -type f -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
    if [ "${_mk_n:-0}" -gt 0 ]; then
        case "$_mk_n" in 1) _mk_w="1 memory file is" ;; *) _mk_w="$_mk_n memory files are" ;; esac
        MSG="$MSG${MSG:+; }$_mk_w staged and loaded into no session: run /memory-kit:initialize-memory to finish bringing them in"
    fi
fi

[ -n "$MSG" ] || exit 0

mk_notice_stamp "$SID" health
mk_emit_notice "Memory kit health: $MSG."
