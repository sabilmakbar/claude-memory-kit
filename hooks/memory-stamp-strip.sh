#!/usr/bin/env bash
# hooks/memory-stamp-strip.sh — PostToolUse hook: strip harness-added
# node_type/originSessionId/modified keys from a memory file's frontmatter
# right after Claude Code's own writer stamps them on a Write or Edit.
#
# Wire it as:  "$HOME/.claude/memory-kit/hooks/memory-stamp-strip.sh" 2>/dev/null || true
#   matcher: Write|Edit, event: PostToolUse
#
# Why a hook rather than a review-time manual strip. These keys carry nothing
# across machines — originSessionId names a session that exists only on the
# machine that wrote it, and modified churns on every save — so a synced
# memory repo picked up pure metadata noise on every commit, and real content
# changes drowned in it. Stripping here means a memory file never leaves this
# machine with them in the first place; a review pass no longer has to do it.

set -u

KIT="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." 2>/dev/null && pwd)"
command -v jq >/dev/null 2>&1 || exit 0
[ -r "$KIT/core/lib.sh" ] || exit 0
. "$KIT/core/lib.sh"

input=$(cat 2>/dev/null) || exit 0
[ -n "$input" ] || exit 0

fp=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -n "$fp" ] || exit 0
[ -f "$fp" ] || exit 0

# scope: markdown inside the memory store or a mount, never the generated
# index or the repo's own docs — same scope memory-write-guard.sh checks.
_mk_store="$(mk_memory_dir)"
case "$fp" in
    "$_mk_store"/memory/*/*) exit 0 ;;
    "$_mk_store"/memory/*.md) ;;
    "$_mk_store"/*/*) exit 0 ;;
    "$_mk_store"/*.md|"$(mk_mounts_dir)"/*/*.md) ;;
    *) exit 0 ;;
esac
base="${fp##*/}"
mk_is_nonmemory "$base" && exit 0

# only touch files with real YAML frontmatter
[ "$(head -n1 "$fp" 2>/dev/null)" = "---" ] || exit 0

tmp="$(mktemp "${TMPDIR:-/tmp}/mk-stamp-strip.XXXXXX")" || exit 0
awk '
    BEGIN { infm = 0; fmdone = 0 }
    {
        if (!fmdone && $0 == "---") {
            infm = infm + 1
            print
            if (infm == 2) fmdone = 1
            next
        }
        if (infm == 1 && !fmdone) {
            if ($0 ~ /^[[:space:]]*node_type:[[:space:]]/) next
            if ($0 ~ /^[[:space:]]*originSessionId:[[:space:]]/) next
            if ($0 ~ /^[[:space:]]*modified:[[:space:]]/) next
            if ($0 ~ /^metadata:[[:space:]]+$/) { print "metadata:"; next }
        }
        print
    }
' "$fp" > "$tmp" 2>/dev/null || { rm -f "$tmp"; exit 0; }

# never overwrite with something emptied or truncated by a parsing edge case
[ -s "$tmp" ] || { rm -f "$tmp"; exit 0; }
cmp -s "$fp" "$tmp" 2>/dev/null && { rm -f "$tmp"; exit 0; }
mv "$tmp" "$fp"
exit 0
