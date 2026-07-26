#!/bin/bash
# Ensures the current project's Claude memory dir is symlinked to the central store,
# and injects the current mount's memory entries into the central MEMORY.md.
# Runs automatically via UserPromptSubmit hook. Safe to run repeatedly (idempotent).

CENTRAL="$HOME/.claude/memory"
CENTRAL_MD="$CENTRAL/MEMORY.md"
MOUNTS_BASE="$HOME/.claude/memory-mounts"
mkdir -p "$CENTRAL" "$MOUNTS_BASE"

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
ENCODED=$(echo "$PROJECT_DIR" | tr '/' '-')
MEMORY_DIR="$HOME/.claude/projects/$ENCODED/memory"

# Step 1: Ensure project memory → central symlink
if ! { [ -L "$MEMORY_DIR" ] && [ "$(readlink "$MEMORY_DIR")" = "$CENTRAL" ]; }; then
    mkdir -p "$(dirname "$MEMORY_DIR")"
    if [ -d "$MEMORY_DIR" ] && [ ! -L "$MEMORY_DIR" ]; then
        find "$MEMORY_DIR" -maxdepth 1 -type f -exec cp -n {} "$CENTRAL/" \; 2>/dev/null || true
        # keep the old dir as a backup: cp -n skips name collisions and never copies
        # subdirs, so deleting here would silently destroy them
        mv "$MEMORY_DIR" "$MEMORY_DIR.pre-kit.$(date +%s).bak"
    fi
    ln -sfn "$CENTRAL" "$MEMORY_DIR"
fi

# Step 2: Detect current mount point
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

# Step 3: Rebuild MEMORY.md = fixed header + index generated from the memory files.
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
    case "$b" in MEMORY.md|README.md|CLAUDE.md|DEPENDENCIES.md|HOW-IT-WORKS.md|user_*.md|feedback_*.md) ;; *) unindexed="$unindexed${unindexed:+, }$b" ;; esac
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
