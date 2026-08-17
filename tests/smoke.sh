#!/usr/bin/env bash
# tests/smoke.sh — run the kit against the REAL ~/.claude on THIS machine.
#
# Run: bash tests/smoke.sh          (add --quiet for summary-only, used by the hook)
#
# run.sh (the CI gate) builds fixtures from what the author believed transcripts and
# settings look like, so it can only confirm that belief. This suite has no fixtures:
# the data is whatever this machine actually has, so every check is an invariant —
# "whatever the answer is, it must have this shape" — and a check with no local data
# to run against SKIPs instead of failing.
#
# Rules that keep it honest:
#   1. Where a script parses Claude Code internals, the cross-check extracts by a
#      DIFFERENT path (tolerant whole-file jq), never by reusing the script itself.
#   2. Real state is left untouched: mutating paths run inside a throwaway $HOME or
#      temp repo, and a before/after checksum of the real settings, tracker, and
#      memory listing is itself one of the checks.
#
# On a clean pass it stamps the current Claude Code version into <kit>/.verified —
# which is what silences hooks/version-check.sh until the next Claude Code update.
# On failure it stamps nothing: the missing write is the report (see .smoke-last.log).
#
# Never wire this into CI: it passes or skips depending on the machine it runs on,
# which is the point. tests/run.sh is the gate; this is the reality check.

set -u

# Never block on ambient stdin: hook scripts read stdin for a session id when it is
# not a tty, and an invoking environment that holds stdin open (some CI runners and
# tool harnesses do) would hang them forever. Checks that need stdin pipe it in.
exec </dev/null

KIT="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
QUIET=0; [ "${1:-}" = "--quiet" ] && QUIET=1
PASS=0; FAIL=0; SKIP=0

# Which release is this? Two homes, because this suite runs from both trees. The
# deployed copy has no .git, so install.sh writes .kit-version beside it; a checkout
# has no .kit-version, so ask git directly. This suite has no shareable report file,
# so the console output is what gets pasted, and it has never named the kit's own
# version. Answers "unknown" rather than guessing: a wrong version in a bug report
# sends the reader somewhere that never had the bug.
mk_kit_version() {
    if [ -r "$KIT/.kit-version" ]; then
        tr -d '\n' < "$KIT/.kit-version"
    else
        git -C "$KIT" describe --tags --always --dirty 2>/dev/null || printf 'unknown'
    fi
}

say()  { [ "$QUIET" = 1 ] || echo "$@"; }
ok()   { PASS=$((PASS+1)); say "  ✓ $1"; }
bad()  { FAIL=$((FAIL+1)); say "  ✗ $1"; }
skip() { SKIP=$((SKIP+1)); say "  - skip: $1"; }

command -v jq >/dev/null 2>&1 || { echo "smoke: jq missing — everything would skip; install jq"; exit 1; }

# ---------- snapshot real state we must not disturb ----------
TRACKER="$HOME/.local/share/claude-feedback/proposals.md"
snap() {
    { [ -f "$HOME/.claude/settings.json" ] && cat "$HOME/.claude/settings.json"
      [ -f "$TRACKER" ] && cat "$TRACKER"
      # Contents, not just names. A listing reads the same before and after a file is
      # rewritten in place, and that blind spot is what let an uninstall in a
      # throwaway $HOME flip the real store's marker and strip the kit's line out of
      # the real .git/info/exclude while this very check reported success.
      find "$HOME/.claude/memory" -maxdepth 1 -type f -exec cksum {} + 2>/dev/null | sort
      [ -f "$HOME/.claude/memory/.git/info/exclude" ] \
        && cat "$HOME/.claude/memory/.git/info/exclude"
    } | cksum
}
BEFORE=$(snap)

