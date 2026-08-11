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

# ---- tunable knobs -----------------------------------------------------------

# Knobs are KEY=value lines in a config file at the deployed kit root, beside
# .verified, which install.sh never wipes. A file is the only mechanism that
# reaches every context this kit runs in: hooks, skill and Bash-tool commands, the
# hook-launched miner grandchild, and the git-spawned guardrail. It is parsed
# strictly and NEVER sourced, so a stray line in a hand-edited file cannot become
# code inside a hook. Resolved from $HOME rather than this file's location, which
# is also what lets a test's fake HOME isolate it for free.
mk_state_dir() { printf '%s/.claude/memory-kit' "$HOME"; }

# mk_conf <key> <default> [int] → value. Precedence is env > file > default, with
# the env half at the call site: VAR="${VAR:-$(mk_conf VAR default)}".
# A missing file, missing key, empty value, or a non-numeric value under `int` all
# fall back to the default silently. A typo in a config file must never break a
# session start, so this fails open like everything else here.
mk_conf() {
    _mk_cf="$(mk_state_dir)/config"
    [ -r "$_mk_cf" ] || { printf '%s' "$2"; return; }
    _mk_cv=$(grep -E "^$1=" "$_mk_cf" 2>/dev/null | tail -1 | cut -d= -f2- \
             | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    [ -n "$_mk_cv" ] || { printf '%s' "$2"; return; }
    if [ "${3:-}" = int ]; then
        case "$_mk_cv" in ''|*[!0-9]*) _mk_cv="$2" ;; esac
    fi
    printf '%s' "$_mk_cv"
}

# mk_conf_off <value> → rc 0 when the value means "off". A kill switch read from a
# file needs this: presence alone would make MEMORY_KIT_NO_MINER=0 mean "on",
# which is the opposite of what anyone writing that line intends.
mk_conf_off() {
    case "$(printf '%s' "${1:-}" | tr 'A-Z' 'a-z')" in
        ''|0|no|off|false) return 0 ;;
        *) return 1 ;;
    esac
}

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

# ---- feature health ----------------------------------------------------------

# A feature that cannot run must leave a trace. Without one, "nothing happened"
# and "nothing could happen" look identical, and a machine can sit half working
# for months. One file per feature: first-seen epoch on line 1, reason on line 2.
# Lives beside the tracker, outside ~/.claude, so headless sessions can write it.

mk_health_dir() { printf '%s/health' "$(mk_tracker_dir)"; }

# mk_health_record <feature> <reason> — the first-seen epoch survives repeated
# records of the same reason, so "blocked since" is real and not reset each run.
mk_health_record() {
    _mk_hd="$(mk_health_dir)"; mkdir -p "$_mk_hd" 2>/dev/null || return 1
    _mk_hf="$_mk_hd/$1"; _mk_since=$(date +%s)
    if [ -r "$_mk_hf" ] && [ "$(sed -n '2p' "$_mk_hf" 2>/dev/null)" = "$2" ]; then
        _mk_prev=$(head -1 "$_mk_hf" 2>/dev/null)
        case "$_mk_prev" in ''|*[!0-9]*) ;; *) _mk_since="$_mk_prev" ;; esac
    fi
    printf '%s\n%s\n' "$_mk_since" "$2" > "$_mk_hf"
}

# Called on every success: recovery must be as automatic as detection, or a
# fixed machine keeps nagging.
mk_health_clear() { rm -f "$(mk_health_dir)/$1" 2>/dev/null; return 0; }

# mk_health_blocked <feature> → "<days> <reason>", rc 1 when nothing is on record.
mk_health_blocked() {
    _mk_hf="$(mk_health_dir)/$1"
    [ -r "$_mk_hf" ] || return 1
    _mk_since=$(head -1 "$_mk_hf" 2>/dev/null)
    case "$_mk_since" in ''|*[!0-9]*) return 1 ;; esac
    printf '%s %s\n' "$(( ( $(date +%s) - _mk_since ) / 86400 ))" \
                     "$(sed -n '2p' "$_mk_hf" 2>/dev/null)"
}

# ---- memory repo sync --------------------------------------------------------

# mk_git_reason <stderr-text> → offline | credentials | diverged | other.
# Matching git's prose is unavoidable here, so the classes stay coarse: each one
# points at a different thing to go and check, and anything unrecognised says so
# rather than guessing.
mk_git_reason() {
    case "$1" in
        *"Could not resolve host"*|*"could not resolve"*|*"name resolution"*|\
        *"Network is unreachable"*|*"Failed to connect"*|*"Connection refused"*|*"timed out"*)
            printf 'offline' ;;
        *"Authentication failed"*|*"could not read Username"*|*"could not read Password"*|\
        *"terminal prompts disabled"*|*"Permission denied (publickey)"*|*"Invalid username or password"*)
            printf 'credentials' ;;
        *"non-fast-forward"*|*"Not possible to fast-forward"*|*"diverged"*|*"unrelated histories"*)
            printf 'diverged' ;;
        *)  printf 'other' ;;
    esac
}

# Names how git authenticates for the memory repo, so a refused sync can say what
# to check. Read from the repo's own config, since the mechanism differs per
# machine. Wording only: nothing here decides whether a sync runs.
mk_credential_hint() {
    _mk_url=$(git -C "$(mk_memory_dir)" remote get-url origin 2>/dev/null)
    case "$_mk_url" in
        git@*|ssh://*) printf 'check the SSH key for that host'; return 0 ;;
    esac
    _mk_h=$(git -C "$(mk_memory_dir)" config --get-urlmatch credential.helper "$_mk_url" 2>/dev/null)
    case "$_mk_h" in
        '')   printf 'no credential helper is configured' ;;
        *gh*) printf 'credentials come from the GitHub CLI' ;;
        *)    printf 'credential helper: %s' "$_mk_h" ;;
    esac
}

# Pull the memory repo. Silent rc 0 when it worked or there was nothing to do;
# rc 1 and a human-readable reason otherwise. Never merges, never prompts.
# A repo with no remote, or no repo at all, is a valid setup and not a failure.
mk_memory_pull() {
    _mk_mem="$(mk_memory_dir)"
    [ -d "$_mk_mem/.git" ] || return 0
    command -v git >/dev/null 2>&1 || { printf 'git is not installed, so memory cannot sync'; return 1; }
    git -C "$_mk_mem" remote get-url origin >/dev/null 2>&1 || return 0
    _mk_err=$(GIT_TERMINAL_PROMPT=0 git -C "$_mk_mem" pull --ff-only --quiet 2>&1) && return 0
    case "$(mk_git_reason "$_mk_err")" in
        offline)     printf 'memory sync cannot reach the remote' ;;
        credentials) printf 'memory sync was refused by the remote: %s' "$(mk_credential_hint)" ;;
        diverged)    printf 'memory history has diverged, so a fast-forward pull is not possible' ;;
        *)           printf 'memory sync failed' ;;
    esac
    return 1
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
