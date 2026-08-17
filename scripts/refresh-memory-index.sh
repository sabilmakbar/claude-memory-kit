#!/bin/bash
# Regenerates the central MEMORY.md index, including the current mount's entries, and
# reports memory files whose frontmatter carries harness-stamped keys.
# Runs automatically via UserPromptSubmit hook. Safe to run repeatedly (idempotent).
#
# It writes the generated index and nothing else. A memory file is the user's, and
# DESIGN-memory.md D7 and D8 put every change to one behind a person: managed says
# what it will do first, and a hook cannot hold that conversation.

_LIB="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." 2>/dev/null && pwd)/core/lib.sh"
[ -r "$_LIB" ] && . "$_LIB"

# Asked, not recomputed. This line carried its own copy of the default, so an
# install that adopted a different store had the index built in an empty
# directory while the real memories sat unindexed elsewhere. lib.sh may be
# unreadable here (the sourcing above is conditional), hence the same fallback.
CENTRAL="$(mk_memory_dir 2>/dev/null || printf '%s/.claude/memory' "$HOME")"
CENTRAL_MD="$CENTRAL/MEMORY.md"
MOUNTS_BASE="$HOME/.claude/memory-mounts"
mkdir -p "$CENTRAL" "$MOUNTS_BASE"

# Used only to find the mount below. The kit no longer derives where Claude Code keeps
# memory: install names it with autoMemoryDirectory (DESIGN-memory.md D8). Deriving it
# was wrong two ways, and both are gone with the code rather than fixed in it: dots
# were not replaced (O11), and memory comes from the git root while this value is a
# working directory (O13). Issue 40.
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"