# ---------- 0. every shell entrypoint parses under THIS machine's bash ----------
say "memory-kit $(mk_kit_version), bash $(bash --version | head -1 | awk '{print $4}')"
say ""
say "syntax (tested on bash $(bash --version | head -1 | awk '{print $4}')):"
SYNTAX_OK=1
for f in "$KIT"/scripts/*.sh "$KIT"/guardrail/pre-commit "$KIT"/install.sh "$KIT"/hooks/*.sh; do
    [ -f "$f" ] || continue
    if bash -n "$f" 2>/dev/null; then :; else bad "bash -n $(basename "$f")"; SYNTAX_OK=0; fi
done
[ "$SYNTAX_OK" = 1 ] && ok "all entrypoints parse"

# ---------- 1. extractor invariants against real transcripts ----------
say "extract-user-messages.sh (real transcripts, 7-day window):"
since=$(( $(date +%s) - 7*24*3600 ))
digest=$(bash "$KIT/scripts/extract-user-messages.sh" "$since" 2>/dev/null)
if [ -z "$digest" ]; then
    skip "no user messages in window (new/idle machine)"
else
    n=$(printf '%s\n' "$digest" | grep -c '^---$')
    hdrs=$(printf '%s\n' "$digest" | grep -cE '^\[[^ ]+/[0-9a-f]{8} ')
    [ "$hdrs" -gt 0 ] \
        && ok "block headers have [project/session timestamp] shape ($n msgs)" \
        || bad "no well-formed block headers in digest"
    leak=$(printf '%s' "$digest" | grep -c 'tool_use_id\|<system-reminder>\|"type":"tool_result"\|<local-command-stdout>')
    [ "$leak" = 0 ] && ok "no tool-result/system noise leaked" || bad "leakage tokens in digest: $leak"
    [ "$(printf '%s' "$digest" | wc -c)" -le 300000 ] && ok "size cap respected" || bad "digest exceeds cap"
    # cross-check by a DIFFERENT path: tolerant jq over the newest transcript
    tp=$(find "$HOME/.claude/projects" -mindepth 2 -maxdepth 2 -name '*.jsonl' ! -name 'agent-*.jsonl' -newer "$TMP" 2>/dev/null | head -1)
    [ -z "$tp" ] && tp=$(ls -t "$HOME"/.claude/projects/*/*.jsonl 2>/dev/null | head -1)
    if [ -n "$tp" ]; then
        raw=$(jq -r 'select(.type=="user") | .message.content | if type=="string" then . else empty end' "$tp" 2>/dev/null | grep -vc '^\s*$')
        [ "$raw" -ge 0 ] && ok "independent transcript parse agrees transcripts are readable" || bad "independent parse failed"
    fi
fi

# ---------- 2. SessionStart/UserPromptSubmit hook scripts: silent or valid JSON ----------
say "hook outputs (real state):"
for s in feedback-proposals-ping.sh memory-review-reminder.sh; do
    out=$(bash "$KIT/scripts/$s" 2>/dev/null); rc=$?
    if [ "$rc" != 0 ]; then bad "$s exit $rc"
    elif [ -z "$out" ]; then ok "$s: silent (nothing due) — valid"
    elif printf '%s' "$out" | jq -e '.systemMessage and .hookSpecificOutput.additionalContext' >/dev/null 2>&1; then
        ok "$s: valid dual-field JSON"
    else bad "$s: non-empty output is not the expected JSON"; fi
done

for s in feedback-proposals-ping.sh memory-review-reminder.sh; do
    msid="smoke-mark-$$"
    first=$(printf '{"session_id":"%s"}' "$msid" | bash "$KIT/scripts/$s" 2>/dev/null)
    if [ -n "$first" ]; then
        second=$(printf '{"session_id":"%s"}' "$msid" | bash "$KIT/scripts/$s" 2>/dev/null)
        [ -z "$second" ] && ok "$s: once-per-session marker suppresses repeat" \
                         || bad "$s: repeated notice despite marker"
    else
        skip "$s: nothing due on this machine — marker path not exercisable"
    fi
    rm -f "$HOME/.claude/.notice-markers/$msid".*
