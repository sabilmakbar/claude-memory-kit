#!/usr/bin/env bash
# claude-memory-kit test suite. Self-contained: everything runs against throwaway
# temp dirs / fake $HOMEs; nothing touches the real ~/.claude or any real repo.
#   tests/run.sh          # run all, exit non-zero on first failure summary
set -u

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
echo "$out" | grep -q "feedback_x.md, memory-mounts/-m/project_y.md" && ok "change: notice lists both files" || fail "notice ($out)"
[ -z "$(ping s1)" ] && ok "same change: announced once" || fail "dedup"
sleep 1; touch "$DH/.claude/memory/feedback_x.md"
[ -z "$(ping s1 3600)" ] && ok "inside throttle: silent" || fail "throttle"
out=$(ping s1)  # throttle passed (0): pending change delivered late, not lost
echo "$out" | grep -q "feedback_x.md" && ok "throttled change delivered after window" || fail "late delivery"
sleep 1; printf '# regen\n' > "$DH/.claude/memory/MEMORY.md"
[ -z "$(ping s1)" ] && ok "MEMORY.md regen alone: silent" || fail "MEMORY.md excluded"
[ -z "$(ping '../../../tmp/evil')" ] && [ ! -e "$DH/tmp" ] \
  && ok "session_id traversal sanitized" || fail "traversal"

# ---------- installer ----------
echo "install.sh:"
IH="$TMP/home3"; mkdir -p "$IH/.claude/memory"
printf 'customized\n' > "$IH/.claude/memory/feedback_memory_conventions.md"
HOME="$IH" bash "$KIT/install.sh" >/dev/null 2>&1
HOME="$IH" bash "$KIT/install.sh" >/dev/null 2>&1
[ "$(cat "$IH/.claude/memory/feedback_memory_conventions.md")" = "customized" ] \
  && ok "re-run keeps customized seed file" || fail "seed clobbered"
n=$(jq '[.hooks[][].hooks[].command] | length' "$IH/.claude/settings.json")
n2=$(jq '[.hooks[][].hooks[].command] | unique | length' "$IH/.claude/settings.json")
[ "$n" = "$n2" ] && ok "hooks deduped across re-runs ($n entries)" || fail "hook dupes ($n vs $n2)"

echo
echo "passed $PASS, failed $FAIL"
[ "$FAIL" = 0 ]
