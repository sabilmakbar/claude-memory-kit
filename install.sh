#!/usr/bin/env bash
# claude-memory-kit installer. Idempotent: re-running is safe and is the upgrade path.
#   git clone <repo> ~/claude-memory-kit && ~/claude-memory-kit/install.sh
#
# Deploys the kit as ONE tree at ~/.claude/memory-kit (scripts + their core lib +
# hooks + guidance + tests move together, so no partial staleness), gated on the test
# suite: a tree the tests reject is never deployed. Skills go where Claude Code finds
# them. Memory files are yours, and neither half of this script writes them.
#
# Usage: ./install.sh [--dry-run] [--uninstall] [--purge-cache] [--purge-tracker]
#
# The settings.json contract matches claude-session-kit's, deliberately: two kits
# writing one shared file under two different contracts is worse than either choice
# alone. Both wire their own hooks, both remove them again, and both decide what
# counts as theirs the same way.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE="$HOME/.claude"
DEST="$CLAUDE/memory-kit"
SETT="$CLAUDE/settings.json"
# Kit-specific backup name: session-kit names its own copy for the same reason. A
# shared settings.json.bak means each kit's installer clobbers the other's backup.
SETT_BAK="$SETT.memory-kit.bak"
SNIPPET="$REPO/settings.snippet.json"
[ -f "$SNIPPET" ] || SNIPPET="$DEST/settings.snippet.json"
TRACKER="$HOME/.local/share/claude-feedback"

DRY=0; UNINSTALL=0; PURGE_CACHE=0; PURGE_TRACKER=0
for arg in "$@"; do
  case "$arg" in
    --dry-run)       DRY=1 ;;
    --uninstall)     UNINSTALL=1 ;;
    --purge-cache)   PURGE_CACHE=1 ;;
    --purge-tracker) PURGE_TRACKER=1 ;;
    *) echo "install.sh: unknown option $arg" >&2; exit 2 ;;
  esac
done
run() { [ "$DRY" -eq 1 ] && { printf '  would: %s\n' "$*"; return 0; }; "$@"; }

# --- settings.json ------------------------------------------------------------
#
# Ownership is the script basename tokenised out of the command AND the directory that
# basename sits in, never the exact command string. Exact matching duplicates a hook on
# every harmless difference in spelling (an absolute path where the snippet writes
# $HOME, a missing 2>/dev/null, other quoting). Basename alone is wrong in both
# directions, because tool names collide: this kit had to rename its own
# version-check.sh once because a sibling kit ships one too, and that rename was a
# workaround for exactly this. A hook is ours only when the basename is one we ship and
# its directory sits inside the deployed tree.
JQ_LIB='
def cmd_tokens:
    if type == "string"
    then [scan("[^\\s]+")] | map(gsub("[^A-Za-z0-9._/$~{}-]"; "")) | map(select(length > 0))
    else [] end;
def cmd_basenames: cmd_tokens | map(split("/") | last);
# refs($managed; true) = hooks of ours. refs($managed; false) = someone else using one
# of our filenames from elsewhere. Both a deployed tree and a checkout end in
# memory-kit/scripts or memory-kit/hooks.
def refs($managed; $mine):
    [ (.command | cmd_tokens)[] as $t
      | ($t | split("/") | last) as $b
      | ($t | split("/") | .[:-1] | join("/")) as $dir
      | select($managed | index($b))
      | select((($dir | endswith("memory-kit/scripts")) or ($dir | endswith("memory-kit/hooks"))) == $mine)
      | $b ];
# Managed = the .sh basenames THIS kit wires, derived from the snippet so the list
# lives in exactly one place. The .sh filter drops shell noise (the "null" of
# 2>/dev/null, "true", "||") that would otherwise match across unrelated hooks.
def managed_names: [.hooks[]?[]?.hooks[]?.command | cmd_basenames[] | select(endswith(".sh"))] | unique;
'

