#!/usr/bin/env bash
# Integration checks that need the real `claude` CLI, so they cannot run on a CI runner.
# tests/run.sh covers everything reachable with filesystem and git alone; this file covers the
# rest, and skips itself with exit 0 when the binary is absent so it is safe to wire into CI.
#
# What it verifies is Claude Code's behaviour, not this kit's: the entries it corresponds to are
# O13-O19 in docs/INTERNALS.md. Run it when the CLI updates, to catch a platform change under
# the assumptions this kit is built on.
#
#   bash tests/integration-plugin.sh
#
# Every call runs under `env -i HOME=<sandbox>`, so a real ~/.claude is never a participant.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
M=memory-kit

CLI=$(command -v claude 2>/dev/null)
if [ -z "$CLI" ]; then
    for c in "$HOME"/.vscode/extensions/anthropic.claude-code-*/resources/native-binary/claude \
             "$HOME"/.vscode-server/extensions/anthropic.claude-code-*/resources/native-binary/claude; do
        [ -x "$c" ] && CLI="$c" && break
    done
fi
if [ -z "$CLI" ]; then
    echo "integration-plugin: no claude CLI found — skipping (this is expected on CI)"
    exit 0
fi
command -v jq >/dev/null 2>&1 || { echo "integration-plugin: jq missing — skipping"; exit 0; }

P=0; F=0
ok(){ P=$((P+1)); printf '  ok   %s\n' "$1"; }
no(){ F=$((F+1)); printf '  FAIL %s — %s\n' "$1" "${2:-}"; }
cli(){ local h=$1; shift; env -i HOME="$h" PATH="$PATH" TERM=dumb "$CLI" "$@" 2>&1; }
caches(){ ls -d "$1/.claude/plugins/cache/$M/$M"/*/ 2>/dev/null | wc -l | tr -d ' '; }

echo "claude CLI: $CLI"
echo "marketplace and plugin are a lookup, not a chain (O18):"
h=$(mktemp -d); mkdir -p "$h/.claude"
cli "$h" plugin marketplace add "$ROOT" >/dev/null
n=$(jq -r '(.enabledPlugins//{})|keys|length' "$h/.claude/settings.json" 2>/dev/null)
[ "${n:-0}" = 0 ] && [ "$(caches "$h")" = 0 ] \
    && ok "marketplace add installs nothing" || no "marketplace add installed something" "plugins=$n"
rm -rf "$h"
h=$(mktemp -d); mkdir -p "$h/.claude"
printf '%s' "$(cli "$h" plugin install "$M@$M")" | grep -q 'not found' \
    && ok "install with no marketplace fails" || no "install without a marketplace succeeded"
printf '%s' "$(cli "$h" plugin install "$ROOT")" | grep -q 'not found in any configured marketplace' \
    && ok "install will not take a path as a source" || no "install accepted a path"
rm -rf "$h"

echo "a path source is referenced in place, a remote source is cloned (O13):"
h=$(mktemp -d); mkdir -p "$h/.claude"
cli "$h" plugin marketplace add "$ROOT" >/dev/null
[ -d "$h/.claude/plugins/marketplaces/$M" ] \
    && no "a path source was cloned" "expected no clone" || ok "a path source creates no clone"
rm -rf "$h"

echo "idempotency (O14, O17):"
h=$(mktemp -d); mkdir -p "$h/.claude"
cli "$h" plugin marketplace add "$ROOT" >/dev/null
cli "$h" plugin install "$M@$M" >/dev/null
WANT=$(jq -r .version "$ROOT/.claude-plugin/plugin.json")
[ -d "$h/.claude/plugins/cache/$M/$M/$WANT" ] \
    && ok "the cache is keyed by the version in plugin.json ($WANT)" \
    || no "cache not keyed by version" "$(ls "$h/.claude/plugins/cache/$M/$M" 2>/dev/null | tr '\n' ' ')"
printf '%s' "$(cli "$h" plugin marketplace add "$ROOT")" | grep -q 'already on disk' \
    && ok "marketplace add twice is a no-op" || no "marketplace add not idempotent"
printf '%s' "$(cli "$h" plugin update "$M@$M")" | grep -q 'already at the latest' \
    && ok "plugin update when current is a no-op" || no "plugin update not idempotent"

echo "nothing removes the cache, and order decides whether you can (O19):"
[ "$(caches "$h")" = 1 ] || no "no cache to test with"
cli "$h" plugin uninstall "$M@$M" >/dev/null
[ "$(caches "$h")" = 1 ] && ok "plugin uninstall leaves the cache" || no "uninstall removed the cache"
cli "$h" plugin marketplace remove "$M" >/dev/null
[ "$(caches "$h")" = 1 ] && ok "marketplace remove leaves the cache" || no "marketplace remove removed the cache"
printf '%s' "$(cli "$h" plugin prune)" | grep -q 'Nothing to prune' \
    && ok "prune does not collect orphaned caches" || no "prune behaviour changed"
rm -rf "$h"
h=$(mktemp -d); mkdir -p "$h/.claude"
cli "$h" plugin marketplace add "$ROOT" >/dev/null
cli "$h" plugin install "$M@$M" >/dev/null
cli "$h" plugin marketplace remove "$M" >/dev/null
printf '%s' "$(cli "$h" plugin uninstall "$M@$M")" | grep -q 'not found' \
    && ok "marketplace removed first: uninstall can no longer resolve the plugin" \
    || no "the wrong-order trap did not fire"
rm -rf "$h"

echo "the manifests this kit ships are accepted by the CLI:"
printf '%s' "$(env -i HOME="$HOME" PATH="$PATH" TERM=dumb "$CLI" plugin validate "$ROOT" 2>&1)" \
    | grep -q 'Validation passed' && ok "plugin validate passes" || no "plugin validate failed"

printf '\n%d passed, %d failed\n' "$P" "$F"
[ "$F" -eq 0 ]
