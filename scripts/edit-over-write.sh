#!/bin/bash
# PreToolUse hook (Write): force Edit on files that already exist, so every change
# to an existing file produces an auditable line diff (add/edit/remove) instead of
# an opaque full-file overwrite. New files -> Write is allowed (nothing to diff).
# Fails open: any parse problem or missing jq lets the Write through.

input=$(cat)
command -v jq >/dev/null 2>&1 || exit 0
fp=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty')
[ -z "$fp" ] && exit 0

if [ -e "$fp" ]; then
  cat <<'EOF'
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"This file already exists — use the Edit tool instead of Write so the change shows an auditable line diff (add/edit/remove). Write is for new files only. If a full rewrite is genuinely required, delete the file first (or ask the user to disable this hook)."}}
EOF
fi
exit 0