SETT_TOUCHED=0; SETT_CREATED=0
rollback_settings() {
  local rc=$?
  [ "$rc" -eq 0 ] && return 0
  # A file we created ourselves is undone by removing it, not by restoring an empty
  # one: on a machine that had no settings.json, leaving {} behind is not where it
  # started.
  if [ "$SETT_CREATED" -eq 1 ]; then
    rm -f "$SETT" 2>/dev/null \
      && echo "install.sh: run failed, so the settings.json it created was removed again" >&2
    return 0
  fi
  [ "$SETT_TOUCHED" -eq 1 ] || return 0
  [ -f "$SETT_BAK" ] || return 0
  cp "$SETT_BAK" "$SETT" 2>/dev/null \
    && echo "install.sh: run failed, so settings.json was rolled back to its previous contents" >&2
  return 0
}
trap rollback_settings EXIT

# Re-point hooks written by the pre-tree layout onto the deployed tree, so an upgrade
# does not leave two spellings of one hook behind. Matched by basename alone here on
# purpose: these paths sit outside the tree by definition, which is what the ownership
# test above is built to reject.
hooks_migrate() {
  [ -f "$SETT" ] || return 0
  local names tmp
  names=$(ls "$REPO"/scripts | paste -sd'|' - | sed 's/\./\\./g')
  tmp="$(mktemp "$SETT.tmp.XXXXXX")"
  # NOTE: jq gsub replacements can only reference NAMED captures — an unnamed group
  # interpolates as the string "null" and corrupts the command
  if jq --arg re "(\\\$HOME|$HOME)/\\.claude/scripts/(?<n>$names)" \
        --arg hookre "(\\\$HOME|$HOME)/claude-memory-kit/hooks/" '
       .hooks = ((.hooks // {}) | map_values(map(
         .hooks |= map(.command |= (gsub($re; "$HOME/.claude/memory-kit/scripts/\(.n)")
                                    | gsub($hookre; "$HOME/.claude/memory-kit/hooks/")))
       )))
     ' "$SETT" > "$tmp" 2>/dev/null; then mv "$tmp" "$SETT"; else rm -f "$tmp"; fi
}

