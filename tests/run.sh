#!/usr/bin/env bash
# claude-memory-kit test suite. Self-contained: everything runs against throwaway
# temp dirs / fake $HOMEs; nothing touches the real ~/.claude or any real repo.
#   tests/run.sh          # run all, exit non-zero on first failure summary
set -u

# Never block on ambient stdin: hook scripts read stdin for a session id when it is
# not a tty, and an invoking environment that holds stdin open (some CI runners and
# tool harnesses do) would hang them forever. Checks that need stdin pipe it in.
exec </dev/null

KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0

ok()   { PASS=$((PASS+1)); echo "  ✓ $1"; }
fail() { FAIL=$((FAIL+1)); echo "  ✗ $1"; }
check() { # check <desc> <expected-exit> <actual-exit>
  [ "$2" = "$3" ] && ok "$1" || fail "$1 (want exit $2, got $3)"
}

# ---------- guardrail ----------
echo "guardrail/pre-commit:"
G="$TMP/guard"; mkdir -p "$G"; cd "$G"
git init -q . && git config core.hooksPath "$KIT/guardrail"
git config user.email t@t && git config user.name t

printf -- '---\nname: wrong_slug\n---\nmail me at leak@example.com\n' > feedback_bad.md
git add feedback_bad.md
"$KIT/guardrail/pre-commit" >/dev/null 2>&1; check "blocks PII + bad name at repo root" 1 $?
git rm -q --cached feedback_bad.md && rm feedback_bad.md

printf -- '---\nname: feedback_ok\ndescription: a clean rule\n---\nGeneric rule.\n' > feedback_ok.md
printf '# docs\n' > README.md
git add feedback_ok.md README.md
"$KIT/guardrail/pre-commit" >/dev/null 2>&1; check "passes clean memory file + README at root" 0 $?
git rm -qr --cached . && rm feedback_ok.md README.md

mkdir -p memory && printf -- '---\nname: x\n---\nno desc\n' > memory/notes.md
git add memory/notes.md
"$KIT/guardrail/pre-commit" >/dev/null 2>&1; check "blocks bad file under memory/" 1 $?
git rm -q --cached memory/notes.md && rm memory/notes.md

# style rule: em-dashes blocked in reader-facing docs only (same rule and scope as
# claude-session-kit). This suite is outside the scope, so it may hold the literal char.
mkdir -p docs
printf 'a clause — set off wrong\n' > docs/style.md
git add docs/style.md
"$KIT/guardrail/pre-commit" >/dev/null 2>&1; check "blocks an em-dash staged in docs/*.md" 1 $?
git rm -q --cached docs/style.md && rm docs/style.md

printf 'intro — dense on purpose\n' > README.md
git add README.md
"$KIT/guardrail/pre-commit" >/dev/null 2>&1; check "blocks an em-dash staged in README.md" 1 $?
git rm -q --cached README.md && rm README.md

# negative controls: memory files keep their em-dashes (exempt prose), and the
# frontmatter lint never reaches docs/ (its path filter is root + memory/ only)
printf -- '---\nname: feedback_dash\ndescription: legit — memory prose is exempt\n---\nBody — with dashes.\n' > feedback_dash.md
printf 'plain doc prose, no frontmatter, no dashes\n' > docs/notes.md
git add feedback_dash.md docs/notes.md
"$KIT/guardrail/pre-commit" >/dev/null 2>&1; check "memory file with em-dash + frontmatter-less docs file both pass" 0 $?
git rm -qr --cached . && rm feedback_dash.md docs/notes.md && rmdir docs

# ---------- adoption merge + index engine ----------
echo "scripts/ensure-memory-symlink.sh:"
FH="$TMP/home1"; mkdir -p "$FH/.claude/memory" "$FH/proj"
printf 'central\n' > "$FH/.claude/memory/feedback_collide.md"
ENC="$(echo "$FH/proj" | tr '/' '-')"; MD="$FH/.claude/projects/$ENC/memory"; mkdir -p "$MD/subdir"
printf 'project\n' > "$MD/feedback_collide.md"
printf -- '---\nname: old_note\ndescription: adopted\n---\nb\n' > "$MD/old-note.md"
printf 'nested\n' > "$MD/subdir/nested.md"
HOME="$FH" CLAUDE_PROJECT_DIR="$FH/proj" bash "$KIT/scripts/ensure-memory-symlink.sh" >/dev/null 2>&1

