# Design: guarding what gets written

> **This is a decision record, not a user guide.** It is dense on purpose: it exists so that
> future changes know what they would be overturning. For how the kit behaves day to day, read
> [FLOWS.md](FLOWS.md). For setup, the README.

    Status:            Implemented
    Last revised:      2026-08-12
    Verified against:  Claude Code 2.1.222
    Supersedes:        docs/DESIGN.md, split by feature 2026-08-12

Two mechanisms, both about stopping a bad write rather than reporting one afterwards, and one
open question about which repo the commit check belongs in. The authoring rules it enforces are in
[DESIGN-memory.md](DESIGN-memory.md), decisions D4 and D5.

## D1. The guardrail is generic patterns plus a local denylist

The built-in patterns catch any home path, any email, and a mount section, so the hook itself
carries no identifying information and can be public. Employer names and other private terms come
from an untracked `denylist.local` or an environment variable.

It runs as the memory repo's pre-commit hook and enforces both leak-safety and the file
conventions. **Commit time is the last moment before content becomes irreversible history**,
which is why the check sits there rather than at push time.

The same hook also guards this repo's own checkout (`git config core.hooksPath guardrail`). One
more rule rides along with it: no em-dashes on lines added to `README.md` or `docs/*.md`. That
rule is **not** conditional on which repo it is in, and the hook has no notion of its own checkout
at all: it fires wherever such a file is staged, including in a memory repo. Code, tests and
memory files are outside the scope on purpose: only reader-facing prose is checked, which leaves
the rule with no exemptions to remember and so nothing to drift.

`CLAUDE_CONFIG_DENYLIST` stays outside the kit's naming convention. The guardrail is wired into
other repos on its own, so its interface is not the kit's to rename.

## D2. Edit-over-Write

A `PreToolUse` hook denies the `Write` tool on any existing file, so every change lands as a
reviewable diff.

**Memory used to tell the agent to prefer Edit. Memory is advisory, and it was eventually
ignored.** The hook is not advisory.

## D3. Which repo the frontmatter lint belongs in, and why it does not know yet

**Decided 2026-08-12. Recorded ahead of the code, which is a stopgap.**

The lint treats any `.md` at the repo root, or under `memory/`, as a memory file, then exempts a
list of known non-memory names. That scope is **correct for the user's memory repo**, where memory
files really do sit at the root beside `README.md` and `MEMORY.md`.

It is wrong for this repo, which the same hook also guards. **No memory file has ever lived here**,
so every root-level document is a false positive waiting for someone to add its name. Four of the
original five exemptions were already dead when this was found: the path filter cannot reach
anything under `docs/`, and this repo has no root `MEMORY.md` or `CLAUDE.md`. Only `README` was
doing any work. Adding `CONTRIBUTING` made six exemptions where three would do, and adding
`CHANGELOG` hours later made seven.

**The list is also duplicated, and has already drifted once.** It exists twice, in two syntaxes:
a regex alternation in `guardrail/pre-commit`, and a shell `case` pattern in
`scripts/refresh-memory-index.sh`, where a root-level document not on the list is reported as an
unindexed memory file. The `CONTRIBUTING` exemption patched only the first copy, so for several
hours one half of the kit exempted that file and the other half complained about it. The next
exemption had to fix both at once to catch up. Two copies of a list that must be remembered is
strictly worse than one, and it is the second failure of this stopgap in a single day.

**The fix is to gate the lint on being in the memory repo**, not to keep widening the list.
`install.sh` wires the hook to exactly one place, so `git rev-parse --show-toplevel` against
`$HOME/.claude/memory` is a fact rather than an inference. The three exemptions that survive are
then correct rather than stale, because `MEMORY.md`, `CLAUDE.md` and `README.md` are genuinely the
memory repo's own non-memory root files.

That also fixes a case nobody had raised. The README documents wiring this hook into any repo for
the leak checks alone; today such a repo gets memory frontmatter linting too, which is the same
overreach in a third place.

**A prefix test was considered and rejected as the primary fix.** Checking only files that already
start with `user_`, `feedback_` or `project_` cannot catch the failure the rule exists to catch, a
memory file named `notes.md`, and the type-prefixed filename is an enforced rule
([DESIGN-memory.md](DESIGN-memory.md) D5). It is worth adding as a second condition, not as a
replacement.

**Not done.** The exemption list carries `CONTRIBUTING` for now, which unblocks work and leaves the
overreach in place. Two things are still open and both are behaviour changes to a hook users
install, so each wants its own tests:

1. **The location gate above.** Known limitation to accept rather than engineer around: it
   silently does nothing if someone clones their memory repo somewhere other than
   `~/.claude/memory`. That is the only location the installer wires.
