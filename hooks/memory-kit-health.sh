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

# The two halves on different releases. Reported at once rather than after the grace
# period, for the same reason a legacy knob is: nothing is broken and one command fixes
# it, so waiting three days only delays the fix. It is last of the immediate clauses
# because it is the mildest: both halves work, they are just not the same version.
_mk_halves=$(mk_halves_mismatch) && MSG="$MSG${MSG:+; }$_mk_halves"

# The commit guardrail and the push pin on the memory repo. Both are plain settings in
# that repo's own git config, and each has gone missing before without a word: git then
# finds no hook file and runs nothing, so the repo looks guarded while the private-term
# check is off, and a push dies on a missing password. Reported at once, since the fix
# is one command. Only a store this kit manages (a marker beside it) and that lies inside
# this $HOME is expected to carry them: the installer wires nothing else.
_mk_store="$(mk_memory_dir)"
case "$_mk_store/" in "$HOME"/*)
  if [ -d "$_mk_store/.git" ] && [ -f "$_mk_store/.memory-kit-marker.json" ] \
     && command -v git >/dev/null 2>&1; then
    _mk_hp=$(git -C "$_mk_store" config --get core.hooksPath 2>/dev/null)
    case "$_mk_hp" in "") ;; /*) ;; *) _mk_hp="$_mk_store/$_mk_hp" ;; esac
    if [ -z "$_mk_hp" ]; then
      MSG="$MSG${MSG:+; }the commit guardrail is not wired on the memory repo (core.hooksPath is unset), so commits there skip the private-term check: re-run install.sh"
    elif [ ! -x "$_mk_hp/pre-commit" ]; then
      MSG="$MSG${MSG:+; }core.hooksPath on the memory repo points at $_mk_hp, which has no pre-commit hook, so commits there skip the private-term check: re-run install.sh"
    fi
    # Asked of git itself, with the answer discarded: only whether SOME helper supplies a
    # credential. A repo whose helper list was reset to nothing fails here, which is exactly
    # the state a lost pin leaves behind.
    case "$(git -C "$_mk_store" config --get remote.origin.url 2>/dev/null)" in
      https://github.com/*)
        _mk_user=$(git -C "$_mk_store" config --get credential.https://github.com.username 2>/dev/null)
        printf 'protocol=https\nhost=github.com\n%s\n' "${_mk_user:+username=$_mk_user}" \
          | GIT_TERMINAL_PROMPT=0 GCM_INTERACTIVE=never git -C "$_mk_store" credential fill >/dev/null 2>&1 \
          || MSG="$MSG${MSG:+; }no push credential resolves for the memory repo's GitHub remote, so a push there will fail: check gh auth status, or re-run install.sh"
        ;;
    esac
  fi ;;
esac

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
