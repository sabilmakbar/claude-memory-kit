#!/usr/bin/env bash
# Print the Claude Code version present on this machine, best source first:
#   1. running processes (~/.claude/sessions/*.json, the ground truth while live)
#   2. newest installed VS Code extension (dir name carries the version)
#   3. `claude --version` if a binary is reachable
# Prints nothing and exits 1 when none resolve. Read-only.

set -u

best=""
for f in "$HOME"/.claude/sessions/*.json; do
    [ -r "$f" ] || continue
    v=$(jq -r '.version // empty' "$f" 2>/dev/null)
    [ -n "$v" ] || continue
    # keep the highest version seen (sort -V is GNU; fall back to plain sort)
    best=$(printf '%s\n%s\n' "$best" "$v" | grep -v '^$' | sort -V 2>/dev/null | tail -1 \
        || printf '%s\n%s\n' "$best" "$v" | grep -v '^$' | sort | tail -1)
done
[ -n "$best" ] && { printf '%s\n' "$best"; exit 0; }

for d in "$HOME"/.vscode/extensions/anthropic.claude-code-* \
         "$HOME"/.vscode-server/extensions/anthropic.claude-code-*; do
    [ -d "$d" ] || continue
    v=$(basename "$d" | sed 's/^anthropic\.claude-code-//; s/-[a-z0-9]*-[a-z0-9]*$//')
    [ -n "$v" ] || continue
    best=$(printf '%s\n%s\n' "$best" "$v" | grep -v '^$' | sort -V 2>/dev/null | tail -1 \
        || printf '%s\n%s\n' "$best" "$v" | grep -v '^$' | sort | tail -1)
done
[ -n "$best" ] && { printf '%s\n' "$best"; exit 0; }

if command -v claude >/dev/null 2>&1; then
    v=$(claude --version 2>/dev/null | awk '{print $1; exit}')
    [ -n "$v" ] && { printf '%s\n' "$v"; exit 0; }
fi
exit 1
