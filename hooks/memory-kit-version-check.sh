#!/usr/bin/env bash
# hooks/memory-kit-version-check.sh — SessionStart hook: re-verify the kit after Claude Code
# updates, so nobody has to remember to.
#
# Wire it as:  "$HOME/.claude/memory-kit/hooks/memory-kit-version-check.sh" 2>/dev/null || true
# (the name is kit-prefixed so settings dedup-by-basename never collides with a
#  sibling kit's version-check; it runs from whichever tree it lives in — the
#  deployed tree in normal use — and stamps .verified next to itself)
#
# Normal case costs one version lookup and one file read, then exit. When the version
# moved, the smoke suite runs ONCE per version per day, backgrounded, so session start
# never waits. It prints nothing, ever: on success smoke.sh stamps .verified and this
# hook goes quiet; on failure nothing is stamped and .smoke-last.log holds the receipt
# — the missing stamp is the report.

set -u

KIT="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." 2>/dev/null && pwd)"
[ -r "$KIT/tests/smoke.sh" ] || exit 0
[ -r "$KIT/core/lib.sh" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0
. "$KIT/core/lib.sh"

cur=$(mk_claude_version 2>/dev/null)
[ -n "$cur" ] || exit 0

seen=""
[ -r "$KIT/.verified" ] && seen=$(head -1 "$KIT/.verified" 2>/dev/null | tr -d '[:space:]')
[ "$cur" = "$seen" ] && exit 0

# one attempt per (version, day) — a persistently failing suite must not re-run
# on every session start
mark="$cur $(date +%F)"
[ -r "$KIT/.smoke-attempt" ] && [ "$(cat "$KIT/.smoke-attempt" 2>/dev/null)" = "$mark" ] && exit 0
printf '%s\n' "$mark" > "$KIT/.smoke-attempt"

( bash "$KIT/tests/smoke.sh" --quiet > "$KIT/.smoke-last.log" 2>&1 </dev/null & ) >/dev/null 2>&1
exit 0