[ "$(readlink "$MD")" = "$FH/.claude/memory" ] && ok "project dir becomes symlink" || fail "symlink"
[ "$(cat "$FH/.claude/memory/feedback_collide.md")" = "central" ] && ok "collision keeps central copy" || fail "collision"
[ -f "$FH/.claude/memory/old-note.md" ] && ok "adopted file copied to central" || fail "adopt copy"
b=$(ls -d "$FH/.claude/projects/$ENC/memory.pre-kit."*.bak 2>/dev/null | head -1)
[ -n "$b" ] && [ -f "$b/subdir/nested.md" ] && ok "backup keeps subdir + collided copy" || fail "backup"
grep -q "Unindexed.*old-note.md" "$FH/.claude/memory/MEMORY.md" && ok "unindexed file flagged in index" || fail "unindexed flag"

printf '# my repo\n' > "$FH/.claude/memory/README.md"
printf '# guide\n' > "$FH/.claude/memory/CLAUDE.md"
HOME="$FH" CLAUDE_PROJECT_DIR="$FH/proj" bash "$KIT/scripts/ensure-memory-symlink.sh" >/dev/null 2>&1
grep "Unindexed" "$FH/.claude/memory/MEMORY.md" | grep -qE "README|CLAUDE" \
  && fail "known docs wrongly flagged" || ok "README/CLAUDE.md exempt from unindexed warning"

# --- stamped-frontmatter normalization (issue #16) ---
# fixture mirrors the harness writer byte-for-byte: node_type/originSessionId nested
# under a `metadata: ` line with a trailing space, `modified` at the top level
NH="$TMP/home-norm"; mkdir -p "$NH/.claude/memory" "$NH/proj"
SF="$NH/.claude/memory/feedback_stamped.md"
printf -- '---\nname: feedback_stamped\ndescription: "keeps this"\nmetadata: \n  node_type: memory\n  type: feedback\n  originSessionId: cc6d0e44-5eaa-4a7b-8eff-28a7a81a4562\nmodified: 2026-08-10T08:00:00.000Z\n---\n\nBody keeps\nmodified: mentions.\n' > "$SF"
CF="$NH/.claude/memory/feedback_clean.md"
printf -- '---\nname: feedback_clean\ndescription: "c"\nmetadata:\n  type: feedback\n---\nmodified: in body only.\n' > "$CF"
REF1="$TMP/norm-ref1"; touch "$REF1"; sleep 1   # any rewrite lands strictly after REF1
HOME="$NH" CLAUDE_PROJECT_DIR="$NH/proj" bash "$KIT/scripts/ensure-memory-symlink.sh" >/dev/null 2>&1

fm() { sed -n '2,/^---$/p' "$1"; }   # frontmatter block of a file
fm "$SF" | grep -q 'node_type'        && fail "node_type stripped" || ok "node_type stripped"
fm "$SF" | grep -q 'originSessionId'  && fail "originSessionId stripped" || ok "originSessionId stripped"
fm "$SF" | grep -q '^modified:'       && fail "modified stripped from frontmatter" || ok "modified stripped from frontmatter"
grep -q '^modified: mentions' "$SF"   && ok "body text left alone" || fail "body text left alone"
grep -q '^metadata:$' "$SF" && grep -q '^  type: feedback$' "$SF" && grep -q '^name: feedback_stamped$' "$SF" \
  && ok "kept fields intact, metadata trailing space healed" || fail "kept fields intact"
grep -q 'feedback_stamped.md) — keeps this' "$NH/.claude/memory/MEMORY.md" \
  && ok "normalized file still indexed" || fail "normalized file still indexed"
[ "$CF" -nt "$REF1" ] && fail "stamp-free file never rewritten" || ok "stamp-free file never rewritten"

