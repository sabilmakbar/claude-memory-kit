#!/usr/bin/env bash
# hooks/memory-write-guard.sh — PreToolUse hook: hold memory files to the kit's
# conventions at the moment they are written, and say which rule was missed.
#
# Wire it as:  "$HOME/.claude/memory-kit/hooks/memory-write-guard.sh" 2>/dev/null || true
#   matcher: Write|Edit
#
# Why a hook rather than a memory file. These rules used to ship as two seeded
# memory files, which made kit instructions live inside the user's data: they cost
# context in every session, could be edited into drift, and nothing verified that a
# write actually followed them. The commit guardrail runs the same seven, from this
# at commit time and only where a git repo exists, so memory-mounts were never
# checked at all. Here the check runs at write time, everywhere, with no repo.
#
# Only rules that hold for EVERY legitimate file are enforced. A rule that would
# refuse real, correct files belongs in the guidance doc instead:
#   - `**How to apply:**` is optional; a prescriptive rule can carry its own how.
#   - `**Why:**` is required for feedback_ rules but not for a user_ profile.
#   - a [[wikilink]] may point at a memory not written yet, so links are never
#     resolved here.
# Anything unparseable fails open: a hook that blocks writes on its own confusion
# is worse than the drift it prevents.

set -u

KIT="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." 2>/dev/null && pwd)"
GUIDE="$HOME/.claude/memory-kit/guidance/memory-authoring.md"

# Self-describing, so prose and code cannot drift apart. This is the canonical list
# of what is enforced; tests bind it three ways: every id must have a deny site here,
# every id must be marked in the guidance, and the guidance may name no other.
MK_RULES="filename-prefix name-matches-slug description-required type-required origin-required why-required-for-feedback no-evidence-when-synced"
if [ "${1:-}" = "--rules" ]; then printf '%s\n' $MK_RULES; exit 0; fi

command -v jq >/dev/null 2>&1 || exit 0
[ -r "$KIT/core/lib.sh" ] || exit 0
. "$KIT/core/lib.sh"

input=$(cat 2>/dev/null) || exit 0
[ -n "$input" ] || exit 0

fp=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -n "$fp" ] || exit 0

# scope: markdown inside the memory store or a mount, never the generated index or
# the repo's own docs
# Resolved once. mk_memory_dir reads a setting through jq now, and this hook runs on
# every Write and Edit, so calling it per case statement pays for the lookup twice on
# a path where it used to be a printf.
_mk_store="$(mk_memory_dir)"
case "$fp" in
    "$_mk_store"/*.md|"$(mk_mounts_dir)"/*/*.md) ;;
    *) exit 0 ;;
esac
base="${fp##*/}"
mk_is_nonmemory "$base" && exit 0

# Write carries the whole file; Edit carries only a fragment, so a rule is checked
# only when the fragment actually contains the line it governs. Never guess at
# what the rest of the file says.
whole=""
content=$(printf '%s' "$input" | jq -r '.tool_input.content // empty' 2>/dev/null)
if [ -n "$content" ]; then
    whole=1
else
    content=$(printf '%s' "$input" | jq -r '.tool_input.new_string // empty' 2>/dev/null)
fi
[ -n "$content" ] || exit 0

slug="${base%.md}"
deny() {  # deny <rule-id> <message>; the id is what the tests bind to the guidance
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":%s}}\n' \
        "$(printf '%s Fix it and write again. The conventions and a template are at %s' "$2" "$GUIDE" | jq -Rs .)"
    exit 0
}
has() { printf '%s' "$content" | grep -q "$1"; }

# 1. type-prefixed filename (checkable from the path alone, so it applies to Edit too)
case "$slug" in
    user_*|feedback_*|project_*) ;;
    *) deny filename-prefix "A memory filename must start with user_, feedback_ or project_, and '$base' does not. Global preferences are feedback_, facts about the user are user_, and project-specific notes are project_ and belong in memory-mounts." ;;
esac

# 2. name: must equal the filename slug — the index and every [[wikilink]] key off it
if has '^name:'; then
    name=$(printf '%s' "$content" | sed -n 's/^name:[[:space:]]*//p' | head -1 | tr -d '[:space:]')
    [ "$name" = "$slug" ] || deny name-matches-slug "The name field must equal the filename slug: '$slug', not '$name'. The generated index and every [[wikilink]] resolve through it, and the harness suggests a kebab-case name that breaks both."
fi

# 3, 4, 5. whole-file rules: only a Write shows enough to judge absence
if [ -n "$whole" ]; then
    has '^description:' || deny description-required "A memory file needs a description line in its frontmatter. It is the index entry and what recall reads to judge whether the file is relevant, so a file without one is close to invisible."
    has '^[[:space:]]*type:' || deny type-required "A memory file needs a type in its metadata: user, feedback, project or reference."
    has '^[[:space:]]*source: \(direct\|feedback-miner\)$' \
      || deny origin-required "A memory file must state where it came from: source: direct when you decided the rule, or source: feedback-miner when a mined proposal was accepted. Nothing follows either value, and no later edit changes it; what a review did to the rule belongs in the commit message. A proposal id would name a tracker entry that only one machine can resolve."
    case "$slug" in
        feedback_*)
            has '^\*\*Why:\*\*' || deny why-required-for-feedback "A feedback rule needs a **Why:** line giving the generalized reason it matters. Without it the rule reads as an arbitrary instruction and gets ignored or misapplied later." ;;
    esac
fi

# 6. no incident evidence inside a synced file, whichever tool is writing
case "$fp" in
    "$_mk_store"/*)
        if has '^\*\*Evidence' || has '^#\{1,6\}[[:space:]]*Evidence'; then
            deny no-evidence-when-synced "Global memory files carry no Evidence section. Quotes, repo names and paths stay in the miner tracker and git history; distil the lesson into Why and How instead. This file syncs to a personal GitHub repo, which is why the leak surface was removed rather than policed."
        fi ;;
esac

exit 0