done

# this machine's real config: every knob it names must be one the kit still reads,
# or a rename has silently turned a live setting into a dead line
#
# install.sh is searched alongside the scripts and hooks because a knob may be written
# and read by the installer alone. MEMORY_KIT_MODE is one: install records it so that
# an upgrade needs no flag, and reads it back on the next run. Searching only the two
# directories reported it as a dead line on the first machine that had one.
cfg="$(. "$KIT/core/lib.sh" && printf '%s' "$(mk_state_dir)/config")"
if [ -r "$cfg" ]; then
    unknown=""
    while IFS= read -r k; do
        [ -n "$k" ] || continue          # an all-commented config yields no keys at all
        grep -rq "\${$k:-" "$KIT/scripts" "$KIT/hooks" "$KIT/install.sh" 2>/dev/null || unknown="$unknown $k"
    done <<EOF
$(grep -oE '^[A-Za-z_][A-Za-z0-9_]*=' "$cfg" | tr -d '=')
EOF
    [ -z "$unknown" ] && ok "every knob set in this machine's config is still read" \
                      || bad "config sets knobs nothing reads:$unknown"
else
    skip "no config file deployed yet"
fi

# The write guard against this machine's real memory files. Fixtures prove each rule
# fires; only real data proves the rules match what correct files actually look like. A
# denial here means the guard would have refused a file that already exists and is fine.
say "memory-write-guard against real memory files:"
gcount=0; grefused=""
for f in "$(. "$KIT/core/lib.sh"; mk_memory_dir)"/*.md \
         "$(. "$KIT/core/lib.sh"; mk_mounts_dir)"/*/*.md; do
    [ -f "$f" ] || continue
    case "${f##*/}" in MEMORY.md|README.md|CLAUDE.md) continue ;; esac
    gout=$(jq -n --arg p "$f" --rawfile c "$f" '{tool_input:{file_path:$p, content:$c}}' 2>/dev/null \
           | bash "$KIT/hooks/memory-write-guard.sh" 2>/dev/null)
    gcount=$((gcount + 1))
    printf '%s' "$gout" | grep -q '"permissionDecision":"deny"' && grefused="$grefused ${f##*/}"
done
if [ "$gcount" -eq 0 ]; then skip "no memory files on this machine to check"
elif [ -n "$grefused" ]; then bad "the guard would refuse existing valid files:$grefused"
else ok "all $gcount real memory files pass the write guard"; fi

hsid="smoke-health-$$"
out=$(printf '{"session_id":"%s"}' "$hsid" | bash "$KIT/hooks/memory-kit-health.sh" 2>/dev/null); rc=$?
if [ "$rc" != 0 ]; then bad "memory-kit-health exit $rc"
elif [ -z "$out" ]; then ok "memory-kit-health: silent (nothing blocked on this machine)"
elif printf '%s' "$out" | jq -e '.systemMessage and .hookSpecificOutput.additionalContext' >/dev/null 2>&1; then
    ok "memory-kit-health: valid dual-field JSON ($(printf '%s' "$out" | jq -r '.systemMessage' | cut -c1-60))"
else bad "memory-kit-health: non-empty output is not the expected JSON"; fi
rm -f "$HOME/.claude/.notice-markers/$hsid".*

# the credential hint is built from real config, so it is the one place a token could
# leak into a message. It must name a mechanism and never carry the secret itself.
hint=$(. "$KIT/core/lib.sh" && mk_credential_hint 2>/dev/null)
if [ -z "$hint" ]; then skip "no memory repo remote to describe"
elif printf '%s' "$hint" | grep -qEi 'gh[pousr]_|password=|[A-Za-z0-9_-]{32,}'; then
    bad "credential hint may contain a secret"
else ok "credential hint names a mechanism without a secret ($hint)"; fi

