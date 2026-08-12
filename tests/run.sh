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
# Hermetic by construction: the hook reads denylist.local from ITS OWN directory, so
# running the repo copy would read whatever private terms this machine happens to
# have. Every check below runs a copy whose denylist we control, so a pass means the
# same thing on a developer machine as in CI.
GH="$TMP/guardrail"; mkdir -p "$GH"
cp "$KIT/guardrail/pre-commit" "$GH/pre-commit"
G="$TMP/guard"; mkdir -p "$G"; cd "$G"
git init -q . && git config core.hooksPath "$GH"
git config user.email t@t && git config user.name t

printf -- '---\nname: wrong_slug\n---\nmail me at leak@example.com\n' > feedback_bad.md
git add feedback_bad.md
"$GH/pre-commit" >/dev/null 2>&1; check "blocks PII + bad name at repo root" 1 $?
git rm -q --cached feedback_bad.md && rm feedback_bad.md

printf -- '---\nname: feedback_ok\ndescription: a clean rule\n---\nGeneric rule.\n' > feedback_ok.md
printf '# docs\n' > README.md
git add feedback_ok.md README.md
"$GH/pre-commit" >/dev/null 2>&1; check "passes clean memory file + README at root" 0 $?
git rm -qr --cached . && rm feedback_ok.md README.md

mkdir -p memory && printf -- '---\nname: x\n---\nno desc\n' > memory/notes.md
git add memory/notes.md
"$GH/pre-commit" >/dev/null 2>&1; check "blocks bad file under memory/" 1 $?
git rm -q --cached memory/notes.md && rm memory/notes.md

# style rule: em-dashes blocked in reader-facing docs only (same rule and scope as
# claude-session-kit). This suite is outside the scope, so it may hold the literal char.
mkdir -p docs
printf 'a clause — set off wrong\n' > docs/style.md
git add docs/style.md
"$GH/pre-commit" >/dev/null 2>&1; check "blocks an em-dash staged in docs/*.md" 1 $?
git rm -q --cached docs/style.md && rm docs/style.md

printf 'intro — dense on purpose\n' > README.md
git add README.md
"$GH/pre-commit" >/dev/null 2>&1; check "blocks an em-dash staged in README.md" 1 $?
git rm -q --cached README.md && rm README.md

# negative controls: memory files keep their em-dashes (exempt prose), and the
# frontmatter lint never reaches docs/ (its path filter is root + memory/ only)
printf -- '---\nname: feedback_dash\ndescription: legit — memory prose is exempt\n---\nBody — with dashes.\n' > feedback_dash.md
printf 'plain doc prose, no frontmatter, no dashes\n' > docs/notes.md
git add feedback_dash.md docs/notes.md
"$GH/pre-commit" >/dev/null 2>&1; check "memory file with em-dash + frontmatter-less docs file both pass" 0 $?
git rm -qr --cached . && rm feedback_dash.md docs/notes.md && rmdir docs

# private terms: both mechanisms, because breaking either one is silent. The generic
# patterns would keep blocking emails and home paths, every other check here would
# stay green, and only the terms you listed would quietly stop being checked.
printf -- '---\nname: feedback_terms\ndescription: d\n---\nthe northwind engagement notes\n' > feedback_terms.md
git add feedback_terms.md
"$GH/pre-commit" >/dev/null 2>&1
check "control: with no denylist and no env var, the term passes" 0 $?
printf 'northwind\n' > "$GH/denylist.local"
"$GH/pre-commit" >/dev/null 2>&1
check "a term from denylist.local blocks the commit" 1 $?
rm -f "$GH/denylist.local"
CLAUDE_CONFIG_DENYLIST=northwind "$GH/pre-commit" >/dev/null 2>&1
check "a term from CLAUDE_CONFIG_DENYLIST blocks the commit" 1 $?
# a file of only comments and blanks must not turn into a pattern that matches anything
printf '# northwind is only mentioned in a comment\n\n' > "$GH/denylist.local"
"$GH/pre-commit" >/dev/null 2>&1
check "comments and blank lines in denylist.local are not terms" 0 $?
printf '# a comment\n\ntyrell\n' > "$GH/denylist.local"
"$GH/pre-commit" >/dev/null 2>&1
check "control: a real term beside the comment still passes other content" 0 $?
printf -- '---\nname: feedback_terms\ndescription: d\n---\nthe tyrell account\n' > feedback_terms.md
git add feedback_terms.md
"$GH/pre-commit" >/dev/null 2>&1
check "a term after a comment line is still read" 1 $?
rm -f "$GH/denylist.local"
git rm -qr --cached . && rm feedback_terms.md

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

# a rewrite inside the user's repo is never silent: it would otherwise appear in git
# status as a change nobody made
out=$(HOME="$NH" CLAUDE_PROJECT_DIR="$NH/proj" bash "$KIT/scripts/ensure-memory-symlink.sh" 2>/dev/null)
[ -z "$out" ] && ok "a run that heals nothing stays silent" || fail "noise with nothing to heal ($out)"
printf -- '---\nname: feedback_loud\ndescription: "d"\nmetadata:\n  node_type: memory\n  type: feedback\n  source: direct\n---\nb\n' \
  > "$NH/.claude/memory/feedback_loud.md"
out=$(HOME="$NH" CLAUDE_PROJECT_DIR="$NH/proj" bash "$KIT/scripts/ensure-memory-symlink.sh" 2>/dev/null)
printf '%s' "$out" | grep -q "feedback_loud.md" \
  && ok "a healed file is named in the output" || fail "healed a file silently ($out)"