# Report harness-stamped frontmatter keys (issue #16). Claude Code's native memory
# writer adds node_type / originSessionId / modified on every save; none carry
# cross-machine value, and `modified` churns on every write (commit noise, merge
# friction).
#
# This pass used to strip them in place and name afterwards what it had touched.
# Announcing after the fact is the wrong order once managed must announce before, and
# a hook has nobody to ask, so the hook reports and /review-memories does the strip.
STAMPED='^[[:space:]]*(node_type|originSessionId|modified):'
STAMPED_FILES=""
find_stamped() { # <dir> — name root-level .md files whose FRONTMATTER carries a stamp
    for f in $(grep -lE "$STAMPED" "$1"/*.md 2>/dev/null); do
        case "$(basename "$f")" in MEMORY.md) continue ;; esac
        [ "$(head -1 "$f")" = "---" ] || continue
        end=$(awk 'NR>1 && /^---$/ {print NR; exit}' "$f")
        [ -n "$end" ] && [ "$end" -gt 2 ] || continue
        # the candidate grep saw the whole file; confirm the stamp sits in the
        # frontmatter rather than the body, so a rule that merely writes "modified:"
        # in its text is never named
        sed -n "2,$((end-1))p" "$f" | grep -qE "$STAMPED" || continue
        STAMPED_FILES="$STAMPED_FILES${STAMPED_FILES:+, }$(basename "$f")"
    done
}
find_stamped "$CENTRAL"

# Step 1: Detect current mount point
MOUNT=$(df -P "$PROJECT_DIR" 2>/dev/null | awk 'NR==2 {print $NF}')
[ -z "$MOUNT" ] && exit 0

# Root mount uses $HOME as the identifier (more meaningful than "/")
if [ "$MOUNT" = "/" ]; then
    MOUNT_LABEL="~"
    MOUNT_ENCODED=$(echo "$HOME" | tr '/' '-')
else
    MOUNT_LABEL="$MOUNT"
    MOUNT_ENCODED=$(echo "$MOUNT" | tr '/' '-')
fi
MOUNT_MEMORY="$MOUNTS_BASE/$MOUNT_ENCODED"
mkdir -p "$MOUNT_MEMORY"
find_stamped "$MOUNT_MEMORY"

# Say it, at most once a day. Claude Code re-stamps `modified` on every native save, so
# the same files qualify again the moment they are cleaned; an unthrottled report would
# fire on nearly every prompt and become noise nobody reads, which is worse than the
# silent rewrite it replaces. Same throttle as the review reminder and the proposals ping.
if [ -n "$STAMPED_FILES" ] && command -v mk_notice_due >/dev/null 2>&1; then
    _SID=$(mk_session_id 2>/dev/null || printf '')
    if mk_notice_due "$_SID" heal 2>/dev/null; then
        mk_notice_stamp "$_SID" heal 2>/dev/null
        echo "Harness-stamped frontmatter keys (node_type, originSessionId, modified) are in the frontmatter of: $STAMPED_FILES. They carry no value across machines and churn on every save. Run /review-memories to strip them. Nothing has been changed."
    fi
fi

# Step 2: Rebuild MEMORY.md = fixed header + index generated from the memory files.
# The index is derived from each file's frontmatter, so it can never drift out of
# sync with the files that actually exist (no writer can silently drop an entry).
cat > "$CENTRAL_MD" <<'HDR'
# Memory Index
> Two-tier system: global memories always load; mount-specific appear in "## Mount:" section below.
> Write global preferences/feedback to ~/.claude/memory/; write filesystem/project-specific memories to ~/.claude/memory-mounts/<encoded-mount>/ (mount path with `/` replaced by `-`).

HDR

# user_* first, then feedback_* alphabetically; index line = derived title + the file's description
for f in $(ls "$CENTRAL"/user_*.md 2>/dev/null) $(ls "$CENTRAL"/feedback_*.md 2>/dev/null | sort); do
    [ -f "$f" ] || continue
    b=$(basename "$f"); slug=${b%.md}
    desc=$(sed -n 's/^description:[[:space:]]*//p' "$f" | head -1)
    case "$desc" in \"*\") desc=${desc#\"}; desc=${desc%\"} ;; esac  # unwrap only fully-quoted values
    case "$slug" in
        user_*) title="User profile" ;;
        *) t=${slug#feedback_}
           title=$(printf '%s' "$t" | tr '_' ' ' \
               | awk '{for(i=1;i<=NF;i++){if($i=="gh")$i="GitHub";else if($i=="gpu")$i="GPU"}}1')
           title="$(printf '%s' "${title:0:1}" | tr '[:lower:]' '[:upper:]')${title:1}" ;;
    esac
    printf -- '- [%s](%s) — %s\n' "$title" "$b" "$desc" >> "$CENTRAL_MD"
done

# Surface non-conforming .md files so adopted memories can't silently drop out of recall
unindexed=""
for f in "$CENTRAL"/*.md; do
    [ -f "$f" ] || continue
    b=$(basename "$f")
    # known non-memory docs (same exemptions as the guardrail lint) are not "unindexed"
    case "$b" in MEMORY.md|README.md|CLAUDE.md|CONTRIBUTING.md|CHANGELOG.md|DEPENDENCIES.md|HOW-IT-WORKS.md|user_*.md|feedback_*.md) ;; *) unindexed="$unindexed${unindexed:+, }$b" ;; esac
done
if [ -n "$unindexed" ]; then
    printf '\n> ⚠ Unindexed files in ~/.claude/memory — not loaded into any session. Rename to user_*/feedback_* (project files belong in memory-mounts): %s\n' "$unindexed" >> "$CENTRAL_MD"
fi

# Collect non-MEMORY.md files in mount memory dir and append section
MOUNT_MD="$MOUNT_MEMORY/MEMORY.md"
if [ -f "$MOUNT_MD" ] && find "$MOUNT_MEMORY" -maxdepth 1 -name "*.md" ! -name "MEMORY.md" | grep -q .; then
    printf '\n## Mount: %s\n' "$MOUNT_LABEL" >> "$CENTRAL_MD"
    re='^- \[([^]]+)\]\(([^)]+)\)(.*)'
    while IFS= read -r line; do
        if [[ "$line" =~ $re ]]; then
            title="${BASH_REMATCH[1]}"
            filepath="${BASH_REMATCH[2]}"
            rest="${BASH_REMATCH[3]}"
            [[ "$filepath" != /* ]] && filepath="$MOUNT_MEMORY/$filepath"
            printf -- '- [%s](%s)%s\n' "$title" "$filepath" "$rest"
        fi
    done < "$MOUNT_MD" >> "$CENTRAL_MD"
fi
