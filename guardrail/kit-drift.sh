#!/usr/bin/env bash
# guardrail/kit-drift.sh — says that the DEPLOYED kit tree no longer matches this checkout,
# at the moment the gap opens: a pull, a branch switch, a rebase.
#
# Nothing wires this beyond the core.hooksPath install.sh already sets on a checkout for the
# commit guardrail, so post-merge, post-checkout and post-rewrite arrive with git pull the
# same way pre-commit does.
#
# WHY IT LIVES IN THE CHECKOUT. The deployed tree at ~/.claude/memory-kit is a file copy with
# no .git and records no path back to its source, so it cannot tell whether it is current. The
# checkout can: the destination is a convention, so the checkout looks FORWARD to the deploy
# instead of the deploy looking back. That removes the need for a stored source path, which
# would rot the first time the checkout moved.
#
# WHY IT COMPARES CONTENT, NOT THE VERSION LABEL. Every commit changes `git describe`, so a
# label comparison fires through all of normal development and gets ignored. What matters is
# whether the files install.sh actually deploys have changed since the deployed commit; a pull
# touching only docs or the README is silent, which is the point.
#
# Committed states only. Uncommitted edits in the working tree are work in progress, not a
# stale deploy, and warning about them would fire on every save.
set -u

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
DEST="$HOME/.claude/memory-kit"

# Anything unknowable exits 0 and says nothing. A git hook that breaks a pull over an
# advisory notice is worse than the drift it reports.
[ -n "$ROOT" ] || exit 0
[ -r "$DEST/.kit-version" ] || exit 0          # not installed, or installed from elsewhere

dep="$(cat "$DEST/.kit-version" 2>/dev/null)" || exit 0
dep="${dep%-dirty}"                            # deployed from a dirty tree; the commit still anchors it
# `unknown` (installed from an archive) and a describe string from some other clone both fail
# here, which is the correct silence: there is no commit in THIS repo to compare against.
rev="$(git -C "$ROOT" rev-parse --verify --quiet "$dep^{commit}")" || exit 0
[ -n "$rev" ] || exit 0

# Must stay in step with what install.sh copies into ~/.claude/memory-kit. tests/run.sh
# installs into a sandbox and asserts every deployed file is covered by this list, so adding
# a file to the installer without adding it here fails the suite rather than going unwatched.
PATHS=(core scripts hooks tests guidance skills guardrail/pre-commit guardrail/denylist.local.example install.sh settings.snippet.json config.example)

git -C "$ROOT" diff --quiet "$rev" HEAD -- "${PATHS[@]}" 2>/dev/null && exit 0

now="$(git -C "$ROOT" describe --tags --always 2>/dev/null)"
# Deliberately no direction claim. The diff is symmetric, and switching to an older branch
# makes the DEPLOY the newer side; naming a direction would be wrong half the time. Either
# way the fix is the same, so the labels are shown and the reader can see which is which.
{ printf '\n! the installed memory-kit does not match this checkout\n'
  printf '  deployed %s, checkout now %s. Files that differ:\n' "$dep" "${now:-HEAD}"
  git -C "$ROOT" diff --name-only "$rev" HEAD -- "${PATHS[@]}" 2>/dev/null | sed 's/^/    /'
  printf '  re-run:  bash install.sh\n\n'
} >&2
exit 0