2. **The coverage gap.** This hook enforces three rules where the write-time hook enforces seven.
   The gap includes `no-evidence-when-synced`, which matters most, because
   [DESIGN-memory.md](DESIGN-memory.md) D3 records that the evidence section was removed
   structurally rather than policed. A memory file that never passed through the Write or Edit
   tools, meaning hand-edited, copied in, or pulled from another machine, can carry an Evidence
   section into the tier that syncs and this hook will not notice. It is the last check before
   content becomes permanent history, and it is the one not looking.

**Both items are done.** Three things about item 1 differ from what was written above, and item 2
was closed by handing the rules over rather than copying them.

The limitation this record accepted has gone away rather than been accepted. It assumed
`~/.claude/memory` was the only location the installer wires, so a store cloned elsewhere would
silently escape the lint. `mk_memory_dir` reads `autoMemoryDirectory` now, so wherever the install
named the store is where the lint runs. What remains is narrower: a store the kit was never
pointed at is still outside the gate, which is the correct answer rather than a gap.

The exemption list stayed at seven names instead of shrinking to three. It became one definition
with four callers in `core/lib.sh`, which is what cures the drift this record was written about.
Shrinking it is a separate behaviour change that would newly block a store keeping its own
`CHANGELOG.md`, and no evidence says anyone wants that. The four extra names are defensive now
rather than load-bearing, and the count is no longer the thing that can go wrong.

Comparing the two paths raw was wrong, and a test caught it. `git rev-parse --show-toplevel`
reports the physical path while the setting holds whatever was written, so a store reached through
a symlink compared unequal and skipped the lint in silence. On macOS `/var` is such a link, which
made every temp-directory fixture hit it before a user could. The store is resolved with `pwd -P`
before comparing.

**Item 2: the commit hook runs all seven rules, from the write-time hook's implementation.** It
builds the same input a `PreToolUse` event delivers, pipes each staged file in, and reads the deny
reason back out. The three hand-written rules are gone rather than joined by four more, so the two
halves cannot disagree about what a valid memory file is.

Content comes from `git show ":$f"`, never the working tree, or the lint judges something the
commit does not contain.

The `file_path` is built from the **unresolved** store path, unlike the location gate above, which
resolves both sides. The write-time hook scopes its synced-tier rule with its own
`case "$fp" in "$(mk_memory_dir)"/*`, so a path resolved through `pwd -P` would fall through that
filter and the Evidence rule would never fire. The two comparisons want opposite treatment, which
is worth stating because it reads like an inconsistency.

The second argument for this check only became visible while making the change. Commit time is the
backstop for a file that never passed through Write or Edit, such as a pull from another machine,
a hand edit, or the harness's own memory writer. It is also **the only place a whole file is ever
seen**: D2's edit-over-write hook turns every change to an existing file into an `Edit`, and three
of the seven rules run only on a `Write`, because absence cannot be judged from a fragment. Before
this change `type-required` and `why-required-for-feedback` had no reliable check anywhere once a
file existed.

A skip is announced in both new branches, naming whether the store could not be identified or the
write-time hook could not be found, since the rules now live in a file the commit hook has to
locate.

## What would reopen this

- **D1's placement, if git gained a reliable pre-push equivalent that ran before the commit was
  reachable.** Commit time was chosen as the last irreversible moment, not as the most convenient
  one.
- **D1's scope, if the em-dash rule ever needs an exemption.** Its entire value is that it has
  none, so the first exemption is the thing that would make it drift, and that is the moment to
  reconsider whether it belongs in a hook at all.
- **D3, once either open item lands.** The location gate and the coverage gap are both recorded as
  not done. When one is implemented, this record stops describing a stopgap and starts describing
  the mechanism, and the exemption list should shrink from six to three in the same change.
- **D2, if a legitimate workflow needs whole-file replacement.** Denying `Write` outright assumes
  no such case exists. One would not necessarily overturn the decision, but it would need an
  answer better than an exemption list.

## Failure posture

Both mechanisms fail closed, which is the opposite of everything else in this kit.

That was once only partly true. The frontmatter lint failed **open** on the case D3 describes: a
memory file carrying an Evidence section into the tier that syncs passed the commit hook, because
that hook checked three of the seven rules. It now runs all seven, so the posture is uniform
again.

The one remaining open case is deliberate and announced: if the store cannot be identified, or the
write-time hook cannot be found, the frontmatter lint is skipped and says so. Blocking every
commit in every repo because a path could not be resolved would be worse, and the leak checks,
which are the ones a missed run makes permanent, still fail closed.

Elsewhere a broken feature goes quiet and records why, because a noisy hook trains you to ignore
it. Here a check that cannot run must block, because the cost of a missed leak is permanent: once
a commit exists, the content is in history whether it is pushed or not. A guardrail that failed
open would be worse than no guardrail, since it would carry the reassurance without the check.

The private denylist lives outside git deliberately, so the file naming your employer never
becomes the leak it exists to prevent.
