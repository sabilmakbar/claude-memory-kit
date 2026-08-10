#!/usr/bin/env bash
# CLI wrapper: print the Claude Code version on this machine (resolution lives in
# core/lib.sh — running sessions, then installed extensions, then the binary).
# Prints nothing and exits 1 when none resolve. Read-only.

_LIB="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." 2>/dev/null && pwd)/core/lib.sh"
[ -r "$_LIB" ] || exit 1
. "$_LIB"
mk_claude_version
