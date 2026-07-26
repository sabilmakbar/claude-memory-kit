#!/usr/bin/env bash
# claude-memory-kit installer.
#   git clone <repo> ~/claude-memory-kit && ~/claude-memory-kit/install.sh
# Deploys the memory engine, hooks, miner, skills, and seed memories into ~/.claude.
# Idempotent: safe to re-run after updating the repo.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE="$HOME/.claude"
SETT="$CLAUDE/settings.json"
mkdir -p "$CLAUDE/scripts" "$CLAUDE/skills" "$CLAUDE/memory"

echo "→ checking prerequisites (see DEPENDENCIES.md)"
command -v jq >/dev/null 2>&1 || { echo "  ✗ jq required — install it and re-run"; exit 1; }
for t in git gh; do command -v "$t" >/dev/null 2>&1 && echo "  ✓ $t" || echo "  ✗ $t missing"; done
if command -v claude >/dev/null 2>&1 \
   || ls "$HOME"/.vscode-server/extensions/anthropic.claude-code-*/resources/native-binary/claude >/dev/null 2>&1 \
   || ls "$HOME"/.vscode/extensions/anthropic.claude-code-*/resources/native-binary/claude >/dev/null 2>&1; then
  echo "  ✓ claude CLI"
else
  echo "  ! claude CLI not found on PATH or in a VS Code extension — the miner no-ops until it is"
fi

echo "→ installing scripts to ~/.claude/scripts"
for f in "$REPO"/scripts/*.sh; do install -m 0755 "$f" "$CLAUDE/scripts/$(basename "$f")"; done
for f in "$REPO"/scripts/*.md; do install -m 0644 "$f" "$CLAUDE/scripts/$(basename "$f")"; done

echo "→ installing skills to ~/.claude/skills"
cp -r "$REPO"/skills/* "$CLAUDE/skills/"

echo "→ seeding memory-authoring conventions into ~/.claude/memory (existing files kept)"
for f in "$REPO"/seed-memories/*.md; do
  t="$CLAUDE/memory/$(basename "$f")"
  [ -f "$t" ] || install -m 0644 "$f" "$t"
done

echo "→ wiring hooks into settings.json (append-only, deduped by command)"
[ -f "$SETT" ] || echo '{}' > "$SETT"
cp "$SETT" "$SETT.bak"
tmp="$(mktemp)"
jq -s '
  .[0] as $live | .[1] as $snip
  | $live
  | .hooks = (reduce ($snip.hooks | keys[]) as $k (($live.hooks // {});
      ($snip.hooks[$k]) as $groups
      | (.[$k] // []) as $existing
      | ([$existing[].hooks[]?.command // ""]) as $cmds
      | ($groups | map(
          ((.hooks[0].command) as $cmd
           | (try ($cmd | capture("(?<f>[A-Za-z0-9_.-]+\\.(sh|md))").f) catch $cmd)) as $sig
          | select([ $cmds[] | select(contains($sig)) ] | length == 0)
        )) as $new
      | .[$k] = ($existing + $new)
    ))
' "$SETT" "$REPO/settings.snippet.json" > "$tmp" && mv "$tmp" "$SETT"
echo "  merged (backup: $SETT.bak)"

# Auto-wire the guardrail when the memory dir is itself a git repo (the README's
# recommended setup), and hide index churn from its diffs.
if [ -d "$CLAUDE/memory/.git" ]; then
  git -C "$CLAUDE/memory" config core.hooksPath "$REPO/guardrail"
  git -C "$CLAUDE/memory" update-index --skip-worktree MEMORY.md 2>/dev/null || true
  echo "→ guardrail wired into the memory repo at ~/.claude/memory"
fi

# The commit guardrail can also be used by any other consuming repo via
#   git -C <repo> config core.hooksPath <this-kit>/guardrail
# Seed the private denylist next to it (gitignored) if absent.
[ -f "$REPO/guardrail/denylist.local" ] || cp "$REPO/guardrail/denylist.local.example" "$REPO/guardrail/denylist.local"
echo "→ commit guardrail available at: $REPO/guardrail"
echo "    add private terms to $REPO/guardrail/denylist.local (or set \$CLAUDE_CONFIG_DENYLIST)"

echo "✓ done — start a new Claude Code session to load memory, hooks, and skills."
