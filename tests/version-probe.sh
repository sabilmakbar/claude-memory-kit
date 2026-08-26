#!/usr/bin/env bash
# tests/version-probe.sh — check one published Claude Code build against the facts this
# kit's wiring rests on, without starting a session.
#
#   tests/version-probe.sh <version>
#
# Exit 0 with one row on stdout when it reached a verdict. Exit 2 when the environment
# is unusable, exit 3 when this build could not be reached, and no row in either case.
#
# Installs that version into a temporary npm prefix, reads the shipped binary, prints one
# tab-separated row for tests/versions-checked.tsv, and removes the install. Needs npm,
# jq, find and grep. No credentials, no tokens, no writes to ~/.claude: every check reads
# the binary rather than running a session.
#
# What it deliberately cannot check. Most entries in docs/INTERNALS.md need a real session
# to observe: O1 and O2 count transcripts, O5 needs a headless run, O8 to O11 and O13 all
# start one. Those stay manual. What is left is small and still worth automating, because
# it is the part that breaks silently:
#
#   O4   the build reports its own version, and reports the one that was asked for
#   O12  the build knows autoMemoryDirectory, which the whole store redirect rests on
#        (O12 read this from the extension's settings schema; the npm package ships one
#        compiled binary instead, so this reads the string out of the binary)
#   and every hook event name install.sh writes, since a renamed event leaves every hook
#   wired and never fired, with nothing to notice it
set -u

version="${1:?usage: version-probe.sh <version>}"
root="$(cd "$(dirname "$0")/.." && pwd)"
snippet="$root/settings.snippet.json"
today="$(date -u +%F)"

row() { printf '%s\t%s\t%s\t%s\n' "$version" "$today" "$1" "$2"; }

# A missing requirement means this probe never ran, so it must not write a row. A row is
# what keeps a version out of every later run, and "could not check" is not a result.
# Exit 2 says the environment is unusable and the whole run should stop; exit 3 below says
# this one build could not be reached and the run should carry on without recording it.
fatal() { echo "version-probe: $1" >&2; exit 2; }
[ -r "$snippet" ] || fatal "no settings.snippet.json at $snippet"
command -v npm >/dev/null 2>&1 || fatal "npm is not available"
command -v jq  >/dev/null 2>&1 || fatal "jq is not available"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

if ! npm i --prefix "$tmp" --no-audit --no-fund --silent \
        "@anthropic-ai/claude-code@$version" >/dev/null 2>&1; then
    # A yanked version or a flaky registry, and nothing here can tell which apart. No row
    # either way, so a later run tries again instead of trusting this one.
    echo "version-probe: $version: install failed" >&2
    exit 3
fi

# Found by shape rather than by name, because the name varies by platform and by era:
# 2.1.234 ships a compiled binary, while 2.0.43 shipped cli.js. The 1M floor skips the
# wrapper scripts sitting beside it.
bin="$(find "$tmp/node_modules/@anthropic-ai/claude-code" -maxdepth 2 -type f \
       -perm -u+x -size +1M 2>/dev/null | head -1)"
[ -n "$bin" ] || { echo "version-probe: $version: no executable in the package" >&2; exit 3; }

problems=""

# O4. Reporting a different version than the one installed would make every other row in
# the index untrustworthy, so this is checked first.
reported="$("$bin" --version 2>/dev/null | awk '{print $1; exit}')"
[ "$reported" = "$version" ] || problems="$problems reported=${reported:-none}"

# grep -a, because the target is a binary. Without it BSD grep reports nothing and every
# check below would pass by silence.
LC_ALL=C grep -aq -- 'autoMemoryDirectory' "$bin" || problems="$problems no-autoMemoryDirectory"

for ev in $(jq -r '.hooks | keys[]' "$snippet" 2>/dev/null); do
    LC_ALL=C grep -aq -- "$ev" "$bin" || problems="$problems no-event:$ev"
done

if [ -n "$problems" ]; then
    row fail "${problems# }"
else
    row ok -
fi
