#!/usr/bin/env bash
# core/lib.sh — the kit's single accessor layer. Every path into Claude Code
# internals (transcript layout, session ids, binary/version discovery) and every
# behavior shared by more than one script lives here, so a harness change is a
# one-file fix and the scripts stay thin.
#
# Source it; do not execute it. Functions fail quiet — on missing data they
# return empty and non-zero rather than erroring — so callers degrade to
# "no data", never to a broken hook. bash 3.2 compatible (macOS default).

# ---- fixed locations -------------------------------------------------------

mk_memory_dir()   { printf '%s/.claude/memory' "$HOME"; }
mk_mounts_dir()   { printf '%s/.claude/memory-mounts' "$HOME"; }
mk_projects_dir() { printf '%s/.claude/projects' "$HOME"; }
mk_tracker_dir()  { printf '%s/.local/share/claude-feedback' "$HOME"; }

# ---- hook stdin ------------------------------------------------------------

# Session id from hook stdin JSON. Empty (rc 1) on a tty, unreadable stdin, or
# missing field — callers treat empty as "no session context" and fail open.
mk_session_id() {
    [ -t 0 ] && return 1
    jq -r '.session_id // empty' 2>/dev/null | tr -cd 'A-Za-z0-9_-'
}

# ---- portability shims -----------------------------------------------------

# mtime as epoch: GNU stat, then BSD stat, then 0.
mk_mtime() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || echo 0; }

# ---- once-per-session-per-day notice markers --------------------------------

# mk_notice_due <sid> <name> → rc 0 when the notice should fire (also sweeps
# stale markers); rc 1 when this session already noticed today. Empty sid → due
# (fail open, the pre-marker behavior).
mk_notice_due() {
    [ -n "${1:-}" ] || return 0
    _mk_markers="$HOME/.claude/.notice-markers"; mkdir -p "$_mk_markers"
    [ "$(cat "$_mk_markers/$1.$2" 2>/dev/null)" = "$(date +%F)" ] && return 1
    find "$_mk_markers" -type f -mtime +7 -delete 2>/dev/null
    return 0
}

# mk_notice_stamp <sid> <name> — record that the notice fired; call only when a
# notice is actually emitted, so silent runs never suppress future ones.
mk_notice_stamp() {
    [ -n "${1:-}" ] || return 0
    date +%F > "$HOME/.claude/.notice-markers/$1.$2"
}

# ---- dual-audience notice emission ------------------------------------------

# Emit the kit's standard SessionStart payload: systemMessage for the human
# (a toast not every UI shows) + additionalContext so the model relays it.
mk_emit_notice() {
    printf '{"systemMessage": "%s", "hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": "%s Mention this to the user at the start of your next reply."}}\n' "$1" "$1"
}

# ---- Claude Code discovery ---------------------------------------------------

# The claude CLI: PATH first, else the newest VS Code extension's bundled binary
# (both the Linux remote layout and the macOS local layout).
mk_claude_bin() {
    _mk_bin=$(command -v claude 2>/dev/null)
    if [ -z "$_mk_bin" ]; then
        _mk_bin=$(ls -t "$HOME"/.vscode-server/extensions/anthropic.claude-code-*/resources/native-binary/claude \
                        "$HOME"/.vscode/extensions/anthropic.claude-code-*/resources/native-binary/claude 2>/dev/null | head -1)
    fi
    [ -x "$_mk_bin" ] || return 1
    printf '%s' "$_mk_bin"
}

# The Claude Code version on this machine, best source first: running processes
# (~/.claude/sessions/*.json), newest installed extension (version in dir name),
# the binary itself. Empty + rc 1 when none resolve.
mk_claude_version() {
    _mk_best=""
    for _mk_f in "$HOME"/.claude/sessions/*.json; do
        [ -r "$_mk_f" ] || continue
        _mk_v=$(jq -r '.version // empty' "$_mk_f" 2>/dev/null)
        [ -n "$_mk_v" ] || continue
        _mk_best=$(printf '%s\n%s\n' "$_mk_best" "$_mk_v" | grep -v '^$' | sort -V 2>/dev/null | tail -1 \
            || printf '%s\n%s\n' "$_mk_best" "$_mk_v" | grep -v '^$' | sort | tail -1)
    done
    if [ -z "$_mk_best" ]; then
        for _mk_d in "$HOME"/.vscode/extensions/anthropic.claude-code-* \
                     "$HOME"/.vscode-server/extensions/anthropic.claude-code-*; do
            [ -d "$_mk_d" ] || continue
            _mk_v=$(basename "$_mk_d" | sed 's/^anthropic\.claude-code-//; s/-[a-z0-9]*-[a-z0-9]*$//')
            [ -n "$_mk_v" ] || continue
            _mk_best=$(printf '%s\n%s\n' "$_mk_best" "$_mk_v" | grep -v '^$' | sort -V 2>/dev/null | tail -1 \
                || printf '%s\n%s\n' "$_mk_best" "$_mk_v" | grep -v '^$' | sort | tail -1)
        done
    fi
    if [ -z "$_mk_best" ]; then
        _mk_b=$(mk_claude_bin) && _mk_best=$("$_mk_b" --version 2>/dev/null | awk '{print $1; exit}')
    fi
    [ -n "$_mk_best" ] || return 1
    printf '%s\n' "$_mk_best"
}