printf '%s' "$out" | grep -qE "node_type|stamped" \
  && ok "and the output says what was removed" || fail "does not say what changed"

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
ping() { echo "{\"session_id\":\"$1\"}" | HOME="$DH" MEMORY_KIT_DELTA_THROTTLE="${2:-0}" bash "$KIT/scripts/memory-delta-ping.sh"; }

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

# ---------- memory write guard ----------
# The conventions moved out of two seeded memory files into this check plus guidance/.
# Enforcement must match what real, correct memory files look like: several legitimate
# rules carry their own "how" with no section header, a user_ profile has no **Why:**,
# and a [[wikilink]] may point at a memory not written yet. Denying any of those would
# make the hook worse than the drift it replaces, so each has its own check.
echo "hooks/memory-write-guard.sh:"
WH="$TMP/home-guard"; MEMD="$WH/.claude/memory"; MNTD="$WH/.claude/memory-mounts/-work"
mkdir -p "$MEMD" "$MNTD"
guard() { # guard <file_path> <content> [tool_input field]
  jq -n --arg p "$1" --arg c "$2" --arg f "${3:-content}" \
     '{tool_input: ({file_path:$p} + {($f): $c})}' \
    | HOME="$WH" bash "$KIT/hooks/memory-write-guard.sh" 2>/dev/null
}
denied() { printf '%s' "$1" | grep -q '"permissionDecision":"deny"'; }

GOOD='---
name: feedback_sample
description: a rule
metadata:
  type: feedback
  source: direct
---

Do the thing.

**Why:** it matters.
'
out=$(guard "$MEMD/feedback_sample.md" "$GOOD")
denied "$out" && fail "a compliant file was denied ($out)" || ok "a compliant memory file passes"
out=$(guard "$MEMD/notes.md" "$GOOD")
denied "$out" && ok "a filename without a type prefix is denied" || fail "prefix not enforced"
out=$(guard "$MEMD/feedback_sample.md" "$(printf '%s' "$GOOD" | sed 's/^name: feedback_sample/name: feedback-sample/')")
denied "$out" && ok "a kebab-case name that breaks wikilinks is denied" || fail "name mismatch not caught"
out=$(guard "$MEMD/feedback_sample.md" "$(printf '%s' "$GOOD" | grep -v '^description:')")
denied "$out" && ok "a missing description is denied" || fail "description not enforced"
out=$(guard "$MEMD/feedback_sample.md" "$(printf '%s' "$GOOD" | grep -v '^  type: feedback')")
denied "$out" && ok "a missing metadata type is denied" || fail "type not enforced"
out=$(guard "$MEMD/feedback_sample.md" "$(printf '%s' "$GOOD" | grep -v '^\*\*Why:\*\*')")
denied "$out" && ok "a feedback rule with no Why line is denied" || fail "Why not enforced"
out=$(guard "$MEMD/feedback_sample.md" "$(printf '%s' "$GOOD" | grep -v '^  source:')")
denied "$out" && ok "a file with no origin is denied" || fail "origin not enforced"
out=$(guard "$MEMD/feedback_sample.md" "$(printf '%s' "$GOOD" | sed 's/^  source: direct$/  source: feedback-miner/')")
denied "$out" && fail "feedback-miner was rejected as an origin ($out)" || ok "feedback-miner is a valid origin"
# the id is what made the field machine-local and wrong, so nothing may follow the value
out=$(guard "$MEMD/feedback_sample.md" "$(printf '%s' "$GOOD" | sed 's/^  source: direct$/  source: feedback-miner (P-009, accepted 2026-08-11)/')")
denied "$out" && ok "an origin with a proposal id appended is denied" || fail "id accepted after the value"
out=$(guard "$MEMD/feedback_sample.md" "$(printf '%s' "$GOOD" | sed 's/^  source: direct$/  source: somewhere-else/')")
denied "$out" && ok "an unknown origin value is denied" || fail "any value accepted"

