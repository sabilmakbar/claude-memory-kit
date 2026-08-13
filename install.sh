#!/usr/bin/env bash
# claude-memory-kit installer. Idempotent: re-running is safe and is the upgrade path.
#   git clone <repo> ~/claude-memory-kit && ~/claude-memory-kit/install.sh
#
# Deploys the kit as ONE tree at ~/.claude/memory-kit (scripts + their core lib +
# hooks + guidance + tests move together, so no partial staleness), gated on the test
# suite: a tree the tests reject is never deployed. Skills go where Claude Code finds
# them. Memory files are yours, and neither half of this script writes them.
#
# Usage: ./install.sh --mode=managed|advisory [--dry-run]
#        ./install.sh [--uninstall] [--purge-cache] [--purge-tracker] [--purge-marker]
#
# --mode is required on a first install and remembered after that (DESIGN-install.md D11).
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
# Oldest Claude Code build the autoMemoryDirectory key was seen declared in
# (docs/INTERNALS.md O12). DESIGN-install.md D10 refuses below it rather than
# falling back, because DESIGN-memory.md D8 leaves nothing to fall back to.
FLOOR=2.1.205
# Sourced this early only for the accessors the version floor needs. lib.sh
# defines functions and does nothing else at source time, and the later source
# at the deploy step is unaffected by this one.
if [ -r "$REPO/core/lib.sh" ]; then . "$REPO/core/lib.sh"; fi

DRY=0; UNINSTALL=0; PURGE_CACHE=0; PURGE_TRACKER=0; PURGE_MARKER=0; MODE_ARG=""
for arg in "$@"; do
  case "$arg" in
    --dry-run)       DRY=1 ;;
    --uninstall)     UNINSTALL=1 ;;
    --purge-cache)   PURGE_CACHE=1 ;;
    --purge-tracker) PURGE_TRACKER=1 ;;
    --purge-marker)  PURGE_MARKER=1 ;;
    --mode=managed|--mode=advisory) MODE_ARG="${arg#--mode=}" ;;
    --mode=*)        echo "install.sh: --mode must be managed or advisory, not '${arg#--mode=}'" >&2; exit 2 ;;
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
# Remove every hook of ours named in $names, then prune upward so nothing is left
# standing empty: groups that emptied, then events, then the hooks key itself. Shapes
# we do not recognise pass through rather than being tidied away.
#
# Extracted because the uninstall and the legacy-name sweep must remove hooks exactly
# the same way. Two copies of this would be two chances for a rename to leave an entry
# behind, which is the failure the sweep exists to prevent.
def strip_hooks($names):
    if (.hooks | type) != "object" then .
    else .hooks = (.hooks
        | map_values(
            if type == "array" then
                map(if (.hooks | type) == "array"
                    then .hooks |= map(select((refs($names; true) | length) == 0))
                    else . end)
                | map(select((.hooks | type) != "array" or (.hooks | length) > 0))
            else . end)
        | with_entries(select((.value | type) != "array" or (.value | length) > 0)))
      | if (.hooks | type) == "object" and (.hooks | length) == 0 then del(.hooks) else . end
    end;
'

# Script basenames this kit wired in the past and no longer ships.
#
# managed_names is derived from settings.snippet.json, which after a rename lists only
# the NEW name. Without this list an upgrade would wire the new hook and walk past the
# old one, and an uninstall would remove the new hook and leave the old one behind,
# naming a script that no longer exists. That is the D3 failure mode in a new disguise:
# a spelling the merge cannot see.
#
# The list only grows, and a rename adds to it in the same commit that renames.
LEGACY_HOOK_NAMES="ensure-memory-symlink.sh"
LEGACY_JSON="$(printf '%s\n' $LEGACY_HOOK_NAMES | jq -R . | jq -sc . 2>/dev/null || echo '[]')"

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