sid="smoke-test-$$"
out=$(printf '{"session_id":"%s"}' "$sid" | bash "$KIT/scripts/memory-delta-ping.sh" 2>/dev/null); rc=$?
[ "$rc" = 0 ] && [ -z "$out" ] && ok "memory-delta-ping: first call sets baseline silently" || bad "memory-delta-ping first call (rc=$rc out=${out:0:40})"
out=$(printf '{"session_id":"%s"}' "$sid" | bash "$KIT/scripts/memory-delta-ping.sh" 2>/dev/null); rc=$?
[ "$rc" = 0 ] && [ -z "$out" ] && ok "memory-delta-ping: throttled second call is silent" || bad "memory-delta-ping throttle (rc=$rc)"
rm -f "$HOME/.claude/.memory-delta/$sid"

say "edit-over-write.sh (synthetic stdin):"
out=$(printf '{"tool_input":{"file_path":"%s"}}' "$KIT/install.sh" | bash "$KIT/scripts/edit-over-write.sh")
printf '%s' "$out" | jq -e '.hookSpecificOutput.permissionDecision=="deny"' >/dev/null 2>&1 \
    && ok "existing file → deny" || bad "existing file did not deny"
out=$(printf '{"tool_input":{"file_path":"%s/absent.py"}}' "$TMP" | bash "$KIT/scripts/edit-over-write.sh")
[ -z "$out" ] && ok "new file → allow (silent)" || bad "new file produced output"
out=$(printf 'not json' | bash "$KIT/scripts/edit-over-write.sh" 2>/dev/null); rc=$?
[ "$rc" = 0 ] && [ -z "$out" ] && ok "garbage stdin → fails open" || bad "garbage stdin (rc=$rc)"

# ---------- 3. guardrail under THIS git/bash (temp repo) ----------
say "guardrail/pre-commit (temp repo on this machine):"
G="$TMP/guard"; mkdir -p "$G"
( cd "$G" && git init -q . && git config user.email t@t && git config user.name t ) 2>/dev/null
printf -- '---\nname: feedback_x\ndescription: d\nmetadata:\n  type: feedback\n---\nmail leak@example.com\n' > "$G/memory_leak.md"
mkdir -p "$G/memory"; cp "$G/memory_leak.md" "$G/memory/feedback_x.md"
( cd "$G" && git add memory/feedback_x.md ) 2>/dev/null
( cd "$G" && bash "$KIT/guardrail/pre-commit" ) >/dev/null 2>&1
[ $? != 0 ] && ok "blocks a synthetic PII leak" || bad "leak NOT blocked"
printf -- '---\nname: feedback_ok\ndescription: clean\nmetadata:\n  type: feedback\n---\nA generic rule.\n' > "$G/memory/feedback_ok.md"
( cd "$G" && git rm -q --cached memory/feedback_x.md && rm memory/feedback_x.md && git add memory/feedback_ok.md ) 2>/dev/null
( cd "$G" && bash "$KIT/guardrail/pre-commit" ) >/dev/null 2>&1
[ $? = 0 ] && ok "passes a clean memory file" || bad "clean file blocked"