out=$(guard "$MEMD/feedback_sample.md" "$GOOD
**Evidence:** the user said something, on a date.
")
denied "$out" && ok "an Evidence section in global memory is denied" || fail "evidence leak surface open"

# shapes that must NEVER be denied, each taken from a real memory file
out=$(guard "$MEMD/user_someone.md" '---
name: user_someone
description: who the user is
metadata:
  type: user
  source: direct
---

Works on things. Prefers directness.
')
denied "$out" && fail "a user_ profile was denied for having no Why ($out)" \
             || ok "a user_ profile needs no Why line"
out=$(guard "$MEMD/feedback_sample.md" "$GOOD
Related: [[feedback_not_written_yet]].
")
denied "$out" && fail "a forward wikilink was denied" || ok "a wikilink to an unwritten memory passes"
out=$(guard "$MEMD/feedback_sample.md" "$(printf '%s' "$GOOD" | sed 's/Do the thing./Always do the thing, no exceptions./')")
denied "$out" && fail "a rule carrying its own how was denied" || ok "the How section stays optional"
out=$(guard "$MNTD/project_thing.md" '---
name: project_thing
description: a project fact
metadata:
  type: project
  source: direct
---

**Evidence:** local notes are fine here.
')
denied "$out" && fail "a mount file was held to the synced-tier rule ($out)" \
             || ok "mount memory keeps its own evidence"

# scope and fail-open
out=$(guard "$MEMD/MEMORY.md" "no frontmatter at all")
[ -z "$out" ] && ok "the generated index is out of scope" || fail "MEMORY.md was checked"
out=$(guard "$WH/somewhere/else/notes.md" "no frontmatter at all")
[ -z "$out" ] && ok "files outside memory are out of scope" || fail "scope leaked"
out=$(printf 'not json\n' | HOME="$WH" bash "$KIT/hooks/memory-write-guard.sh" 2>/dev/null); rc=$?
[ -z "$out" ] && [ "$rc" = 0 ] && ok "garbage stdin fails open" || fail "fail-open (rc=$rc)"

# The hook declares what it enforces, and the guidance must agree in both directions.
# Prose describing code is exactly what drifts, so this is bound rather than trusted:
# the same failure the config.example inventory checks catch for knobs.
RULES=$(bash "$KIT/hooks/memory-write-guard.sh" --rules)
[ -n "$RULES" ] && ok "the hook declares the rules it enforces" || fail "--rules printed nothing"
undenied=""; undocumented=""
for r in $RULES; do
  grep -q "deny $r " "$KIT/hooks/memory-write-guard.sh" || undenied="$undenied $r"
  grep -q "rule: $r" "$KIT/guidance/memory-authoring.md" || undocumented="$undocumented $r"
done
[ -z "$undenied" ] && ok "every declared rule has a deny site" || fail "declared but never enforced:$undenied"
[ -z "$undocumented" ] && ok "every enforced rule is documented in the guidance" \
                       || fail "enforced but undocumented:$undocumented"
stale=""
for m in $(grep -oE 'rule: [a-z-]+' "$KIT/guidance/memory-authoring.md" | awk '{print $2}'); do
  printf '%s\n' $RULES | grep -qx "$m" || stale="$stale $m"
done
[ -z "$stale" ] && ok "the guidance names no rule the hook does not enforce" || fail "stale in guidance:$stale"

# an Edit shows only a fragment, so absence can never be judged from it
out=$(guard "$MEMD/feedback_sample.md" "one edited sentence." new_string)
[ -z "$out" ] && ok "an Edit fragment is not judged for missing sections" || fail "Edit judged on absence"
out=$(guard "$MEMD/feedback_sample.md" "name: feedback-wrong" new_string)
denied "$out" && ok "an Edit that introduces a bad name is still caught" || fail "Edit name check missing"

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
remind() { HOME="$RG" MEMORY_KIT_MACHINE_LABEL=testbox bash "$KIT/scripts/memory-review-reminder.sh"; }
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
out=$(HOME="$RG9" MEMORY_KIT_MACHINE_LABEL=testbox bash "$KIT/scripts/memory-review-reminder.sh")
echo "$out" | grep -q '9 days since last, any machine' && ok "git: stale marker: day count from history" || fail "stale marker ($out)"
# once-per-session notice marker (session_id piped like the SessionStart harness does)
remsid() { echo "{\"session_id\":\"$1\"}" | HOME="$RG9" MEMORY_KIT_MACHINE_LABEL=testbox bash "$KIT/scripts/memory-review-reminder.sh"; }
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

# ---------- config.example is the inventory, enforced in both directions ----------
# smoke checks that every knob a machine SETS is still read. This checks that every
# knob the CODE READS is declared, so the file cannot quietly fall behind. Names read
# from the environment that are not user knobs are listed here explicitly, so adding
# one is a deliberate act. Together these two checks do the job claude-session-kit
# gives its `CS_*` prefix, which is why the knobs here keep their existing names.
echo "config.example inventory:"
NOT_KNOBS="CLAUDE_MEMORY_KIT_INSTALL_GATED CLAUDE_CONFIG_DENYLIST CLAUDE_PROJECT_DIR"
undeclared=""
for k in $(grep -rhE '\$\{[A-Z][A-Z0-9_]*:-' "$KIT/scripts" "$KIT/hooks" "$KIT/core" \
             "$KIT/guardrail/pre-commit" "$KIT/install.sh" 2>/dev/null \
           | grep -v '^[[:space:]]*#' \
           | grep -oE '\$\{[A-Z][A-Z0-9_]*:-' | tr -d '${:-' | sort -u); do
  case " $NOT_KNOBS " in *" $k "*) continue ;; esac
  grep -q "^#$k=" "$KIT/config.example" || undeclared="$undeclared $k"
done
[ -z "$undeclared" ] && ok "every knob the code reads is declared in config.example" \
                     || fail "read but undeclared:$undeclared"
declared_internal=""
for k in $NOT_KNOBS; do
  grep -q "^#$k=" "$KIT/config.example" && declared_internal="$declared_internal $k"
done
[ -z "$declared_internal" ] && ok "internal names stay out of the inventory" \
                            || fail "internal name offered as a knob:$declared_internal"

# ---------- tunable knobs: env > file > default ----------
echo "core/lib.sh mk_conf:"
KH="$TMP/home-conf"; mkdir -p "$KH/.claude/memory-kit"
KC="$KH/.claude/memory-kit/config"
conf() { HOME="$KH" bash -c ". \"$KIT/core/lib.sh\"; $1"; }

[ "$(conf 'mk_conf MEMORY_KIT_MINER_MODEL sonnet')" = sonnet ] \
  && ok "no config file: the default applies" || fail "missing-file default"
printf 'MEMORY_KIT_MINER_MODEL=opus\n' > "$KC"
[ "$(conf 'mk_conf MEMORY_KIT_MINER_MODEL sonnet')" = opus ] \
  && ok "a file value beats the default" || fail "file value ignored"
[ "$(MEMORY_KIT_MINER_MODEL=haiku conf 'printf %s "${MEMORY_KIT_MINER_MODEL:-$(mk_conf MEMORY_KIT_MINER_MODEL sonnet)}"')" = haiku ] \
  && ok "an environment variable beats the file" || fail "precedence"
[ "$(conf 'mk_conf MEMORY_KIT_HEALTH_GRACE 3 int')" = 3 ] \
  && ok "a key absent from the file falls back" || fail "absent-key default"

printf 'MEMORY_KIT_HEALTH_GRACE=soon\n' > "$KC"
[ "$(conf 'mk_conf MEMORY_KIT_HEALTH_GRACE 3 int')" = 3 ] \
  && ok "a non-numeric value for an int knob falls back, silently" || fail "int validation"
printf 'MEMORY_KIT_MACHINE_LABEL=the laptop\n' > "$KC"
[ "$(conf 'mk_conf MEMORY_KIT_MACHINE_LABEL fallback')" = "the laptop" ] \
  && ok "a string knob keeps its spaces" || fail "string knob mangled"
printf '   MEMORY_KIT_MACHINE_LABEL   =   padded   \nMEMORY_KIT_MACHINE_LABEL=  trimmed  \n' > "$KC"
[ "$(conf 'mk_conf MEMORY_KIT_MACHINE_LABEL fallback')" = trimmed ] \
  && ok "surrounding spaces trimmed, last entry wins" || fail "trim/last-wins"
printf '# MEMORY_KIT_MACHINE_LABEL=commented\n\n' > "$KC"
[ "$(conf 'mk_conf MEMORY_KIT_MACHINE_LABEL fallback')" = fallback ] \
  && ok "comments and blank lines are not values" || fail "comment parsed as value"

# the file is data, never code: a command-shaped value must reach the caller as text
printf 'MEMORY_KIT_MINER_MODEL=$(touch %s/pwned)\n' "$TMP" > "$KC"
got=$(conf 'mk_conf MEMORY_KIT_MINER_MODEL sonnet')
[ -f "$TMP/pwned" ] && fail "a config value executed" || ok "a command-shaped value does not execute"
[ "$got" = "\$(touch $TMP/pwned)" ] && ok "it is returned as literal text" || fail "value mangled ($got)"
printf 'MEMORY_KIT_NO_MINER=1; rm -rf %s/victim\n' "$TMP" > "$KC"; mkdir -p "$TMP/victim"
conf 'mk_conf MEMORY_KIT_NO_MINER ""' >/dev/null 2>&1
[ -d "$TMP/victim" ] && ok "a trailing command in a value is inert" || fail "config line ran as code"

# a kill switch read from a file needs 0/no/off to mean off, not "present"
for v in 0 no off false ""; do
  mk_off=$(conf "mk_conf_off \"$v\" && echo off || echo on")
  [ "$mk_off" = off ] || fail "kill switch: '$v' should read as off"
done
ok "0, no, off, false and empty all read as off"
[ "$(conf 'mk_conf_off 1 && echo off || echo on')" = on ] \
  && ok "1 reads as on" || fail "kill switch: 1 should read as on"

# the knobs work through their real call sites, not just the loader
CFH="$TMP/home-conf-live"; mkdir -p "$CFH/.claude/memory-kit" "$CFH/.local/share/claude-feedback/health"
printf 'MEMORY_KIT_NO_MINER=yes\n' > "$CFH/.claude/memory-kit/config"
printf '%s\nstale\n' "$(date +%s)" > "$CFH/.local/share/claude-feedback/health/miner"
HOME="$CFH" PATH="/usr/bin:/bin" bash "$KIT/scripts/run-feedback-miner.sh" >/dev/null 2>&1
[ -f "$CFH/.local/share/claude-feedback/health/miner" ] \
  && fail "opt-out from the config file was not honoured" || ok "the miner opt-out works from the config file"
printf 'MEMORY_KIT_HEALTH_GRACE=90\n' > "$CFH/.claude/memory-kit/config"
printf '%s\nblocked for a month\n' "$(( $(date +%s) - 30 * 86400 ))" > "$CFH/.local/share/claude-feedback/health/miner"
out=$(echo '{"session_id":"c1"}' | HOME="$CFH" bash "$KIT/hooks/memory-kit-health.sh")
[ -z "$out" ] && ok "a raised grace period from the file holds the notice" || fail "grace from file ignored ($out)"

# ---------- renamed knobs: migrated in a file, reported in an environment ----------
echo "knob renames:"
RH2="$TMP/home-rename"; mkdir -p "$RH2/.claude/memory-kit"
RC="$RH2/.claude/memory-kit/config"
printf '#FEEDBACK_MINER_MODEL=sonnet\nMEMORY_MACHINE_LABEL=oldbox\nMEMORY_KIT_NO_MINER=1\n' > "$RC"
HOME="$RH2" CLAUDE_MEMORY_KIT_INSTALL_GATED=1 bash "$KIT/install.sh" >/dev/null 2>&1
grep -q '^MEMORY_KIT_MACHINE_LABEL=oldbox$' "$RC" \
  && ok "install rewrites a set legacy key, keeping its value" || fail "set legacy key not migrated"
grep -q '^#MEMORY_KIT_MINER_MODEL=sonnet$' "$RC" \
  && ok "install rewrites a commented legacy key too" || fail "commented legacy key not migrated"
grep -q '^MEMORY_KIT_NO_MINER=1$' "$RC" \
  && ok "an already-current key is left alone" || fail "current key touched"
grep -qE '^[^#]*FEEDBACK_MINER_MODEL|^[^#]*MEMORY_MACHINE_LABEL' "$RC" \
  && fail "an old key survived the migration" || ok "no old key survives"
[ "$(HOME="$RH2" bash -c ". \"$KIT/core/lib.sh\"; mk_conf MEMORY_KIT_MACHINE_LABEL fallback")" = oldbox ] \
  && ok "the migrated value is what the loader now reads" || fail "migrated value unreadable"

# a shell profile is the one place the installer cannot rewrite, so it is said out loud
out=$(echo '{"session_id":"lg1"}' | HOME="$RH2" MEMORY_MACHINE_LABEL=stale \
      bash "$KIT/hooks/memory-kit-health.sh")
echo "$out" | grep -q "MEMORY_MACHINE_LABEL is still set" \
  && ok "a legacy environment variable is reported by name" || fail "legacy env not reported ($out)"
echo "$out" | grep -q "MEMORY_KIT_MACHINE_LABEL" \
  && ok "the message names the replacement" || fail "no replacement named"
out=$(echo '{"session_id":"lg2"}' | HOME="$RH2" bash "$KIT/hooks/memory-kit-health.sh")
[ -z "$out" ] && ok "nothing is said when no legacy name is set" || fail "legacy noise ($out)"

# ---------- feature health: a blocked feature leaves a reason ----------
echo "core/lib.sh health records:"
HH="$TMP/home-health"; mkdir -p "$HH"
HF="$HH/.local/share/claude-feedback/health/miner"
libsh() { HOME="$HH" bash -c ". \"$KIT/core/lib.sh\"; $1"; }
backdate() { printf '%s\n%s\n' "$(( $(date +%s) - $1 * 86400 ))" "$2" > "$HF"; }

libsh 'mk_health_record miner "no claude CLI"'
[ "$(libsh 'mk_health_blocked miner')" = "0 no claude CLI" ] \
  && ok "a block is recorded with its reason" || fail "record/read"
backdate 5 "no claude CLI"; libsh 'mk_health_record miner "no claude CLI"'
[ "$(libsh 'mk_health_blocked miner')" = "5 no claude CLI" ] \
  && ok "re-recording the same reason keeps blocked-since" || fail "blocked-since reset"
libsh 'mk_health_record miner "a different fault"'
[ "$(libsh 'mk_health_blocked miner')" = "0 a different fault" ] \
  && ok "a new reason restarts the clock" || fail "new reason kept old date"
libsh 'mk_health_clear miner'
libsh 'mk_health_blocked miner' >/dev/null 2>&1 && fail "clear left a record" || ok "clearing removes the record"

# git failures are classified so each class can name a different thing to check
while IFS='|' read -r txt want; do
  [ -n "$txt" ] || continue
  got=$(libsh "mk_git_reason \"$txt\"")
  [ "$got" = "$want" ] && ok "classified as $want" || fail "classifier: $txt gave $got, want $want"
done <<'CASES'
fatal: unable to access repo: Could not resolve host: github.com|offline
fatal: Authentication failed for the remote|credentials
fatal: Not possible to fast-forward, aborting.|diverged
error: your local changes would be overwritten|other
CASES

echo "hooks/memory-kit-health.sh:"
health() { echo "{\"session_id\":\"$1\"}" | HOME="$HH" MEMORY_KIT_HEALTH_GRACE="${2:-3}" \
  bash "$KIT/hooks/memory-kit-health.sh"; }
[ -z "$(health s1)" ] && ok "healthy machine: silent" || fail "noise with nothing recorded"
libsh 'mk_health_record miner "the feedback miner cannot run: no claude CLI"'
[ -z "$(health s1)" ] && ok "a fresh block stays inside the grace period" || fail "grace period ignored"
backdate 5 "the feedback miner cannot run: no claude CLI"
out=$(health s2)
echo "$out" | jq -e '.systemMessage' >/dev/null 2>&1 && echo "$out" | grep -q "for 5 days" \
  && ok "a persistent block notices, with its age" || fail "no notice ($out)"
[ -z "$(health s2)" ] && ok "one notice per session per day" || fail "repeat notice same session"
[ -n "$(health s3)" ] && ok "a different session still hears it" || fail "other session silenced"
libsh 'mk_health_clear miner'
[ -z "$(health s4)" ] && ok "recovery is silent, no manual dismissal" || fail "notice survived the fix"

echo "run-feedback-miner.sh + memory-review-reminder.sh (blocked paths):"
NH="$TMP/home-noclaude"; mkdir -p "$NH/.claude"
HOME="$NH" PATH="/usr/bin:/bin" bash "$KIT/scripts/run-feedback-miner.sh" >/dev/null 2>&1
r=$(sed -n 2p "$NH/.local/share/claude-feedback/health/miner" 2>/dev/null)
case "$r" in *"no claude CLI"*) ok "a missing claude CLI is recorded, not swallowed";;
             *) fail "miner left no reason ($r)";; esac
HOME="$NH" PATH="/usr/bin:/bin" MEMORY_KIT_NO_MINER=1 bash "$KIT/scripts/run-feedback-miner.sh" >/dev/null 2>&1
[ -f "$NH/.local/share/claude-feedback/health/miner" ] \
  && fail "opt-out left a record behind" || ok "opting out clears the record and stays quiet"

CH="$TMP/home-clear"; mkdir -p "$CH/.claude/projects" "$CH/.local/share/claude-feedback/health"
printf '%s\nstale block\n' "$(date +%s)" > "$CH/.local/share/claude-feedback/health/miner"
HOME="$CH" PATH="$SB:$PATH" bash "$KIT/scripts/run-feedback-miner.sh" >/dev/null 2>&1
[ -f "$CH/.local/share/claude-feedback/health/miner" ] \
  && fail "a working run left a stale block" || ok "a working run clears the record"

# git that cannot read the repo must not be reported as "never reviewed"
GH2="$TMP/home-nogit"; mkdir -p "$GH2/.claude"
git init -q "$GH2/.claude/memory"
SHIM="$TMP/gitshim"; mkdir -p "$SHIM"; printf '#!/bin/sh\nexit 1\n' > "$SHIM/git"; chmod +x "$SHIM/git"
out=$(echo '{"session_id":"g1"}' | HOME="$GH2" PATH="$SHIM:$PATH" \
  bash "$KIT/scripts/memory-review-reminder.sh")
echo "$out" | grep -q "status unknown" && ok "unreadable history is reported as unknown" || fail "reminder said ($out)"
echo "$out" | grep -q "never recorded" && fail "still claims never-recorded" || ok "no invented never-recorded claim"
[ -f "$GH2/.local/share/claude-feedback/health/review" ] \
  && ok "unreadable history is recorded for the health notice" || fail "no health record from the reminder"

# ---------- installer ----------
# fixtures set CLAUDE_MEMORY_KIT_INSTALL_GATED so the installer's own test gate doesn't
# recurse back into this suite
echo "install.sh:"
IH="$TMP/home3"; mkdir -p "$IH/.claude/memory"
# retiring the seeded conventions: an edited copy is the user's file and stays, an
# untouched one is kit property and goes, because the rules are a write-time check now
printf 'customized\n' > "$IH/.claude/memory/feedback_memory_conventions.md"
cp "$KIT/guidance/retired-seeds/feedback_memory_generality.md" "$IH/.claude/memory/"
HOME="$IH" CLAUDE_MEMORY_KIT_INSTALL_GATED=1 bash "$KIT/install.sh" >/dev/null 2>&1
HOME="$IH" CLAUDE_MEMORY_KIT_INSTALL_GATED=1 bash "$KIT/install.sh" >/dev/null 2>&1
[ "$(cat "$IH/.claude/memory/feedback_memory_conventions.md")" = "customized" ] \
  && ok "an edited seed file is left alone" || fail "edited seed clobbered"
[ -f "$IH/.claude/memory/feedback_memory_generality.md" ] \
  && fail "an unmodified seed file was left behind" || ok "an unmodified seed file is retired"
# a file git tracks is never deleted, even when it is byte-identical to the kit's copy:
# staging a deletion in the user's history is their commit to make, not the installer's
TH="$TMP/home-tracked"; mkdir -p "$TH/.claude/memory"
git init -q "$TH/.claude/memory"
git -C "$TH/.claude/memory" config user.email t@t
git -C "$TH/.claude/memory" config user.name t
cp "$KIT/guidance/retired-seeds/feedback_memory_generality.md" "$TH/.claude/memory/"
git -C "$TH/.claude/memory" add feedback_memory_generality.md
git -C "$TH/.claude/memory" commit -qm "user tracks the seed file"
out=$(HOME="$TH" CLAUDE_MEMORY_KIT_INSTALL_GATED=1 bash "$KIT/install.sh" 2>&1)
[ -f "$TH/.claude/memory/feedback_memory_generality.md" ] \
  && ok "a tracked seed file is not deleted" || fail "installer deleted tracked content"
printf '%s' "$out" | grep -q "your repo tracks it" \
  && ok "and it says why, naming the command to do it yourself" || fail "silent about the tracked file"
[ -z "$(git -C "$TH/.claude/memory" status --porcelain)" ] \
  && ok "the user's repo is left with nothing to commit" || fail "installer dirtied the memory repo"
# the untracked case still retires, so the cleanup is not lost
UT="$TMP/home-untracked"; mkdir -p "$UT/.claude/memory"
cp "$KIT/guidance/retired-seeds/feedback_memory_generality.md" "$UT/.claude/memory/"
HOME="$UT" CLAUDE_MEMORY_KIT_INSTALL_GATED=1 bash "$KIT/install.sh" >/dev/null 2>&1
[ ! -f "$UT/.claude/memory/feedback_memory_generality.md" ] \
  && ok "an untracked identical copy is still retired" || fail "untracked copy left behind"

[ -f "$IH/.claude/memory-kit/guidance/memory-authoring.md" ] \
  && ok "the guidance the hook points at is deployed" || fail "guidance missing from the tree"
[ -f "$IH/.claude/skills/save-memory/SKILL.md" ] \
  && ok "the authoring skill is installed" || fail "save-memory skill missing"
n=$(jq '[.hooks[][].hooks[].command] | length' "$IH/.claude/settings.json")
n2=$(jq '[.hooks[][].hooks[].command] | unique | length' "$IH/.claude/settings.json")
[ "$n" = "$n2" ] && ok "hooks deduped across re-runs ($n entries)" || fail "hook dupes ($n vs $n2)"
[ -x "$IH/.claude/memory-kit/scripts/run-feedback-miner.sh" ] && [ -r "$IH/.claude/memory-kit/core/lib.sh" ] \
  && ok "deploys one tree: scripts + core lib together" || fail "tree deploy incomplete"

# knobs: seeded once, never overwritten, and the example refreshed every install
[ -f "$IH/.claude/memory-kit/config" ] && [ -f "$IH/.claude/memory-kit/config.example" ] \
  && ok "install seeds a config from the example" || fail "config not seeded"
printf 'MEMORY_KIT_HEALTH_GRACE=42\n' > "$IH/.claude/memory-kit/config"
printf 'stale example\n' > "$IH/.claude/memory-kit/config.example"
HOME="$IH" CLAUDE_MEMORY_KIT_INSTALL_GATED=1 bash "$KIT/install.sh" >/dev/null 2>&1
[ "$(cat "$IH/.claude/memory-kit/config")" = "MEMORY_KIT_HEALTH_GRACE=42" ] \
  && ok "upgrade keeps an edited config" || fail "config overwritten on upgrade"
grep -q "^#MEMORY_KIT_NO_MINER" "$IH/.claude/memory-kit/config.example" \
  && ok "upgrade refreshes the example so new knobs appear" || fail "example not refreshed"
# migration: a pre-tree layout (script copies + old-path hooks) converges to the tree
MH2="$TMP/home8"; mkdir -p "$MH2/.claude/scripts"
printf '#!/bin/sh\n' > "$MH2/.claude/scripts/feedback-proposals-ping.sh"
printf '#!/bin/sh\n' > "$MH2/.claude/scripts/unrelated-tool.sh"
printf '{"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"\\"$HOME/.claude/scripts/feedback-proposals-ping.sh\\" 2>/dev/null || true"},{"type":"command","command":"\\"$HOME/.claude/scripts/unrelated-tool.sh\\" || true"}]}]}}\n' > "$MH2/.claude/settings.json"
HOME="$MH2" CLAUDE_MEMORY_KIT_INSTALL_GATED=1 bash "$KIT/install.sh" >/dev/null 2>&1
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
cp -R "$KIT/guidance" "$GK/guidance"; cp -R "$KIT/skills" "$GK/skills"; cp -R "$KIT/guardrail" "$GK/guardrail"
cp "$KIT/install.sh" "$KIT/settings.snippet.json" "$GK/"
printf '#!/bin/sh\nexit 1\n' > "$GK/tests/run.sh"
GH2="$TMP/home10"; mkdir -p "$GH2/.claude"
# clear the guard explicitly: when THIS suite is itself run by an installer's gate,
# the fixture must not inherit the skip and let the sabotaged kit through
HOME="$GH2" CLAUDE_MEMORY_KIT_INSTALL_GATED= bash "$GK/install.sh" >/dev/null 2>&1
check "gate: failing tests refuse to deploy" 1 $?
[ ! -d "$GH2/.claude/memory-kit" ] && ok "gate: nothing was deployed" || fail "gate deployed anyway"

# ---------- uninstall: symmetric with what install wires ----------
# Everything the installer writes outside its own tree has to come back out, and the
# dangerous one is core.hooksPath: deleting the tree while that still points into it
# leaves git finding no hook and running nothing, so the commit guard stops silently
# while the repo still looks configured.
echo "install.sh --uninstall:"
UH2="$TMP/home-uninstall"; mkdir -p "$UH2/.claude/memory"
git init -q "$UH2/.claude/memory"
git -C "$UH2/.claude/memory" config user.email t@t
git -C "$UH2/.claude/memory" config user.name t
printf -- '---\nname: feedback_mine\ndescription: keep me\nmetadata:\n  type: feedback\n---\n\nRule.\n\n**Why:** mine.\n' \
  > "$UH2/.claude/memory/feedback_mine.md"
printf '# index\n' > "$UH2/.claude/memory/MEMORY.md"
git -C "$UH2/.claude/memory" add -A
git -C "$UH2/.claude/memory" commit -qm seed
mkdir -p "$UH2/.local/share/claude-feedback"
printf '## Rejected\n### P-001 refused\n' > "$UH2/.local/share/claude-feedback/proposals.md"
printf 'a cached copy of messages\n' > "$UH2/.local/share/claude-feedback/digest-latest.txt"
# a hook belonging to something else, sharing one of our filenames from another path
jq -n '{hooks:{SessionStart:[{hooks:[{type:"command",command:"$HOME/other-tool/hooks/memory-kit-health.sh"}]}]}}' \
  > "$UH2/.claude/settings.json"

HOME="$UH2" CLAUDE_MEMORY_KIT_INSTALL_GATED=1 bash "$KIT/install.sh" >/dev/null 2>&1
[ -d "$UH2/.claude/memory-kit" ] && ok "install: tree deployed for the uninstall fixture" || fail "fixture install failed"
[ "$(git -C "$UH2/.claude/memory" config --get core.hooksPath)" = "$UH2/.claude/memory-kit/guardrail" ] \
  && ok "install: guardrail wired via core.hooksPath" || fail "hooksPath not set"
git -C "$UH2/.claude/memory" ls-files -v MEMORY.md | grep -q '^S' \
  && ok "install: MEMORY.md marked skip-worktree" || fail "skip-worktree not set"
mine=$(jq '[.hooks[]?[]?.hooks[]?.command | select(contains("memory-kit/"))] | length' "$UH2/.claude/settings.json")
[ "$mine" -ge 8 ] && ok "install: our hooks wired ($mine entries)" || fail "hooks not wired ($mine)"
grep -q "other-tool" "$UH2/.claude/settings.json" \
  && ok "install: another tool's same-named hook left in place" || fail "foreign hook lost on install"

HOME="$UH2" bash "$KIT/install.sh" --uninstall >/dev/null 2>&1
left=$(jq '[.hooks[]?[]?.hooks[]?.command | select(contains("memory-kit/"))] | length' "$UH2/.claude/settings.json")
[ "$left" = 0 ] && ok "uninstall: every hook of ours is gone" || fail "hooks left behind ($left)"
grep -q "other-tool" "$UH2/.claude/settings.json" \
  && ok "uninstall: the foreign hook with our filename survived" || fail "deleted another tool's hook"
[ -z "$(git -C "$UH2/.claude/memory" config --get core.hooksPath || true)" ] \
  && ok "uninstall: core.hooksPath unset, so no silent guard" || fail "hooksPath left pointing at a deleted tree"
git -C "$UH2/.claude/memory" ls-files -v MEMORY.md | grep -q '^S' \
  && fail "MEMORY.md still hidden from git" || ok "uninstall: skip-worktree cleared"
[ ! -d "$UH2/.claude/memory-kit" ] && ok "uninstall: the tree is gone" || fail "tree left behind"
[ ! -d "$UH2/.claude/skills/save-memory" ] && ok "uninstall: the kit's skills are gone" || fail "skills left behind"
[ -f "$UH2/.claude/memory/feedback_mine.md" ] \
  && ok "uninstall: memory files are untouched" || fail "user memory deleted"
[ -f "$UH2/.local/share/claude-feedback/proposals.md" ] \
  && ok "uninstall: the tracker is kept by default" || fail "tracker deleted without asking"
HOME="$UH2" bash "$KIT/install.sh" --uninstall >/dev/null 2>&1
check "uninstall twice is not an error" 0 $?

# the two purge flags, which must say what they do rather than doing it quietly
out=$(HOME="$UH2" bash "$KIT/install.sh" --uninstall --purge-cache 2>&1)
printf '%s' "$out" | grep -q "purge-cache" && ok "--purge-cache announces itself" || fail "purge-cache silent"
[ ! -f "$UH2/.local/share/claude-feedback/digest-latest.txt" ] \
  && ok "--purge-cache drops the cached messages" || fail "cache survived"
[ -f "$UH2/.local/share/claude-feedback/proposals.md" ] \
  && ok "--purge-cache keeps what you accepted and rejected" || fail "purge-cache took the history"
out=$(HOME="$UH2" bash "$KIT/install.sh" --uninstall --purge-tracker 2>&1)
printf '%s' "$out" | grep -q "re-propose" && ok "--purge-tracker warns what is lost" || fail "purge-tracker unwarned"
[ ! -d "$UH2/.local/share/claude-feedback" ] && ok "--purge-tracker removes the tracker" || fail "tracker survived"

# a hooksPath somebody else set is not ours to unset
UH3="$TMP/home-foreign-hookspath"; mkdir -p "$UH3/.claude/memory"
git init -q "$UH3/.claude/memory"
git -C "$UH3/.claude/memory" config core.hooksPath /somewhere/else
HOME="$UH3" CLAUDE_MEMORY_KIT_INSTALL_GATED=1 bash "$KIT/install.sh" >/dev/null 2>&1
git -C "$UH3/.claude/memory" config core.hooksPath /somewhere/else   # install re-points it; put it back
out=$(HOME="$UH3" bash "$KIT/install.sh" --uninstall 2>&1)
[ "$(git -C "$UH3/.claude/memory" config --get core.hooksPath)" = "/somewhere/else" ] \
  && ok "a foreign core.hooksPath is reported, not unset" || fail "unset someone else's hooksPath"

# --dry-run must change nothing at all
DH="$TMP/home-dry"; mkdir -p "$DH/.claude"
HOME="$DH" bash "$KIT/install.sh" --dry-run >/dev/null 2>&1
[ ! -d "$DH/.claude/memory-kit" ] && [ ! -f "$DH/.claude/settings.json" ] \
  && ok "--dry-run writes nothing" || fail "dry run had side effects"

# a settings.json that is already broken stops the run before anything is installed
BH="$TMP/home-broken"; mkdir -p "$BH/.claude"
printf 'not json at all\n' > "$BH/.claude/settings.json"
HOME="$BH" CLAUDE_MEMORY_KIT_INSTALL_GATED=1 bash "$KIT/install.sh" >/dev/null 2>&1
check "a broken settings.json refuses the install" 1 $?
[ ! -d "$BH/.claude/memory-kit" ] && ok "and nothing was deployed first" || fail "deployed despite bad settings"
[ "$(cat "$BH/.claude/settings.json")" = "not json at all" ] \
  && ok "and the file was left exactly as it was" || fail "touched a file it could not parse"

# ---------- settings.json shapes that parse but are not what we expect ----------
# Unparseable was already covered. This is the other half: a file that IS valid JSON but
# holds a shape the merge cannot use, and a file whose odd corners must survive untouched.
# Ported from claude-session-kit, which had the survive case and we did not.
echo "settings.json shapes:"
SHAPE_DIR=""   # set by shape_case; the result lines and the path cannot share stdout
shape_case() { # shape_case <desc> <json> <expect-rc> <expect-our-hooks>
  local d="$1" json="$2" want_rc="$3" want_ours="$4" rc ours
  SHAPE_DIR=$(mktemp -d); mkdir -p "$SHAPE_DIR/.claude"
  printf '%s' "$json" > "$SHAPE_DIR/.claude/settings.json"
  HOME="$SHAPE_DIR" CLAUDE_MEMORY_KIT_INSTALL_GATED=1 bash "$KIT/install.sh" >/dev/null 2>&1; rc=$?
  ours=$(jq '[.hooks[]?[]?.hooks[]?.command | select(contains("memory-kit/"))] | length' \
         "$SHAPE_DIR/.claude/settings.json" 2>/dev/null || echo -1)
  if [ "$rc" = "$want_rc" ] && [ "$ours" = "$want_ours" ]; then ok "$d"
  else fail "$d (rc=$rc want $want_rc, ourhooks=$ours want $want_ours)"; fi
}
shape_case "hooks as a number: refuses, wires nothing" '{"hooks":42}' 1 0; h="$SHAPE_DIR"
[ "$(cat "$h/.claude/settings.json")" = '{"hooks":42}' ] \
  && ok "and leaves the file byte-identical" || fail "rewrote a file it could not merge"
[ ! -d "$h/.claude/memory-kit" ] \
  && ok "and refuses before deploying anything" || fail "deployed despite an unusable settings.json"
rm -rf "$h"
shape_case "an event that is not an array: refuses" '{"hooks":{"SessionStart":"nope"}}' 1 0; h="$SHAPE_DIR"
rm -rf "$h"
# the survive case: odd corners inside a well-shaped file are none of our business
shape_case "a malformed group survives, and our hooks still wire" \
      '{"hooks":{"SessionStart":[{"hooks":"nope"}]},"other":"keep me"}' 0 9; h="$SHAPE_DIR"
jq -e '.other == "keep me"' "$h/.claude/settings.json" >/dev/null \
  && ok "an unrelated top-level key survives" || fail "dropped a key that was not ours"
jq -e '[.hooks.SessionStart[] | select(.hooks == "nope")] | length == 1' "$h/.claude/settings.json" >/dev/null \
  && ok "the malformed group is preserved, not tidied away" || fail "rewrote someone else's malformed entry"
rm -rf "$h"

echo
echo "passed $PASS, failed $FAIL"
[ "$FAIL" = 0 ]