hooks_wire() {
  [ -f "$SNIPPET" ] || { echo "install.sh: no settings.snippet.json — skipping hook wiring" >&2; return 0; }
  if [ "$DRY" -eq 1 ]; then printf '  would: merge kit hooks into %s\n' "$SETT"; return 0; fi
  mkdir -p "$(dirname "$SETT")"
  if [ ! -f "$SETT" ]; then echo '{}' > "$SETT"; SETT_CREATED=1; fi
  hooks_migrate

  # A hook using one of our filenames from outside the tree belongs to something else.
  # It is neither counted as already-wired nor removed later, and saying so is the
  # difference between sharing a file and springing a surprise.
  local clash
  clash=$(jq -rs "$JQ_LIB"'
    .[0] as $live | .[1] as $snip | ($snip | managed_names) as $managed
    | [$live.hooks[]?[]?.hooks[]? | select((refs($managed; false) | length) > 0) | .command]
    | unique | .[]' "$SETT" "$SNIPPET" 2>/dev/null || true)
  if [ -n "$clash" ]; then
    echo "  ! settings.json has hooks named like ours, owned by something else:" >&2
    printf '      %s\n' "$clash" >&2
    echo "    left untouched; this kit only writes or removes paths inside $DEST" >&2
  fi

  # Staged NEXT TO settings.json: a rename inside one directory is atomic, while moving
  # across filesystems is a copy that can be interrupted and truncate the file.
  local tmp snap before after
  tmp="$(mktemp "$SETT.tmp.XXXXXX")"; snap="$(mktemp "$SETT.snap.XXXXXX")"
  cp "$SETT" "$snap"
  # Dedup is PER HOOK, not per group: a group keyed on its first hook silently drops
  # any hook added to that group later, so upgrades would never land.
  jq -s "$JQ_LIB"'
    .[0] as $live | .[1] as $snip | ($snip | managed_names) as $managed
    | $live
    | .hooks = (reduce ($snip.hooks | keys[]) as $ev ((.hooks // {});
        (.[$ev] // []) as $existing
        | ([$existing[]?.hooks[]? | refs($managed; true)[]] | unique) as $have
        | ($snip.hooks[$ev]
           | map(.hooks |= map(select(
               ([refs($managed; true)[] | select(. as $b | $have | index($b))] | length) == 0)))
           | map(select((.hooks | length) > 0))) as $new
        | .[$ev] = ($existing + $new)))
  ' "$snap" "$SNIPPET" > "$tmp"

  # Wiring only ever adds, so a result that is invalid JSON, or that holds fewer hooks
  # than we started with, means the merge went wrong and the live file is better alone.
  before=$(jq '[.hooks[]?[]?.hooks[]?] | length' "$snap" 2>/dev/null || echo 0)
  after=$(jq '[.hooks[]?[]?.hooks[]?] | length' "$tmp" 2>/dev/null || echo -1)
  if ! jq -e . "$tmp" >/dev/null 2>&1 || [ "$after" -lt "$before" ]; then
    rm -f "$tmp" "$snap"
    echo "install.sh: the settings.json merge did not look right, so your file was left alone" >&2
    return 1
  fi
  # An identical result means there is nothing to do, so neither file is touched. That
  # is what keeps an older backup intact when the installer is re-run as the upgrade.
  if cmp -s "$tmp" "$SETT"; then
    rm -f "$tmp" "$snap"; echo "  hooks already wired; $SETT left untouched"; return 0
  fi
  if ! cmp -s "$snap" "$SETT"; then
    rm -f "$tmp" "$snap"
    echo "install.sh: $SETT changed while it was being read, so nothing was written" >&2
    echo "  another tool wrote it at the same moment. Re-run to merge against the new file." >&2
    return 1
  fi
  rm -f "$snap"
  [ "$SETT_CREATED" -eq 0 ] && cp "$SETT" "$SETT_BAK"
  SETT_TOUCHED=1
  mv "$tmp" "$SETT"
  if [ "$SETT_CREATED" -eq 1 ]
  then echo "  hooks wired into $SETT (created; there was no settings.json before)"
  else echo "  hooks wired into $SETT (previous contents: $SETT_BAK)"; fi
}

hooks_unwire() {
  [ -f "$SETT" ] || return 0
  [ -f "$SNIPPET" ] || { echo "install.sh: no settings.snippet.json — leaving hooks in place" >&2; return 0; }
  # Without jq the hooks cannot be removed safely, and the tree is about to go, so say
  # exactly what is left and how to finish by hand. They stay harmless meanwhile, since
  # each exits quietly when its script is missing, but silence would leave a config
  # nobody knows is stale.
  command -v jq >/dev/null 2>&1 || {
    echo "install.sh: jq not found, so the hooks cannot be removed from $SETT" >&2
    echo "  they will keep naming files this uninstall is about to delete. Nothing breaks," >&2
    echo "  since each hook exits quietly when its script is gone, but the config is stale." >&2
    echo "  To tidy up by hand, delete the entries naming these:" >&2
    ( cd "$REPO" && ls scripts/*.sh hooks/*.sh 2>/dev/null | xargs -n1 basename \
        | tr '\n' ' ' | sed 's/^/    /' ) >&2
    echo >&2
    return 0; }
  if [ "$DRY" -eq 1 ]; then printf '  would: remove kit hooks from %s\n' "$SETT"; return 0; fi
  local tmp snap keep_before keep_after
  tmp="$(mktemp "$SETT.tmp.XXXXXX")"; snap="$(mktemp "$SETT.snap.XXXXXX")"
  cp "$SETT" "$snap"
  # Prune upward so nothing is left standing empty: our hooks, then groups that
  # emptied, then events, then the hooks key itself. Shapes we do not recognise pass
  # through untouched rather than being tidied away.
  jq -s "$JQ_LIB"'
    .[0] as $live | .[1] as $snip | ($snip | managed_names) as $managed
    | $live
    | if (.hooks | type) != "object" then .
      else .hooks = (.hooks
          | map_values(
              if type == "array" then
                  map(if (.hooks | type) == "array"
                      then .hooks |= map(select((refs($managed; true) | length) == 0))
                      else . end)
                  | map(select((.hooks | type) != "array" or (.hooks | length) > 0))
              else . end)
          | with_entries(select((.value | type) != "array" or (.value | length) > 0)))
        | if (.hooks | type) == "object" and (.hooks | length) == 0 then del(.hooks) else . end
      end
  ' "$snap" "$SNIPPET" > "$tmp"

  # Removal is meant to shrink the file, so counting totals proves nothing. What must
  # hold is that every hook that was NOT ours survived. Anything else means we were
  # about to delete someone else's configuration.
  keep_before=$(jq -s "$JQ_LIB"'
      .[0] as $live | .[1] as $snip | ($snip | managed_names) as $managed
      | [$live.hooks[]?[]?.hooks[]? | select((refs($managed; true) | length) == 0)] | length' \
      "$snap" "$SNIPPET" 2>/dev/null || echo -1)
  keep_after=$(jq '[.hooks[]?[]?.hooks[]?] | length' "$tmp" 2>/dev/null || echo -2)
  if ! jq -e . "$tmp" >/dev/null 2>&1 || [ "$keep_after" != "$keep_before" ]; then
    rm -f "$tmp" "$snap"
    echo "install.sh: removing the hooks would have changed something else, so your file was left alone" >&2
    return 1
  fi
  if cmp -s "$tmp" "$SETT"; then
    rm -f "$tmp" "$snap"; echo "  no kit hooks were wired; $SETT left untouched"; return 0
  fi
  if ! cmp -s "$snap" "$SETT"; then
    rm -f "$tmp" "$snap"
    echo "install.sh: $SETT changed while it was being read, so nothing was written" >&2
    echo "  the hooks are still wired. Re-run --uninstall to try again." >&2
    return 1
  fi
  rm -f "$snap"
  cp "$SETT" "$SETT_BAK"
  SETT_TOUCHED=1
  mv "$tmp" "$SETT"
  echo "  hooks removed from $SETT (previous contents: $SETT_BAK)"
}

# --- uninstall ----------------------------------------------------------------
if [ "$UNINSTALL" -eq 1 ]; then
  echo "uninstalling"
  # Unwire BEFORE the tree goes: the snippet naming our hooks may be the deployed copy.
  hooks_unwire

  # The guardrail is wired by pointing the memory repo's core.hooksPath into the tree
  # this is about to delete. Leaving that behind is the worst failure available here:
  # git finds no hook file and runs nothing, so the commit guard stops silently while
  # the repo still looks configured, and that guard is what stands between private
  # terms and a public push. Only ever unset a path that points into OUR tree.
  if [ -d "$CLAUDE/memory/.git" ] && command -v git >/dev/null 2>&1; then
    hp=$(git -C "$CLAUDE/memory" config --get core.hooksPath 2>/dev/null || true)
    case "$hp" in
      "$DEST"|"$DEST"/*)
        run git -C "$CLAUDE/memory" config --unset core.hooksPath
        echo "  unset core.hooksPath in ~/.claude/memory (it pointed into the tree being removed)" ;;
      "") ;;
      *) echo "  ! core.hooksPath in ~/.claude/memory is $hp, which is not ours, so it stays" ;;
    esac
    # MEMORY.md was marked skip-worktree to keep index churn out of diffs. Undo it, or
    # the file stays invisible to git once the kit is gone.
    if git -C "$CLAUDE/memory" ls-files -v MEMORY.md 2>/dev/null | grep -q '^S'; then
      run git -C "$CLAUDE/memory" update-index --no-skip-worktree MEMORY.md
      echo "  MEMORY.md is visible to git again (skip-worktree cleared)"
    fi
  fi

  # Knob settings live inside the tree, so they go with it, the same way session-kit
  # treats its own. Print any non-default line first, so a hand-tuned setup is
  # recoverable from the terminal rather than simply gone.
  if [ -f "$DEST/config" ] && grep -qE '^[A-Za-z_]' "$DEST/config" 2>/dev/null; then
    echo "  your knob settings, for the record, since the config goes with the tree:"
    grep -E '^[A-Za-z_]' "$DEST/config" | sed 's/^/      /'
  fi

  for s in "$REPO"/skills/*/; do run rm -rf "$CLAUDE/skills/$(basename "$s")"; done
  run rm -rf "$DEST"
  echo "  removed $DEST and the kit's skills"

  # User data is never removed by default. The tracker holds the proposals you accepted
  # and rejected, and the miner reads the rejections so it never re-proposes them.
  if [ "$PURGE_TRACKER" -eq 1 ]; then
    echo "  ! --purge-tracker: deleting $TRACKER, including the record of what you rejected,"
    echo "    so a later reinstall can re-propose rules you already refused."
    run rm -rf "$TRACKER"
  elif [ "$PURGE_CACHE" -eq 1 ]; then
    echo "  ! --purge-cache: deleting the cached message digest and the run logs, keeping proposals.md"
    run rm -f "$TRACKER/digest-latest.txt" "$TRACKER/miner.log" "$TRACKER/miner.log.1"
  elif [ -d "$TRACKER" ]; then
    echo "  kept $TRACKER: the proposals you accepted and rejected, the miner's logs, and a"
    echo "    cached copy of the messages it last read. --purge-cache drops the cache and logs,"
    echo "    --purge-tracker removes all of it."
  fi
  echo "  kept every memory file in ~/.claude/memory and ~/.claude/memory-mounts"
  echo "✓ uninstalled"
  exit 0
fi

# --- preflight ----------------------------------------------------------------
run mkdir -p "$CLAUDE/skills" "$CLAUDE/memory"

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

# A settings.json that is already broken stops us here, rather than at the very end
# after a full install, with nothing but a parser error to show for it.
if [ -f "$SETT" ] && ! jq -e 'type == "object"' "$SETT" >/dev/null 2>&1; then
  echo "  ✗ $SETT is not a valid JSON object, so the hooks cannot be wired" >&2
  echo "    fix or move that file and re-run. Nothing has been installed or changed." >&2
  exit 1
fi

# Refuse to deploy something the tests reject. run.sh's own install fixtures call this
# installer with the guard variable set, so gating cannot recurse.
if [ "$DRY" -eq 0 ] && [ -z "${CLAUDE_MEMORY_KIT_INSTALL_GATED:-}" ] && [ -r "$REPO/tests/run.sh" ]; then
  echo "→ gating on the test suite"
  if CLAUDE_MEMORY_KIT_INSTALL_GATED=1 bash "$REPO/tests/run.sh" >/dev/null 2>&1 </dev/null; then
    echo "  ✓ tests pass"
  else
    echo "  ✗ tests fail — refusing to deploy an untested tree. Run: bash $REPO/tests/run.sh"
    exit 1
  fi
fi

echo "→ deploying the kit tree to ~/.claude/memory-kit"
run mkdir -p "$DEST"
# content dirs are stateless: replace them wholesale so renames/removals propagate
for d in core scripts hooks tests guidance skills; do
  run rm -rf "$DEST/$d"
  run cp -R "$REPO/$d" "$DEST/$d"
done
# guardrail is overlaid, never wiped: denylist.local (private terms) lives in it
run mkdir -p "$DEST/guardrail"
run cp "$REPO"/guardrail/pre-commit "$REPO"/guardrail/denylist.local.example "$DEST/guardrail/"
# migrate private terms from a pre-tree checkout wiring, then seed if still absent
[ -f "$DEST/guardrail/denylist.local" ] || { [ -f "$REPO/guardrail/denylist.local" ] && run cp "$REPO/guardrail/denylist.local" "$DEST/guardrail/"; } || true
[ -f "$DEST/guardrail/denylist.local" ] || run cp "$DEST/guardrail/denylist.local.example" "$DEST/guardrail/denylist.local"
# ship what re-verification and self-uninstall need: both read from the deployed tree
run install -m 0755 "$REPO/install.sh" "$DEST/install.sh"
run install -m 0644 "$REPO/settings.snippet.json" "$DEST/settings.snippet.json"
# knobs: the example refreshes every install so new knobs show up; the live config is
# seeded once and never overwritten, the same deal denylist.local gets above. Both sit
# at the tree root, which the wipe above does not touch.
run install -m 0644 "$REPO/config.example" "$DEST/config.example"
[ -f "$DEST/config" ] || run install -m 0644 "$DEST/config.example" "$DEST/config"
# a renamed knob keeps working: old keys in the live config are rewritten in place,
# commented or not. The one case this cannot reach is an export in a shell profile,
# which the health hook reports instead of letting it be ignored in silence.
if [ "$DRY" -eq 0 ] && [ -r "$REPO/core/lib.sh" ]; then
  . "$REPO/core/lib.sh"
  mk_legacy_knobs | while read -r old new; do
    grep -qE "^[[:space:]]*#?[[:space:]]*$old=" "$DEST/config" 2>/dev/null || continue
    t="$(mktemp)"
    sed "s/^\([[:space:]]*#\{0,1\}[[:space:]]*\)$old=/\1$new=/" "$DEST/config" > "$t" \
      && mv "$t" "$DEST/config" && echo "  renamed knob $old to $new in your config"
  done
fi
run chmod -R u+rwX "$DEST"

echo "→ installing skills to ~/.claude/skills"
run cp -r "$REPO"/skills/. "$CLAUDE/skills/"

# The authoring conventions used to be seeded into ~/.claude/memory as two memory files.
# They are kit instructions rather than user data: they cost context in every session,
# could be edited into drift, and nothing verified that a write followed them. They now
# live in guidance/ and are enforced by hooks/memory-write-guard.sh. Retire an old copy
# only when it is byte-identical to what the kit shipped; anything edited is the user's.
# Two guards, because ~/.claude/memory is the USER'S repo and this installer does not own
# it. Only a file byte-identical to the copy the kit still ships is ever removed, so
# anything deleted here is reproducible from this tree. And a file git tracks is never
# removed at all: deleting tracked content would stage a deletion in someone else's
# history, which is a commit for them to make, not for an installer to make on their behalf.
for f in "$REPO"/guidance/retired-seeds/*.md; do
  b="$(basename "$f")"; t="$CLAUDE/memory/$b"
  [ -f "$t" ] || continue
  if ! cmp -s "$f" "$t"; then
    echo "  ! $b differs from the copy the kit shipped, so it is yours and stays"
    echo "    its rules are enforced at write time now; delete it whenever you like"
  elif command -v git >/dev/null 2>&1 && git -C "$CLAUDE/memory" ls-files --error-unmatch "$b" >/dev/null 2>&1; then
    echo "  ! $b is unchanged from the kit's copy but your repo tracks it, so it stays"
    echo "    removing it is a commit for you to make: git rm $b"
  else
    run rm -f "$t"
    echo "→ retired $b from ~/.claude/memory (its rules are now a write-time check)"
  fi
done

# Auto-wire the guardrail when the memory dir is itself a git repo (the README's
# recommended setup), and hide index churn from its diffs. Points at the DEPLOYED
# guardrail: a stable, tested path that survives the checkout moving. --uninstall
# unsets both of these again.
if [ -d "$CLAUDE/memory/.git" ]; then
  run git -C "$CLAUDE/memory" config core.hooksPath "$DEST/guardrail"
  [ "$DRY" -eq 1 ] || git -C "$CLAUDE/memory" update-index --skip-worktree MEMORY.md 2>/dev/null || true
  echo "→ guardrail wired into the memory repo at ~/.claude/memory"
fi

# The commit guardrail can also be used by any other consuming repo via
#   git -C <repo> config core.hooksPath ~/.claude/memory-kit/guardrail
echo "→ commit guardrail available at: $DEST/guardrail"
echo "    add private terms to $DEST/guardrail/denylist.local (or set \$CLAUDE_CONFIG_DENYLIST)"
echo "→ knobs (miner opt-out, notice timing, machine label) live in $DEST/config"

# Legacy cleanup: the pre-tree layout scattered our scripts into ~/.claude/scripts;
# they are now stale copies. Remove exactly ours, never anything else living there.
for f in "$REPO"/scripts/*; do run rm -f "$CLAUDE/scripts/$(basename "$f")"; done
[ "$DRY" -eq 1 ] || rmdir "$CLAUDE/scripts" 2>/dev/null || true

# settings.json goes LAST, after everything else has installed: a run that fails
# earlier never touches the file every other tool shares.
echo "→ wiring hooks into settings.json (append-only, deduped per hook)"
hooks_wire

echo "✓ done — start a new Claude Code session to load memory, hooks, and skills."
echo "  ./install.sh --uninstall removes the hooks, the tree and the skills, and keeps your memory."
