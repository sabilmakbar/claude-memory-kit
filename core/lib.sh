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

# The store is NAMED by autoMemoryDirectory, not computed (DESIGN-memory.md D8).
# install writes that key, so recomputing the default here means the kit ignores
# the choice it just made: an install that adopts a project store leaves every
# consumer indexing, guarding and reminding against an empty directory while
# Claude Code reads the real one. The divergence is silent, because the two agree
# on any machine where the default happened to be the store chosen.
#
# Falls back to the default whenever the key cannot be read, which covers a
# machine with no setting, no settings file, and no jq. The guardrail runs as a
# git hook in whatever environment the commit came from, so jq is not a given,
# and a missing tool has to degrade to the old behaviour rather than to nothing.
mk_memory_dir() {
    _mk_md="$HOME/.claude/memory"
    if command -v jq >/dev/null 2>&1 && [ -r "$HOME/.claude/settings.json" ]; then
        _mk_set=$(jq -r '.autoMemoryDirectory // empty' "$HOME/.claude/settings.json" 2>/dev/null)
        # the setting permits a ~/ prefix, and a bare ~ never expands inside a
        # variable, so it is spelled out here rather than passed on to break a path
        case "$_mk_set" in
            "~/"*) _mk_md="$HOME/${_mk_set#\~/}" ;;
            /*)    _mk_md="$_mk_set" ;;
        esac
    fi
    printf '%s' "$_mk_md"
}
mk_mounts_dir()   { printf '%s/.claude/memory-mounts' "$HOME"; }

# The .md files that live in a memory store without being memories. Four copies of
# this list had drifted into two lengths, so a CONTRIBUTING.md inside the store was
# exempt from the commit lint and denied by the write-time hook at the same moment:
# the kit disagreed with itself, and which answer you got depended on which check
# ran first. One definition, four callers.
#
# Three names, which is what a memory store actually holds. It carried seven for a
# while: CONTRIBUTING, CHANGELOG, DEPENDENCIES and HOW-IT-WORKS were added when the
# frontmatter lint still ran inside this kit's own checkout, where every new
# root-level document tripped a check that had no business running there. Gating the
# lint on the store removed the cause, and the four names had nothing left to do.
#
# The trade is deliberate. A store that keeps its own CHANGELOG.md is now told to
# rename it to user_/feedback_/project_, which is wrong advice for a changelog. No
# store has one today, and a name kept for a hypothetical file is how the list grew
# the first time. Add it back when a real one appears, rather than carrying four
# guesses against it.
mk_is_nonmemory() { # <basename> -> rc 0 when the file is store scaffolding, not a memory
    case "$1" in
        MEMORY.md|README.md|CLAUDE.md) return 0 ;;
        *) return 1 ;;
    esac
}

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

# Knobs renamed when the prefix became exact: MEMORY_KIT_* is a user knob and
# CLAUDE_MEMORY_KIT_* is internal. install.sh rewrites these keys inside a live
# config file, so the one place a rename cannot reach is an export in a shell
# profile on some other machine. mk_legacy_env finds exactly that, which is what
# keeps a rename from silently dropping a setting.
mk_legacy_knobs() {
    printf '%s\n' \
        'FEEDBACK_MINER_MODEL MEMORY_KIT_MINER_MODEL' \
        'MEMORY_DELTA_THROTTLE MEMORY_KIT_DELTA_THROTTLE' \
        'MEMORY_MACHINE_LABEL MEMORY_KIT_MACHINE_LABEL'
}

# mk_legacy_env → one clause per line for each old name still exported, with no
# trailing punctuation: the caller joins and terminates them like any other notice.
mk_legacy_env() {
    mk_legacy_knobs | while read -r _mk_old _mk_new; do
        [ -n "$_mk_old" ] || continue
        eval "_mk_lv=\${$_mk_old:-}"
        [ -n "$_mk_lv" ] || continue
        printf '%s is still set in the environment but is no longer read, rename it to %s\n' \
               "$_mk_old" "$_mk_new"
    done
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
# JSON-escape a string without jq. The health hook calls mk_emit_notice while reporting
# that jq is missing, so the escaper it depends on cannot need jq either.
#
# Callers used to sanitize their own interpolations, which is one sed per caller and one
# missed caller away from emitting a broken object. Notice text carries paths, health
# reasons and proposal titles, none of which this kit writes from scratch, so the escaping
# belongs here where every caller gets it.
mk_json_escape() {
    # The newline join is awk, not sed's :a;N;$!ba idiom: BSD sed discards the pattern
    # space when N runs out of input, so on macOS a single-line message came back empty
    # and the notice emitted "" instead of failing.
    printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/\t/ /g' \
      | awk 'BEGIN{ORS=""} NR>1{printf "\\n"} {print}'
}

mk_emit_notice() {
    _mk_msg=$(mk_json_escape "$1")
    printf '{"systemMessage": "%s", "hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": "%s Mention this to the user at the start of your next reply."}}\n' "$_mk_msg" "$_mk_msg"
}

# ---- the two halves ----------------------------------------------------------

# The kit installs in two halves that version independently: install.sh deploys the
# hooks, scripts and kit tree, `claude plugin install` caches the skills. Either can
# move without the other, and nothing used to say so. Both numbers are already on
# disk, so nothing new is recorded to compare them. No jq: the health hook that
# reports this is the one hook that must work when jq is gone.

# The deployed release as X.Y.Z, rc 1 when there is nothing comparable. install.sh
# records `git describe`, which writes v0.3.1 on a tag and v0.3.1-4-gabc1234,
# optionally -dirty, anywhere else. Only the exact-tag form names a release; anything
# else is a development tree, where the plugin has no matching number and a mismatch
# would be reported every day. `unknown` from an archive install is the same answer.
mk_kit_release() {
    _mk_kv=$(cat "$HOME/.claude/memory-kit/.kit-version" 2>/dev/null) || return 1
    _mk_kv=${_mk_kv#v}
    case "$_mk_kv" in ""|*[!0-9.]*) return 1 ;; esac
    printf '%s' "$_mk_kv"
}

# The cached plugin version, rc 1 when the plugin is not installed. Newest rather than
# the only one: nothing removes an old cache directory, so a machine that has updated
# keeps both, and the newest is the one the harness loads.
mk_plugin_version() {
    _mk_pd="$HOME/.claude/plugins/cache/memory-kit/memory-kit"
    [ -d "$_mk_pd" ] || return 1
    _mk_pv=$(ls "$_mk_pd" 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -1)
    [ -n "$_mk_pv" ] || return 1
    printf '%s' "$_mk_pv"
}

# The sentence for the health hook, rc 1 when the halves agree or cannot be compared.
# Direction is knowable here, unlike the deploy-drift hook's symmetric diff, so this
# names the one command that fixes it instead of describing the state.
mk_halves_mismatch() {
    _mk_hk=$(mk_kit_release) || return 1
    _mk_hp=$(mk_plugin_version) || return 1
    [ "$_mk_hk" != "$_mk_hp" ] || return 1
    if [ "$(printf '%s\n%s\n' "$_mk_hk" "$_mk_hp" | sort -V | tail -1)" = "$_mk_hk" ]; then
        printf 'the skills are at %s while the hooks and the kit tree are at %s: run claude plugin update memory-kit@memory-kit' \
            "$_mk_hp" "$_mk_hk"
    else
        # install.sh records its source checkout in .kit-source, so the advice can name
        # a runnable path. Named only while its install.sh still exists: a checkout that
        # has moved or been deleted falls back to the generic wording, because advice
        # naming a dead path is worse than advice naming no path.
        _mk_src=$(cat "$HOME/.claude/memory-kit/.kit-source" 2>/dev/null) || _mk_src=""
        if [ -n "$_mk_src" ] && [ -x "$_mk_src/install.sh" ]; then
            printf 'the hooks and the kit tree are at %s while the skills are at %s: re-run %s/install.sh' \
                "$_mk_hk" "$_mk_hp" "$_mk_src"
        else
            printf 'the hooks and the kit tree are at %s while the skills are at %s: re-run install.sh from your checkout' \
                "$_mk_hk" "$_mk_hp"
        fi
    fi
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