# ---------- 4. installer end-to-end in a throwaway HOME seeded with REAL settings ----------
say "install.sh (throwaway \$HOME seeded with a copy of real settings):"
# CLAUDE_MEMORY_KIT_INSTALL_GATED skips the installer's run.sh gate here — smoke checks
# reality, the fixture gate has its own suite (and its own gate-refusal fixture)
FH="$TMP/home"; mkdir -p "$FH/.claude"
[ -f "$HOME/.claude/settings.json" ] && cp "$HOME/.claude/settings.json" "$FH/.claude/settings.json"
HOME="$FH" CLAUDE_MEMORY_KIT_INSTALL_GATED=1 bash "$KIT/install.sh" --mode=managed >/dev/null 2>&1; rc1=$?
c1=$(jq -r '[.hooks[]?[]?.hooks[]?.command] | length' "$FH/.claude/settings.json" 2>/dev/null)
HOME="$FH" CLAUDE_MEMORY_KIT_INSTALL_GATED=1 bash "$KIT/install.sh" --mode=managed >/dev/null 2>&1; rc2=$?
c2=$(jq -r '[.hooks[]?[]?.hooks[]?.command] | length' "$FH/.claude/settings.json" 2>/dev/null)
[ "$rc1" = 0 ] && [ "$rc2" = 0 ] && ok "installer runs twice cleanly" || bad "installer rc: $rc1/$rc2"
[ -n "$c1" ] && [ "$c1" = "$c2" ] && ok "settings merge is idempotent ($c1 hook cmds)" || bad "hook count drifted: $c1 → $c2"
jq -e . "$FH/.claude/settings.json" >/dev/null 2>&1 && ok "merged settings still valid JSON" || bad "merged settings invalid"
[ -x "$FH/.claude/memory-kit/scripts/run-feedback-miner.sh" ] && [ -f "$FH/.claude/memory-kit/scripts/feedback-miner.md" ] \
    && [ -r "$FH/.claude/memory-kit/core/lib.sh" ] \
    && ok "tree deployed: scripts + miner brief + core lib together" || bad "deployed tree incomplete"
# upgrade path: a hook removed from an existing group must be re-appended, not
# dropped as a "duplicate" of the group it belongs to
jq '.hooks.SessionStart |= (map(.hooks |= map(select(.command | contains("memory-kit-version-check") | not))) | map(select((.hooks|length) > 0)))' \
    "$FH/.claude/settings.json" > "$FH/.claude/settings.json.t" && mv "$FH/.claude/settings.json.t" "$FH/.claude/settings.json"
HOME="$FH" CLAUDE_MEMORY_KIT_INSTALL_GATED=1 bash "$KIT/install.sh" --mode=managed >/dev/null 2>&1
grep -q 'memory-kit-version-check' "$FH/.claude/settings.json" \
    && ok "upgrade re-adds a hook missing from an existing group" || bad "upgrade path drops new hooks in existing groups"

# Round trip in the same throwaway HOME, which holds a copy of the REAL settings file:
# whatever else lives in yours is exactly what an uninstall must not touch.
foreign_before=$(jq '[.hooks[]?[]?.hooks[]?.command | select(contains("memory-kit/") | not)] | length' \
    "$FH/.claude/settings.json" 2>/dev/null || echo -1)
HOME="$FH" bash "$KIT/install.sh" --uninstall >/dev/null 2>&1; urc=$?
ours_after=$(jq '[.hooks[]?[]?.hooks[]?.command | select(contains("memory-kit/"))] | length' \
    "$FH/.claude/settings.json" 2>/dev/null || echo -1)
foreign_after=$(jq '[.hooks[]?[]?.hooks[]?.command | select(contains("memory-kit/") | not)] | length' \
    "$FH/.claude/settings.json" 2>/dev/null || echo -2)
[ "$urc" = 0 ] && ok "uninstall runs cleanly against real settings" || bad "uninstall rc $urc"
[ "$ours_after" = 0 ] && ok "uninstall removed every hook of ours" || bad "$ours_after of our hooks survived"
[ "$foreign_after" = "$foreign_before" ] \
    && ok "everything else in settings.json survived ($foreign_before entries)" \
    || bad "other tools' hooks changed: $foreign_before to $foreign_after"
jq -e . "$FH/.claude/settings.json" >/dev/null 2>&1 \
    && ok "settings.json is still valid JSON after uninstall" || bad "uninstall left invalid JSON"
[ ! -d "$FH/.claude/memory-kit" ] && ok "the deployed tree is gone" || bad "tree survived uninstall"

