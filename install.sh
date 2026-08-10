#!/usr/bin/env bash
# claude-memory-kit installer.
#   git clone <repo> ~/claude-memory-kit && ~/claude-memory-kit/install.sh
# Deploys the kit as ONE tree at ~/.claude/memory-kit (scripts + their core lib +
# hooks + tests move together, so no partial staleness), gated on the test suite —
# a tree the tests reject is never deployed. Skills and seed memories still go to
# the locations Claude Code discovers them in. Idempotent: re-run anytime.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE="$HOME/.claude"
DEST="$CLAUDE/memory-kit"
SETT="$CLAUDE/settings.json"
mkdir -p "$CLAUDE/skills" "$CLAUDE/memory"

echo "→ checking prerequisites (see docs/DEPENDENCIES.md)"
command -v jq >/dev/null 2>&1 || { echo "  ✗ jq required — install it and re-run"; exit 1; }
# no gh check: nothing in the kit calls it
command -v git >/dev/null 2>&1 && echo "  ✓ git" \
  || echo "  ! git missing — the guardrail and memory sync stay idle until it is installed"
if command -v claude >/dev/null 2>&1 \
   || ls "$HOME"/.vscode-server/extensions/anthropic.claude-code-*/resources/native-binary/claude >/dev/null 2>&1 \
   || ls "$HOME"/.vscode/extensions/anthropic.claude-code-*/resources/native-binary/claude >/dev/null 2>&1; then
  echo "  ✓ claude CLI"
else
  echo "  ! claude CLI not found on PATH or in a VS Code extension — the miner no-ops until it is"
fi

# Refuse to deploy something the tests reject. run.sh's own install fixtures call
# this installer with the guard variable set, so gating cannot recurse.
if [ -z "${MEMORY_KIT_INSTALL_GATED:-}" ] && [ -r "$REPO/tests/run.sh" ]; then
  echo "→ gating on the test suite"
  if MEMORY_KIT_INSTALL_GATED=1 bash "$REPO/tests/run.sh" >/dev/null 2>&1 </dev/null; then
    echo "  ✓ tests pass"
  else
    echo "  ✗ tests fail — refusing to deploy an untested tree. Run: bash $REPO/tests/run.sh"
    exit 1
  fi
fi

echo "→ deploying the kit tree to ~/.claude/memory-kit"
mkdir -p "$DEST"
# content dirs are stateless: replace them wholesale so renames/removals propagate
for d in core scripts hooks tests seed-memories skills; do
  rm -rf "$DEST/$d"
  cp -R "$REPO/$d" "$DEST/$d"
done
# guardrail is overlaid, never wiped: denylist.local (private terms) lives in it
mkdir -p "$DEST/guardrail"
cp "$REPO"/guardrail/pre-commit "$REPO"/guardrail/denylist.local.example "$DEST/guardrail/"
# migrate private terms from a pre-tree checkout wiring, then seed if still absent
[ -f "$DEST/guardrail/denylist.local" ] || { [ -f "$REPO/guardrail/denylist.local" ] && cp "$REPO/guardrail/denylist.local" "$DEST/guardrail/"; } || true
[ -f "$DEST/guardrail/denylist.local" ] || cp "$DEST/guardrail/denylist.local.example" "$DEST/guardrail/denylist.local"
# ship what re-verification needs (smoke reinstalls from the deployed tree)
install -m 0755 "$REPO/install.sh" "$DEST/install.sh"
install -m 0644 "$REPO/settings.snippet.json" "$DEST/settings.snippet.json"
chmod -R u+rwX "$DEST"

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

# Migrate hooks from the pre-tree layout: re-point OUR script commands (matched by
# basename, so other tools' scripts in ~/.claude/scripts are never touched) from
# ~/.claude/scripts and the old checkout-hooks path onto the deployed tree.
names=$(ls "$REPO"/scripts | paste -sd'|' - | sed 's/\./\\./g')
tmp="$(mktemp)"
# NOTE: jq gsub replacements can only reference NAMED captures — an unnamed group
# interpolates as the string "null" and corrupts the command
jq --arg re "(\\\$HOME|$HOME)/\\.claude/scripts/(?<n>$names)" \
   --arg hookre "(\\\$HOME|$HOME)/claude-memory-kit/hooks/" '
  .hooks = ((.hooks // {}) | map_values(map(
    .hooks |= map(.command |= (gsub($re; "$HOME/.claude/memory-kit/scripts/\(.n)")
                               | gsub($hookre; "$HOME/.claude/memory-kit/hooks/")))
  )))
' "$SETT" > "$tmp" && mv "$tmp" "$SETT"

tmp="$(mktemp)"
jq -s '
  # dedup is PER HOOK (by script filename), not per group: a group keyed on its first
  # hook silently drops any new hook later added to that group, so upgrades never land
  .[0] as $live | .[1] as $snip
  | $live
  | .hooks = (reduce ($snip.hooks | keys[]) as $k (($live.hooks // {});
      ($snip.hooks[$k]) as $groups
      | (.[$k] // []) as $existing
      | ([$existing[].hooks[]?.command // ""]) as $cmds
      | ($groups
         | map(.hooks |= map(
             ((.command) as $cmd
              | (try ($cmd | capture("(?<f>[A-Za-z0-9_.-]+\\.(sh|md))").f) catch $cmd)) as $sig
             | select([ $cmds[] | select(contains($sig)) ] | length == 0)
           ))
         | map(select((.hooks | length) > 0))
        ) as $new
      | .[$k] = ($existing + $new)
    ))
' "$SETT" "$REPO/settings.snippet.json" > "$tmp" && mv "$tmp" "$SETT"
echo "  merged (backup: $SETT.bak)"

# Auto-wire the guardrail when the memory dir is itself a git repo (the README's
# recommended setup), and hide index churn from its diffs. Points at the DEPLOYED
# guardrail — a stable, tested path that survives the checkout moving.
if [ -d "$CLAUDE/memory/.git" ]; then
  git -C "$CLAUDE/memory" config core.hooksPath "$DEST/guardrail"
  git -C "$CLAUDE/memory" update-index --skip-worktree MEMORY.md 2>/dev/null || true
  echo "→ guardrail wired into the memory repo at ~/.claude/memory"
fi

# The commit guardrail can also be used by any other consuming repo via
#   git -C <repo> config core.hooksPath ~/.claude/memory-kit/guardrail
echo "→ commit guardrail available at: $DEST/guardrail"
echo "    add private terms to $DEST/guardrail/denylist.local (or set \$CLAUDE_CONFIG_DENYLIST)"

# Legacy cleanup: the pre-tree layout scattered our scripts into ~/.claude/scripts;
# they are now stale copies. Remove exactly ours, never anything else living there.
for f in "$REPO"/scripts/*; do rm -f "$CLAUDE/scripts/$(basename "$f")"; done
rmdir "$CLAUDE/scripts" 2>/dev/null || true

echo "✓ done — start a new Claude Code session to load memory, hooks, and skills."