# An upgrade has to unwire a name the kit no longer ships. The merge is append-only
# and dedups per hook, so on its own it would wire the new name and leave the old one
# standing beside it, pointing at a script the upgrade just deleted.
hooks_drop_legacy() {
  [ -f "$SETT" ] || return 0
  if [ "$LEGACY_JSON" = "[]" ]; then return 0; fi
  local tmp before after
  tmp="$(mktemp "$SETT.tmp.XXXXXX")"
  if ! jq --argjson legacy "$LEGACY_JSON" "$JQ_LIB"'strip_hooks($legacy)' "$SETT" > "$tmp" 2>/dev/null; then
    rm -f "$tmp"; return 0
  fi
  # The same guard the uninstall uses: every hook that is NOT ours has to survive.
  # Counting totals would prove nothing, since removal is meant to shrink the file.
  before=$(jq --argjson legacy "$LEGACY_JSON" "$JQ_LIB"'
      [.hooks[]?[]?.hooks[]? | select((refs($legacy; true) | length) == 0)] | length' \
      "$SETT" 2>/dev/null || echo -1)
  after=$(jq '[.hooks[]?[]?.hooks[]?] | length' "$tmp" 2>/dev/null || echo -2)
  if [ "$before" != "$after" ]; then rm -f "$tmp"; return 0; fi
  if cmp -s "$tmp" "$SETT"; then rm -f "$tmp"; return 0; fi
  mv "$tmp" "$SETT"
  echo "  ! unwired a hook this kit no longer ships: $LEGACY_HOOK_NAMES"
}

hooks_wire() {
  [ -f "$SNIPPET" ] || { echo "install.sh: no settings.snippet.json — skipping hook wiring" >&2; return 0; }
  if [ "$DRY" -eq 1 ]; then printf '  would: merge kit hooks into %s\n' "$SETT"; return 0; fi
  mkdir -p "$(dirname "$SETT")"
  if [ ! -f "$SETT" ]; then echo '{}' > "$SETT"; SETT_CREATED=1; fi
  hooks_migrate
  hooks_drop_legacy

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
  ' "$snap" "$SNIPPET" > "$tmp" 2>/dev/null || {
    rm -f "$tmp" "$snap"
    echo "install.sh: the settings.json merge could not run, so your file was left alone" >&2
    return 1
  }

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
  jq -s --argjson legacy "$LEGACY_JSON" "$JQ_LIB"'
    .[0] as $live | .[1] as $snip | (($snip | managed_names) + $legacy | unique) as $managed
    | $live
    | strip_hooks($managed)
  ' "$snap" "$SNIPPET" > "$tmp"

  # Removal is meant to shrink the file, so counting totals proves nothing. What must
  # hold is that every hook that was NOT ours survived. Anything else means we were
  # about to delete someone else's configuration.
  keep_before=$(jq -s --argjson legacy "$LEGACY_JSON" "$JQ_LIB"'
      .[0] as $live | .[1] as $snip | (($snip | managed_names) + $legacy | unique) as $managed
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

# --- the memory store ---------------------------------------------------------
#
# DESIGN-memory.md D8: the kit names the store with autoMemoryDirectory rather than
# computing where Claude Code keeps one and linking that onto a central directory.
# Everything here decides WHICH path the key names. Writing it is one jq call.

MARKER_NAME=".memory-kit-marker.json"
STORE_RECORD_DIR="$HOME/.local/share/claude-memory-kit"

# A store is a directory that already holds memory files.
#
# A symlinked project directory is skipped on purpose. The kit made those and they
# all point at one central directory, so counting them would report a single store
# many times over and turn every existing install into the many-stores case.
stores_find() {
  local d
  if ls "$CLAUDE"/memory/*.md >/dev/null 2>&1; then printf '%s\n' "$CLAUDE/memory"; fi
  for d in "$CLAUDE"/projects/*/memory; do
    [ -d "$d" ] || continue
    [ -L "$d" ] && continue
    ls "$d"/*.md >/dev/null 2>&1 || continue
    printf '%s\n' "$d"
  done
}

# The mode says who makes the change: managed means the kit does it and says what it
# will do first, advisory means the user does it (DESIGN-memory.md D8).
#
# It is never guessed. An earlier version let the store count decide, treating several
# stores as advisory, and guessing is wrong here: the mode governs whether the kit may
# rewrite someone's memory, and a machine that quietly picked for you is the one you
# cannot trust with that (D11). Detection still runs and still prints; it advises.
#
# Precedence is the flag, then the environment, then the value recorded by an earlier
# install. Empty means unresolved, which preflight turns into a refusal.
MODE=""
mode_recorded() { printf '%s' "${MEMORY_KIT_MODE:-$(mk_conf MEMORY_KIT_MODE "")}"; }
mode_resolve() {
  local m
  # Not written as ${MODE_ARG:-...}: that idiom means "read from the environment" to the
  # knob inventory test, and this one is set by this script's own argument parser.
  m="$MODE_ARG"
  [ -n "$m" ] || m="$(mode_recorded)"
  case "$(printf '%s' "$m" | tr 'A-Z' 'a-z')" in
    managed)  printf 'managed' ;;
    advisory) printf 'advisory' ;;
    *)        printf '' ;;
  esac
}

# Record the mode so a later run needs no flag. README states in two places that
# re-running the installer is the upgrade path, so a flag mandatory on every run would
# mean every upgrade restates it, and a value differing from last time would change
# behaviour during what looked routine (D11).
conf_set() { # <key> <value>
  local cf="$DEST/config" tmp
  [ -f "$cf" ] || return 0
  tmp="$(mktemp "$cf.tmp.XXXXXX")"
  grep -v "^[[:space:]]*$1=" "$cf" > "$tmp" 2>/dev/null || true
  printf '%s=%s\n' "$1" "$2" >> "$tmp"
  mv "$tmp" "$cf"
}

# The path the setting should name, or nothing when the kit must not choose one.
#
# Takes the store list rather than calling stores_find again: piping a multi-line
# producer into `head -1` makes the producer write into a closed pipe, which prints
# a broken-pipe error from a run that actually succeeded.
store_choose() { # <mode> <store-list>
  local count
  count=$(printf '%s' "$2" | grep -c . || true)
  if [ "$count" -eq 0 ]; then printf '%s' "$CLAUDE/memory"; return 0; fi
  if [ "$count" -eq 1 ]; then printf '%s' "$2"; return 0; fi
  if [ "$1" = managed ]; then printf '%s' "$CLAUDE/memory"; fi
}

# DESIGN-memory.md D9. A marker goes only into a store the kit acts on. Finding a
# store is not acting on it, so a store the kit merely read is recorded elsewhere:
# writing into it would mean advisory mode changes something, which is the one thing
# advisory mode promises not to do.
store_mark() { # <store-path> <reason: created|adopted>
  local marker cc
  [ -d "$1" ] || return 0
  marker="$1/$MARKER_NAME"
  if [ "$DRY" -eq 1 ]; then printf '  would: write %s\n' "$marker"; return 0; fi
  # Not written as ${CC_VERSION:-unknown}: that idiom marks a value read from the
  # environment, and the knob inventory test reads it that way. This one is set by
  # this script in preflight and is empty only when the version would not resolve.
  cc="$CC_VERSION"; [ -n "$cc" ] || cc=unknown
  jq -n --arg p "$1" --arg r "$2" --arg cc "$cc" \
        --arg t "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{state:"active", path:$p, reason:$r, claude_code_version:$cc, written:$t}' \
    > "$marker" 2>/dev/null || return 0
  # Announced rather than silent, on the same reasoning as the frontmatter heal in
  # D7: a file appearing in someone's repo that they did not create is not something
  # to do quietly.
  echo "  ✓ $MARKER_NAME written in $1 (state: active, $2)"
  store_exclude "$1"
}

# A store under git gets the marker excluded locally, never through .gitignore. The
# marker records what happened on THIS machine and the store may sync to others, so
# committing it would claim a history that is not true elsewhere. A local exclude
# changes no tracked file, which is what keeps D7 intact.
store_exclude() { # <store-path>
  local top ex
  command -v git >/dev/null 2>&1 || return 0
  top=$(git -C "$1" rev-parse --show-toplevel 2>/dev/null) || return 0
  [ -n "$top" ] || return 0
  ex="$top/.git/info/exclude"
  mkdir -p "$(dirname "$ex")" 2>/dev/null || return 0
  if grep -qxF "$MARKER_NAME" "$ex" 2>/dev/null; then return 0; fi
  printf '%s\n' "$MARKER_NAME" >> "$ex" 2>/dev/null \
    && echo "    excluded locally in .git/info/exclude, so it is not committed"
  return 0
}

# Stores the kit found and did not act on. Kept outside every store, and outside the
# deployed tree, so it survives --uninstall: a record that dies with the kit is
# useless at the exact moment it is needed.
store_record() { # <newline-separated store list>
  local n
  n=$(printf '%s' "$1" | grep -c . || true)
  [ "$n" -gt 0 ] || return 0
  if [ "$DRY" -eq 1 ]; then printf '  would: record %s store(s) in %s\n' "$n" "$STORE_RECORD_DIR"; return 0; fi
  mkdir -p "$STORE_RECORD_DIR" 2>/dev/null || return 0
  printf '%s\n' "$1" | jq -R . | jq -s --arg t "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{seen:$t, stores:.}' > "$STORE_RECORD_DIR/stores.json" 2>/dev/null || return 0
  echo "  ✓ $n store(s) recorded in $STORE_RECORD_DIR, and nothing written inside them"
}

# DESIGN-install.md D10 and DESIGN-memory.md D9. Uninstall removes the setting only
# when the kit wrote it, and the marker beside the store is how it knows: a value with
# no marker was set by someone else, and D5 leaves those alone.
#
# The marker itself is marked reverted, not deleted. A record of what the kit did is
# what makes the change reversible after the kit is gone, so deleting it on the way
# out destroys the only copy at the moment it becomes useful.
store_revert() {
  local cur marker top ex tmp
  [ -f "$SETT" ] || return 0
  cur=$(jq -r '.autoMemoryDirectory // empty' "$SETT" 2>/dev/null || true)
  [ -n "$cur" ] || return 0
  marker="$cur/$MARKER_NAME"
  if [ ! -f "$marker" ]; then
    echo "  kept autoMemoryDirectory=$cur: no $MARKER_NAME beside it, so this kit did not write it"
    return 0
  fi
  if [ "$DRY" -eq 1 ]; then printf '  would: remove autoMemoryDirectory and mark %s reverted\n' "$cur"; return 0; fi

  tmp="$(mktemp "$SETT.tmp.XXXXXX")"
  if jq 'del(.autoMemoryDirectory)' "$SETT" > "$tmp" 2>/dev/null; then
    mv "$tmp" "$SETT"; echo "  removed autoMemoryDirectory from $SETT"
  else
    rm -f "$tmp"
  fi

  if [ "$PURGE_MARKER" -eq 1 ]; then
    rm -f "$marker" && echo "  ! --purge-marker: deleted $MARKER_NAME from $cur"
    rm -rf "$STORE_RECORD_DIR" && echo "  ! --purge-marker: deleted $STORE_RECORD_DIR"
  else
    tmp="$(mktemp "$marker.tmp.XXXXXX")"
    if jq --arg t "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
         '.state = "reverted" | .reverted = $t' "$marker" > "$tmp" 2>/dev/null; then
      mv "$tmp" "$marker"
      echo "  $MARKER_NAME in $cur marked reverted, and kept as the record of what happened"
      echo "    --purge-marker removes it and the record of stores the kit only found"
    else
      rm -f "$tmp"
    fi
  fi

  # The local exclude goes either way: it was the kit's line, and it names a file that
  # is now either gone or no longer the kit's business.
  command -v git >/dev/null 2>&1 || return 0
  top=$(git -C "$cur" rev-parse --show-toplevel 2>/dev/null) || return 0
  [ -n "$top" ] || return 0
  ex="$top/.git/info/exclude"
  [ -f "$ex" ] || return 0
  if grep -qxF "$MARKER_NAME" "$ex" 2>/dev/null; then
    grep -vxF "$MARKER_NAME" "$ex" > "$ex.tmp" 2>/dev/null || true
    mv "$ex.tmp" "$ex" && echo "  removed $MARKER_NAME from $ex"
  fi
  return 0
}

store_setup() {
  local mode chosen existing all count tmp
  existing=$(jq -r '.autoMemoryDirectory // empty' "$SETT" 2>/dev/null || true)
  all=$(stores_find)
  count=$(printf '%s' "$all" | grep -c . || true)
  mode="$MODE"
  echo "→ naming the memory store (mode: $mode)"

  # Advisory writes nothing about the store: no setting and no marker. The kit reports
  # and the user makes the change, which is the whole of D8. It still records what it
  # found, outside every store, because that record is the kit's own bookkeeping rather
  # than a change to anyone's memory (D9).
  if [ "$mode" = advisory ]; then
    if [ -n "$existing" ]; then
      echo "  autoMemoryDirectory is $existing"
    elif [ "$count" -eq 0 ]; then
      echo "  no memory store found, and no setting written"
      echo "    managed would name $CLAUDE/memory here"
    else
      echo "  $count memory store(s) found:"
      printf '%s\n' "$all" | sed 's/^/      /'
      store_record "$all"
      if [ "$count" -eq 1 ]; then
        echo "    managed would point autoMemoryDirectory at that store, moving nothing"
      else
        echo "    managed would name $CLAUDE/memory and merge none of them"
      fi
    fi
    echo "  nothing written. To make the change yourself, set autoMemoryDirectory in $SETT"
    echo "    or re-run with --mode=managed to have the kit do it."
    return 0
  fi

  # A value we did not write is not ours to replace. Overwriting it would relocate
  # someone's memory without saying so, which is the D4 rule applied to a value.
  if [ -n "$existing" ]; then
    echo "  ✓ autoMemoryDirectory is already $existing — left alone"
    return 0
  fi

  if [ "$count" -gt 1 ]; then
    echo "  ! $count memory stores found:"
    printf '%s\n' "$all" | sed 's/^/      /'
    store_record "$all"
    echo "    managed: starting a central store at $CLAUDE/memory. None of the above is changed."
  fi

  chosen=$(store_choose "$mode" "$all")
  [ -n "$chosen" ] || return 0
  if [ "$DRY" -eq 1 ]; then printf '  would: set autoMemoryDirectory=%s in %s\n' "$chosen" "$SETT"; return 0; fi

  mkdir -p "$(dirname "$SETT")"
  if [ ! -f "$SETT" ]; then echo '{}' > "$SETT"; SETT_CREATED=1; fi
  if [ "$SETT_TOUCHED" -eq 0 ]; then
    if [ "$SETT_CREATED" -eq 0 ]; then cp "$SETT" "$SETT_BAK"; fi
    SETT_TOUCHED=1
  fi
  tmp="$(mktemp "$SETT.tmp.XXXXXX")"
  if jq --arg d "$chosen" '.autoMemoryDirectory = $d' "$SETT" > "$tmp" 2>/dev/null; then
    mv "$tmp" "$SETT"
    echo "  ✓ autoMemoryDirectory = $chosen"
    echo "    Every project now uses this one store. Claude Code reads the path from that"
    echo "    setting, so nothing has to guess where your memory lives and no symlink is"
    echo "    involved. Deleting the key puts every project back on its own store."
    if [ "$count" -eq 1 ]; then store_mark "$chosen" adopted; else store_mark "$chosen" created; fi
  else
    rm -f "$tmp"
    echo "  ✗ could not write autoMemoryDirectory into $SETT" >&2
    return 1
  fi
}

# --- uninstall ----------------------------------------------------------------
if [ "$UNINSTALL" -eq 1 ]; then
  echo "uninstalling"
  # Unwire BEFORE the tree goes: the snippet naming our hooks may be the deployed copy.
  hooks_unwire
  store_revert

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
#
# The version floor is checked before anything at all is created, because a refusal
# has to leave the machine exactly as it found it. Everything below this point
# writes something.
#
# An unreadable version is not a refusal. mk_claude_version returns empty on a
# machine with no CLI and no extension, which the prerequisite check below already
# reports; refusing there would block an install that starts working the moment
# Claude Code is present.
version_lt() { # <a> <b> → rc 0 when a is older than b
  [ "$1" = "$2" ] && return 1
  [ "$(printf '%s\n%s\n' "$1" "$2" | { sort -V 2>/dev/null || sort; } | head -1)" = "$1" ]
}
echo "→ checking Claude Code version (floor $FLOOR)"
CC_VERSION="$(mk_claude_version 2>/dev/null || true)"
if [ -z "$CC_VERSION" ]; then
  echo "  ! version not readable — continuing, the floor is re-checked on the next install"
elif version_lt "$CC_VERSION" "$FLOOR"; then
  echo "  ✗ Claude Code $CC_VERSION is older than $FLOOR" >&2
  echo "    The kit points auto memory at one store with the autoMemoryDirectory setting," >&2
  echo "    and this build does not read that key. There is no fallback to install instead." >&2
  echo "    Upgrade Claude Code and re-run. Nothing has been installed or changed." >&2
  exit 1
else
  echo "  ✓ Claude Code $CC_VERSION"
fi

# The mode is required before anything is written, for the same reason as the floor
# above: a refusal has to leave the machine as it found it. D11 puts the hard stop on
# a first install only, since re-running is the upgrade path and a flag mandatory
# every time would let a routine upgrade change behaviour by omission.
MODE="$(mode_resolve)"
if [ -z "$MODE" ]; then
  echo "  ✗ no mode set, and the installer will not choose one for you" >&2
  echo >&2
  _mk_all="$(stores_find)"; _mk_n=$(printf '%s' "$_mk_all" | grep -c . || true)
  if [ "$_mk_n" -gt 0 ]; then
    echo "    $_mk_n memory store(s) are already on this machine:" >&2
    printf '%s\n' "$_mk_all" | sed 's/^/        /' >&2
    echo >&2
  fi
  echo "    --mode=managed   the kit makes the change, and says what it will do first" >&2
  echo "    --mode=advisory  the kit reports what it thinks should change, and you do it" >&2
  echo >&2
  echo "    The mode decides whether the kit may rewrite your memory, so it is not" >&2
  echo "    guessed. It is asked once: this run records it, and upgrades re-use it." >&2
  echo "    Nothing has been installed or changed." >&2
  exit 1
fi
if [ -n "$MODE_ARG" ] && [ -n "$(mode_recorded)" ] && [ "$MODE_ARG" != "$(mode_recorded)" ]; then
  echo "  ! mode changing from $(mode_recorded) to $MODE_ARG"
fi
if [ "$MODE" = managed ]; then
  echo "  ✓ mode: managed, so the kit makes the change and says what it will do first"
else
  echo "  ✓ mode: advisory, so the kit reports and you make the change yourself"
fi

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
# A file can parse and still be unusable: .hooks has to be an object keyed by event, and
# each event we wire an array of groups. Checking the shape here rather than discovering
# it mid-merge is what turns a raw jq parser error at the end of a half-finished run into
# a sentence.
#
# Scoped to the snippet's own event keys, NOT to every event in the file. A foreign event
# of the wrong type is not our business: the merge only reads the keys the snippet
# declares, so such an event survives an install and an uninstall untouched. Refusing over
# it would mean judging config we did not write, which is the one thing this installer is
# built never to do. Deriving the list from the snippet keeps that file the single source
# of truth, so wiring a new event cannot forget to widen this check.
#
# `hooks` itself is different, and is still refused whatever it holds: that is not someone
# else's key, it is the container the merge has to write into. Nothing is repaired
# automatically either, because a wrongly-typed `hooks` holds something this installer did
# not write and must not guess at. No snippet means no wiring at all (hooks_wire returns
# early), so there is nothing left to check for.
if [ -f "$SETT" ] && [ -f "$SNIPPET" ] && ! jq -e --slurpfile snip "$SNIPPET" '
      ($snip[0].hooks | keys) as $ours
      | (.hooks // {}) as $h
      | ($h | type) == "object"
        and ([ $ours[]
               | $h[.]
               | select(. != null)
               | select((type != "array") or (any(.[]; type != "object")))
             ] | length) == 0
    ' "$SETT" >/dev/null 2>&1; then
  echo "  ✗ $SETT parses, but its \"hooks\" is not a shape this installer can merge into" >&2
  echo "    expected: \"hooks\" an object, and each event we wire an array of groups" >&2
  echo "    it will not rewrite what it did not write. Fix that key and re-run;" >&2
  echo "    nothing has been installed or changed." >&2
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
# Recorded only when the file does not already say it, so a plain upgrade rewrites
# nothing and leaves no mtime churn in a file the user edits by hand.
if [ "$(mk_conf MEMORY_KIT_MODE "")" != "$MODE" ]; then conf_set MEMORY_KIT_MODE "$MODE"; fi
store_setup

echo "✓ done — start a new Claude Code session to load memory, hooks, and skills."
echo "  ./install.sh --uninstall removes the hooks, the tree and the skills, and keeps your memory."