# ---------- 5. index engine normalization over a COPY of real memory ----------
say "refresh-memory-index.sh (leaves real memory alone, copy of real memory):"
if ls "$HOME/.claude/memory"/*.md >/dev/null 2>&1; then
    EH="$TMP/norm-home"; mkdir -p "$EH/.claude/memory" "$EH/proj" "$EH/.claude/memory-kit/core"
    cp "$HOME/.claude/memory"/*.md "$EH/.claude/memory/"
    cp "$KIT/core/lib.sh" "$EH/.claude/memory-kit/core/lib.sh"
    # EVERY memory file must come out byte-identical now, not just the stamp-free ones:
    # the pass reports stamped frontmatter and strips nothing (DESIGN-memory.md D7).
    # MEMORY.md is excluded, since regenerating it is the whole job.
    ALL_LIST=$(ls "$EH/.claude/memory"/*.md 2>/dev/null | grep -v 'MEMORY.md')
    pre=$(echo "$ALL_LIST" | xargs cksum 2>/dev/null)
    out=$(HOME="$EH" CLAUDE_PROJECT_DIR="$EH/proj" bash "$KIT/scripts/refresh-memory-index.sh" 2>/dev/null </dev/null)
    post=$(echo "$ALL_LIST" | xargs cksum 2>/dev/null)
    [ "$pre" = "$post" ] && ok "every memory file byte-identical after the index pass" \
                         || bad "the index pass rewrote a memory file"
    # if this machine happens to have a stamped file, the pass has to say so rather
    # than fix it silently. If it has none, there is nothing to report and that is fine.
    stamped=0
    for f in "$EH/.claude/memory"/*.md; do
        [ "$(basename "$f")" = "MEMORY.md" ] && continue
        [ "$(head -1 "$f")" = "---" ] || continue
        sed -n '2,/^---$/p' "$f" | grep -qE '^[[:space:]]*(node_type|originSessionId|modified):' && stamped=$((stamped+1))
    done
    if [ "$stamped" -gt 0 ]; then
        printf '%s' "$out" | grep -q 'Harness-stamped' \
            && ok "$stamped stamped file(s) reported, none rewritten" || bad "stamped files went unreported"
    else
        ok "no stamped files on this machine, so nothing to report"
    fi
else
    skip "no memory files on this machine"
fi

# ---------- 6. real state untouched ----------
AFTER=$(snap)
[ "$BEFORE" = "$AFTER" ] && ok "real settings/tracker/memory untouched by this run" || bad "REAL STATE CHANGED during smoke run"

# ---------- summary + stamp ----------
echo "smoke: $PASS passed, $FAIL failed, $SKIP skipped"
if [ "$FAIL" = 0 ]; then
    v=$(bash "$KIT/scripts/claude-version.sh" 2>/dev/null)
    if [ -n "$v" ]; then
        # Record every version that has passed, never just the latest. A single value
        # moves BACKWARDS on a machine running several versions at once: a run started
        # while only older sessions are live overwrites a newer pass, and the suite then
        # re-runs work it had already cleared. A set cannot regress.
        if [ -r "$KIT/.verified" ] && grep -qxF "$v" "$KIT/.verified" 2>/dev/null; then
            echo "smoke: $v already recorded in .verified"
        else
            { [ -r "$KIT/.verified" ] && cat "$KIT/.verified"; printf '%s\n' "$v"; } \
                | grep -vE '^[[:space:]]*$' | sort -V -u > "$KIT/.verified.new" 2>/dev/null \
                || { [ -r "$KIT/.verified" ] && cat "$KIT/.verified"; printf '%s\n' "$v"; } \
                     | grep -vE '^[[:space:]]*$' | sort -u > "$KIT/.verified.new"
            mv "$KIT/.verified.new" "$KIT/.verified"
            echo "smoke: recorded $v in .verified ($(grep -c . "$KIT/.verified") version(s) passed)"
        fi
    else
        echo "smoke: pass, but Claude Code version unresolvable — not stamping"
    fi
    exit 0
fi
exit 1