# second run: central file already healed must not be rewritten again (mtime churn
# would re-trigger delta pings and dirty the repo); a freshly stamped mount file heals
MNT=$(ls -d "$NH/.claude/memory-mounts"/*/ 2>/dev/null | head -1)
printf -- '---\nname: proj_note\ndescription: "m"\nmetadata: \n  node_type: memory\n  type: project\n---\nb\n' > "$MNT/proj_note.md"
REF2="$TMP/norm-ref2"; touch "$REF2"; sleep 1
HOME="$NH" CLAUDE_PROJECT_DIR="$NH/proj" bash "$KIT/scripts/ensure-memory-symlink.sh" >/dev/null 2>&1
[ "$SF" -nt "$REF2" ] && fail "healed file not rewritten again" || ok "healed file not rewritten again"
fm "$MNT/proj_note.md" | grep -q 'node_type' && fail "mount-side file healed too" || ok "mount-side file healed too"

# ---------- memory-delta-ping ----------
echo "scripts/memory-delta-ping.sh:"
DH="$TMP/home2"; mkdir -p "$DH/.claude/memory" "$DH/.claude/memory-mounts/-m"
printf -- '---\nname: feedback_x\n---\nr\n' > "$DH/.claude/memory/feedback_x.md"
printf '# idx\n' > "$DH/.claude/memory/MEMORY.md"
ping() { echo "{\"session_id\":\"$1\"}" | HOME="$DH" MEMORY_DELTA_THROTTLE="${2:-0}" bash "$KIT/scripts/memory-delta-ping.sh"; }

[ -z "$(ping s1)" ] && ok "first prompt: silent baseline" || fail "baseline"
sleep 1
[ -z "$(ping s1)" ] && ok "no change: silent" || fail "quiet"
touch "$DH/.claude/memory/feedback_x.md" "$DH/.claude/memory-mounts/-m/project_y.md"
out=$(ping s1)
echo "$out" | grep -q "memory/feedback_x.md" && echo "$out" | grep -q "memory-mounts/-m/project_y.md" \
  && ok "change: notice lists both files" || fail "notice ($out)"
[ -z "$(ping s1)" ] && ok "same change: announced once" || fail "dedup"
sleep 1; touch "$DH/.claude/memory/feedback_x.md"
[ -z "$(ping s1 3600)" ] && ok "inside throttle: silent" || fail "throttle"
out=$(ping s1)  # throttle passed (0): pending change delivered late, not lost
echo "$out" | grep -q "feedback_x.md" && ok "throttled change delivered after window" || fail "late delivery"
sleep 1; printf '# regen\n' > "$DH/.claude/memory/MEMORY.md"
[ -z "$(ping s1)" ] && ok "MEMORY.md regen alone: silent" || fail "MEMORY.md excluded"
[ -z "$(ping '../../../tmp/evil')" ] && [ ! -e "$DH/tmp" ] \
  && ok "session_id traversal sanitized" || fail "traversal"

# ---------- edit-over-write ----------
echo "scripts/edit-over-write.sh:"
EF="$TMP/existing.txt"; touch "$EF"
out=$(echo "{\"tool_input\":{\"file_path\":\"$EF\"}}" | bash "$KIT/scripts/edit-over-write.sh")
echo "$out" | grep -q '"permissionDecision":"deny"' && ok "denies Write on existing file" || fail "deny existing"
out=$(echo "{\"tool_input\":{\"file_path\":\"$TMP/brand-new.txt\"}}" | bash "$KIT/scripts/edit-over-write.sh")
[ -z "$out" ] && ok "allows Write on new file" || fail "allow new"
out=$(echo 'not json' | bash "$KIT/scripts/edit-over-write.sh" 2>/dev/null); rc=$?
[ -z "$out" ] && [ "$rc" = 0 ] && ok "fails open on garbage input" || fail "fail-open"

# ---------- session-start reminders ----------
echo "scripts/memory-review-reminder.sh:"
RH="$TMP/home4"; mkdir -p "$RH/.claude/memory"
date +%s > "$RH/.claude/memory/.last-review"
out=$(HOME="$RH" bash "$KIT/scripts/memory-review-reminder.sh")
[ -z "$out" ] && ok "fresh stamp: silent" || fail "fresh stamp"
echo $(( $(date +%s) - 9*86400 )) > "$RH/.claude/memory/.last-review"
out=$(HOME="$RH" bash "$KIT/scripts/memory-review-reminder.sh")
echo "$out" | grep -q '"additionalContext".*9 days' && ok "9-day-old stamp: reminder with day count" || fail "overdue ($out)"
rm "$RH/.claude/memory/.last-review"
out=$(HOME="$RH" bash "$KIT/scripts/memory-review-reminder.sh")
echo "$out" | grep -q 'Memory review due' && ok "missing stamp: reminder" || fail "missing stamp"

RG="$TMP/home8"; mkdir -p "$RG/.claude/memory"
git init -q "$RG/.claude/memory"
git -C "$RG/.claude/memory" config user.email t@t && git -C "$RG/.claude/memory" config user.name t
remind() { HOME="$RG" MEMORY_MACHINE_LABEL=testbox bash "$KIT/scripts/memory-review-reminder.sh"; }
out=$(remind)
echo "$out" | grep -q 'never recorded' && ok "git repo, no marker: honest never-reviewed nag" || fail "no marker ($out)"
git -C "$RG/.claude/memory" commit -q --allow-empty -m "memory review (otherbox): no changes"
[ -z "$(remind)" ] && ok "git: fresh marker by ANY machine silences nag" || fail "any-machine marker"
mkdir -p "$RG/.claude/memory-mounts/-m" && printf 'x\n' > "$RG/.claude/memory-mounts/-m/project_x.md"
out=$(remind)
echo "$out" | grep -q 'mount-local memories never reviewed' && ok "git: mounts need THIS machine's marker" || fail "mount scope ($out)"
git -C "$RG/.claude/memory" commit -q --allow-empty -m "memory review (testbox): no changes"
[ -z "$(remind)" ] && ok "git: own marker silences mount nag" || fail "own marker"
RG9="$TMP/home9"; mkdir -p "$RG9/.claude/memory"
git init -q "$RG9/.claude/memory"
git -C "$RG9/.claude/memory" config user.email t@t && git -C "$RG9/.claude/memory" config user.name t
old_epoch=$(( $(date +%s) - 9*86400 ))
GIT_COMMITTER_DATE="@$old_epoch +0000" GIT_AUTHOR_DATE="@$old_epoch +0000" \
    git -C "$RG9/.claude/memory" commit -q --allow-empty -m "memory review (otherbox): tidy"
out=$(HOME="$RG9" MEMORY_MACHINE_LABEL=testbox bash "$KIT/scripts/memory-review-reminder.sh")
echo "$out" | grep -q '9 days since last, any machine' && ok "git: stale marker: day count from history" || fail "stale marker ($out)"
# once-per-session notice marker (session_id piped like the SessionStart harness does)
remsid() { echo "{\"session_id\":\"$1\"}" | HOME="$RG9" MEMORY_MACHINE_LABEL=testbox bash "$KIT/scripts/memory-review-reminder.sh"; }
out=$(remsid r1)
echo "$out" | grep -q '9 days' && ok "sid: due nag fires on first notice" || fail "sid first ($out)"
[ -z "$(remsid r1)" ] && ok "sid: same session same day is silent" || fail "sid repeat"

echo "scripts/feedback-proposals-ping.sh:"
PH="$TMP/home5"; mkdir -p "$PH/.local/share/claude-feedback"
out=$(HOME="$PH" bash "$KIT/scripts/feedback-proposals-ping.sh")
[ -z "$out" ] && ok "no tracker: silent" || fail "no tracker"
printf '## Pending\n\n## Accepted\n\n### P-001 · accepted · x\n' > "$PH/.local/share/claude-feedback/proposals.md"
out=$(HOME="$PH" bash "$KIT/scripts/feedback-proposals-ping.sh")
[ -z "$out" ] && ok "empty Pending: silent (Accepted not counted)" || fail "empty pending ($out)"
printf '## Pending\n\n### P-009 · total 9 · Rule A\n### P-010 · total 5 · Rule B\n\n## Accepted\n' > "$PH/.local/share/claude-feedback/proposals.md"
out=$(HOME="$PH" bash "$KIT/scripts/feedback-proposals-ping.sh")
echo "$out" | grep -q '2 feedback proposal(s) pending (top: P-009' && ok "counts pending, names top proposal" || fail "pending count ($out)"
# once-per-session notice marker
pingsid() { echo "{\"session_id\":\"$1\"}" | HOME="$PH" bash "$KIT/scripts/feedback-proposals-ping.sh"; }
out=$(pingsid m1)
echo "$out" | grep -q '2 feedback proposal' && ok "sid m1: first notice fires" || fail "sid first ($out)"
[ -z "$(pingsid m1)" ] && ok "sid m1: repeat same day is silent" || fail "sid repeat"
out=$(pingsid m2)
echo "$out" | grep -q '2 feedback proposal' && ok "sid m2: another session still notices" || fail "sid isolation ($out)"
printf '2020-01-01\n' > "$PH/.claude/.notice-markers/m1.proposals"
out=$(pingsid m1)
echo "$out" | grep -q '2 feedback proposal' && ok "sid m1: a new day re-notices" || fail "sid rollover ($out)"
out=$(echo '{}' | HOME="$PH" bash "$KIT/scripts/feedback-proposals-ping.sh")
echo "$out" | grep -q '2 feedback proposal' && ok "no session id: fails open and notices" || fail "sid fail-open ($out)"

# ---------- feedback miner: remote sync ----------
echo "scripts/run-feedback-miner.sh:"
SB="$TMP/stub"; mkdir -p "$SB"; printf '#!/bin/sh\nexit 0\n' > "$SB/claude"; chmod +x "$SB/claude"
git init -q "$TMP/mem-src" && ( cd "$TMP/mem-src" && git config user.email t@t && git config user.name t \
  && printf 'seed\n' > seed.md && git add seed.md && git commit -qm seed )
git clone -q --bare "$TMP/mem-src" "$TMP/mem-origin.git"
MH="$TMP/home6"; mkdir -p "$MH/.claude"
git clone -q "$TMP/mem-origin.git" "$MH/.claude/memory"
git clone -q "$TMP/mem-origin.git" "$TMP/mem-other"
( cd "$TMP/mem-other" && git config user.email t@t && git config user.name t \
  && printf 'remote rule\n' > feedback_remote.md && git add . && git commit -qm remote && git push -q )
HOME="$MH" PATH="$SB:$PATH" bash "$KIT/scripts/run-feedback-miner.sh" >/dev/null 2>&1
[ -f "$MH/.claude/memory/feedback_remote.md" ] && ok "daily run pulls memory repo first" || fail "pull missing"
UH="$TMP/home7"; mkdir -p "$UH/.claude"
git clone -q "$TMP/mem-origin.git" "$UH/.claude/memory"
git -C "$UH/.claude/memory" remote set-url origin "$TMP/nonexistent.git"
HOME="$UH" PATH="$SB:$PATH" bash "$KIT/scripts/run-feedback-miner.sh" >/dev/null 2>&1
check "unreachable origin: miner run still succeeds" 0 $?

# ---------- installer ----------
# fixtures set MEMORY_KIT_INSTALL_GATED so the installer's own test gate doesn't
# recurse back into this suite
echo "install.sh:"
IH="$TMP/home3"; mkdir -p "$IH/.claude/memory"
printf 'customized\n' > "$IH/.claude/memory/feedback_memory_conventions.md"
HOME="$IH" MEMORY_KIT_INSTALL_GATED=1 bash "$KIT/install.sh" >/dev/null 2>&1
HOME="$IH" MEMORY_KIT_INSTALL_GATED=1 bash "$KIT/install.sh" >/dev/null 2>&1
[ "$(cat "$IH/.claude/memory/feedback_memory_conventions.md")" = "customized" ] \
  && ok "re-run keeps customized seed file" || fail "seed clobbered"
n=$(jq '[.hooks[][].hooks[].command] | length' "$IH/.claude/settings.json")
n2=$(jq '[.hooks[][].hooks[].command] | unique | length' "$IH/.claude/settings.json")
[ "$n" = "$n2" ] && ok "hooks deduped across re-runs ($n entries)" || fail "hook dupes ($n vs $n2)"
[ -x "$IH/.claude/memory-kit/scripts/run-feedback-miner.sh" ] && [ -r "$IH/.claude/memory-kit/core/lib.sh" ] \
  && ok "deploys one tree: scripts + core lib together" || fail "tree deploy incomplete"
# migration: a pre-tree layout (script copies + old-path hooks) converges to the tree
MH2="$TMP/home8"; mkdir -p "$MH2/.claude/scripts"
printf '#!/bin/sh\n' > "$MH2/.claude/scripts/feedback-proposals-ping.sh"
printf '#!/bin/sh\n' > "$MH2/.claude/scripts/unrelated-tool.sh"
printf '{"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"\\"$HOME/.claude/scripts/feedback-proposals-ping.sh\\" 2>/dev/null || true"},{"type":"command","command":"\\"$HOME/.claude/scripts/unrelated-tool.sh\\" || true"}]}]}}\n' > "$MH2/.claude/settings.json"
HOME="$MH2" MEMORY_KIT_INSTALL_GATED=1 bash "$KIT/install.sh" >/dev/null 2>&1
# exactly ONE entry for the migrated script: the old command re-pointed in place,
# not left mangled beside a merge-appended duplicate
pcount=$(jq '[.hooks[][].hooks[].command | select(contains("feedback-proposals-ping.sh"))] | length' "$MH2/.claude/settings.json")
[ "$pcount" = 1 ] && grep -q 'memory-kit/scripts/feedback-proposals-ping.sh' "$MH2/.claude/settings.json" \
  && ok "migration re-points our old-path hooks in place (no duplicates)" || fail "hook migration ($pcount entries)"
grep -q 'scripts/null' "$MH2/.claude/settings.json" \
  && fail "migration corrupted a command to scripts/null" || ok "migration never mangles a command"
grep -q '\.claude/scripts/unrelated-tool.sh' "$MH2/.claude/settings.json" \
  && ok "migration leaves other tools' hooks alone" || fail "migration overreach"
[ ! -f "$MH2/.claude/scripts/feedback-proposals-ping.sh" ] && [ -f "$MH2/.claude/scripts/unrelated-tool.sh" ] \
  && ok "legacy cleanup removes only our stale copies" || fail "legacy cleanup"
# the gate: a tree whose tests fail is never deployed
GK="$TMP/gated-kit"; mkdir -p "$GK"
cp -R "$KIT/scripts" "$GK/scripts"; cp -R "$KIT/core" "$GK/core"
cp -R "$KIT/hooks" "$GK/hooks"; cp -R "$KIT/tests" "$GK/tests"
cp -R "$KIT/seed-memories" "$GK/seed-memories"; cp -R "$KIT/skills" "$GK/skills"; cp -R "$KIT/guardrail" "$GK/guardrail"
cp "$KIT/install.sh" "$KIT/settings.snippet.json" "$GK/"
printf '#!/bin/sh\nexit 1\n' > "$GK/tests/run.sh"
GH2="$TMP/home10"; mkdir -p "$GH2/.claude"
# clear the guard explicitly: when THIS suite is itself run by an installer's gate,
# the fixture must not inherit the skip and let the sabotaged kit through
HOME="$GH2" MEMORY_KIT_INSTALL_GATED= bash "$GK/install.sh" >/dev/null 2>&1
check "gate: failing tests refuse to deploy" 1 $?
[ ! -d "$GH2/.claude/memory-kit" ] && ok "gate: nothing was deployed" || fail "gate deployed anyway"

echo
echo "passed $PASS, failed $FAIL"
[ "$FAIL" = 0 ]
