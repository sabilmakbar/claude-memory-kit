# Design: the memory files, and the repo they live in

> **This is a decision record, not a user guide.** It is dense on purpose: it exists so that
> future changes know what they would be overturning. For how the kit behaves day to day, read
> [FLOWS.md](FLOWS.md). For setup, the README.

    Status:            Implemented, except where a paragraph is marked NOT BUILT. Two things
                       are still specified only: the report-only heal in D7, and the notice
                       D10 wants while files sit staged. A NOT BUILT paragraph describes
                       intent, never behaviour.
    Last revised:      2026-08-13
    Verified against:  Claude Code 2.1.222 (D1 to D7) · 2.1.228 (D8 to D10)
    Supersedes:        docs/DESIGN.md, split by feature 2026-08-12

What a memory is, where the two tiers divide, and what this kit may and may not do to a git repo
it does not own.

## D1. Two tiers, split by what may leave the machine

Global memory (`~/.claude/memory`) holds project-agnostic preferences and syncs across machines.
Mount memory (`~/.claude/memory-mounts`) holds project facts and never syncs.

The boundary is a privacy line first and an architecture second. Everything below it can name
projects and paths. Everything above it must survive being pushed to a personal GitHub repo.

## D2. The index is generated, never edited

`MEMORY.md`, the file loaded into every session, is rebuilt from the memory files on every
prompt.

Early on it was hand-edited, and twice an entry silently vanished: once to a hook race, once to
an automated rewrite. A derived index cannot drift or lose entries, and any writer that corrupts
it is undone one prompt later.

## D3. Memory files are What, then Why, then How, with no incident evidence inside

A rule states the preference, the generalized reason, and when it applies. The incident that
motivated it, meaning quotes, repo names and file paths, stays in the miner tracker and in git
history.

**The first design allowed a masked evidence section.** Work-identifying names kept riding in
through that exception faster than they could be masked, so the leak surface was removed
structurally rather than policed.

## D4. Authoring conventions are a write-time check, not seeded memory files

**They used to ship as two memory files installed into the user's memory folder**, on the
reasoning that the commit lint cannot reach memory-mounts and cannot shape behaviour at write
time. That diagnosis was right and the delivery was wrong: it put kit instructions inside the
user's data, where they cost context in every session, could be edited into drift, needed an
uninstall decision, and still verified nothing.

A `PreToolUse` hook on Write and Edit now checks a memory file as it is written, anywhere, with
no repo needed, and denies with the specific rule that was missed. The guidance and template
live in `guidance/`, versioned with the kit, and the deny message points at them, so the advice
arrives when it is needed instead of sitting in context all day.

This is the tooling-over-memory rule applied to the kit itself.

## D5. Only rules that hold for every legitimate file are enforced

An audit of real memory files set that boundary. Several correct rules carry their own "how"
with no section header, a `user_` profile has no `**Why:**` because it is not a rule, and a
`[[wikilink]]` may point at a memory not written yet. Denying any of those would make the check
worse than the drift it replaces, so they stay guidance, each with a test proving it is not
denied.

Enforced **by the write-time hook**, which is the only one that checks all of them; the commit
guardrail currently checks the first three (see [DESIGN-guardrail.md](DESIGN-guardrail.md) D3):
the type-prefixed filename, `name` equal to the filename slug (which the harness's
kebab-case default breaks, repeatedly, until this became mechanical), a present `description`
and `metadata.type`, a `**Why:**` on a `feedback_` rule, and no Evidence section in the tier
that syncs.

An Edit shows only a fragment, so absence is never judged from one.

## D6. Sync failures are classified, not swallowed

A pull that fails is sorted into offline, refused credentials, or diverged history, because each
one sends you somewhere different.

For refused credentials the message reads the repo's own configuration to name the mechanism in
use, whether that is an SSH key, a keychain, or a helper. That detection only shapes the
wording. Nothing in the kit checks for a credential tool or gates a sync on one.

## D7. What the kit may do to the memory repo, which it does not own

`~/.claude/memory` is the user's repo, and the kit reaches into it three ways: it writes the
generated index, it heals harness-stamped frontmatter, and it sets two git settings. The
boundary that keeps that honest has three parts.

**Nothing that git tracks is ever deleted**, because staging a deletion in someone's history is
a commit for them to make. A file the kit once seeded is removed only when it is still
byte-identical to the copy the kit ships, so anything deleted is reproducible from this tree,
and when the repo tracks it the installer says so and names the command instead.

**NOT BUILT: the kit is to stop rewriting a memory file at all, so the question of silence is
settled by not doing it.** The index pass strips harness-stamped frontmatter in place today and
names what it touched afterwards. Announcing after the fact is the wrong order under D8: managed
says what it will do before doing it, and a hook cannot hold that conversation. So the pass is to
report which files carry stamped keys and leave the strip to a skill, with the user's go-ahead in
managed and by the user's own hand in advisory. The in-place heal is still what ships.

The report has to be throttled through `mk_notice_due`, the same mechanism the review reminder and
the proposals ping use. Claude Code re-stamps `modified` on every native save, so an unthrottled
report would fire on essentially every prompt and become noise nobody reads, which is a worse
outcome than the silent rewrite it replaced.

**The two git settings are undone by `--uninstall`**, meaning the guardrail `hooksPath` and the
`skip-worktree` flag on the generated index.

## D8. The store is named, not reached: `autoMemoryDirectory` replaces the symlink

The kit made memory global by computing where Claude Code keeps a project's memory and symlinking
that onto `~/.claude/memory`. Computing it was the mistake. The setting names the destination, so
there is nothing to derive and nothing to link.

**One user-scope value covers every repository**, which is what the symlink was approximating one
project at a time. Three working directories, two of them unrelated repositories and one not a
repository at all, all resolved to a single configured path (O8).

**The setting wins over links already on disk** (O9). A machine part-way through the migration is
therefore not a broken state, and the old links can be cleaned up afterwards instead of unwound
first in some correct order.

**There is no version-gated fallback.** The key is declared in every build available to test, back
to 2.1.205 (O12), so the gate would never fire. Keeping the symlink as a fallback would mean
keeping the derivation alive to maintain, and the derivation is the defect.

**The derivation was wrong two independent ways, and both are deleted rather than fixed.** Claude
Code replaces dots as well as separators, which the kit did not (O11), and it derives memory from
the git repository root while transcripts come from the working directory, which the kit treated
as a single value (O10, O13). Patching either one leaves the other standing. Naming the
destination removes the question instead of answering it twice. Issue 40 closes here.

**Where the key points is a mode decision, not a detection trick.** Auto memory is on by default,
so a machine can already hold several stores, one per repository where Claude chose to save
something. The count is unpredictable, and folding several stores into one is a merge rather than
a move. So an existing `autoMemoryDirectory` is left exactly as it is, and a single existing store
is adopted where it stands.

Several stores are reported rather than guessed between, and what install does after the report
follows the mode. Advisory writes no setting at all, so the machine stays exactly as it was and
the report is the entire output. Managed writes the setting with the central store as the path,
which gives the kit somewhere to work without touching any store it found. Neither mode merges
anything, so the choice is between doing nothing and starting clean, never between two of the
user's stores.

**The mode is stated, never inferred.** An earlier version of this decision had install guess by
detection, treating several stores as advisory. Guessing was wrong here: the mode governs whether
the kit may rewrite a user's memory, and a machine that quietly picked for you is exactly the
machine you cannot trust with that. So a first install refuses until told which mode it is in, and
`DESIGN-install.md` D11 covers how that is asked for and remembered.

**Setup is two steps, and only the first is mechanical.** Install writes settings and markers and
never touches a memory file. Everything that moves, rewrites or deletes memory happens in the
`initialize-memory` skill, where a person is present. That split is forced rather than chosen: a
write inside `~/.claude` is a sensitive-file edit needing permission (O5), so a headless session
launched by an installer is the one caller that cannot do the work, while an interactive session
does it all day.

**What each mode does across those two steps:**

| | managed | advisory |
|---|---|---|
| install | writes the setting, marks the store, records what it found | writes nothing, reports what it found |
| the skill | states what it intends, then writes on your go-ahead | produces a plan and writes nothing |

Advisory therefore leaves a machine unconsolidated until it is switched to managed. That is the
point of it rather than a gap: advisory means tell me, not touch it.

**The mode is about who holds the pen, not about what is automatic.** Managed means the kit makes
the change, and never without saying first what it is about to do. Advisory means the user makes
the change, and the kit only says what it thinks should happen. Both announce. The difference is
who executes. Neither is ever fully automatic over a user's own memory, because these files hold
preferences and an automated edit fails in ways the person it belongs to would not see.

**So the line runs between a derived artifact and the user's files, not between hook and skill.**
`MEMORY.md` is generated from the files and holds nothing anyone wrote, so the kit regenerates it
in both modes: stopping would let the index drift out of step with the files, which is the exact
failure D3 exists to prevent, and recall would degrade with nobody told. Everything else in the
store is the user's, so the kit does not edit it unasked in either mode.

**Consent has two grains in managed, so that "always ask" does not become a prompt per keystroke.**
Passing `--mode=managed` is the consent for the mechanical writes: the setting, the marker, the
record. All are reversible, all are announced, and none touch a memory file. Per-group
confirmation inside a skill is the consent for anything that changes memory content.

**`save-memory` is not an exception to any of this.** Recording one file the user dictated is the
user authoring through the kit, not the kit editing the user, so it works in both modes. A rule
that blocked it would break the most-used skill in the most cautious mode.

Every skill is installed in both modes, since a skill is inert until called. What changes is what
it may do once called.

`CLAUDE.md` is untouched throughout: it is a different mechanism, user-written and per-project,
and this setting does not address it.

**The migration is a toggle, not a one-way door, and that is bought by leaving the old links
alone.** Removing them would be tidier and would make the change irreversible, because putting a
symlink back means deriving the path again, which is the code this decision deletes. Since the
setting already wins over a link on disk (O9), a stale link is inert rather than harmful. So the
links stay, and removing the key restores the previous behaviour exactly, with nothing to restore
from. Clearing them is a separate, explicitly invoked cleanup, never part of install.

**Consolidation copies and never moves.** Folding several stores into one is the only operation
here that could lose data, so it is bounded the way D7 bounds the rest: no source store is ever
deleted or emptied, the copy records what it took and from where, and the record is what makes it
undoable. Rolling back means removing the key and deleting what the record names; the sources were
never touched, so there is nothing to put back. An operation that cannot be undone this way is not
performed automatically, which is why several stores are reported rather than merged on a guess.

## D9. The kit marks a store it acts on, and records a store it only reads somewhere else

Without a record the kit cannot tell a store it created from one it adopted, and it cannot know
that it once pointed at a store it no longer points at. Rollback needs that history, and it has to
survive a reinstall, a kit upgrade, and the kit being removed entirely.

**A marker goes only into a store the kit creates, adopts, or copies into.** Finding a store is
not acting on it. Writing a marker into a store the kit merely read would break the advisory
contract, which is that advisory mode changes nothing, so the two rules would contradict each
other on the exact machine the mode exists to protect.

**A store the kit only found is recorded outside the user's stores**, in
`~/.local/share/claude-memory-kit/`. That is the same placement as the miner's tracker and for one
of the same reasons: it survives `--uninstall`, which state inside the deployed tree does not. So
the kit still knows every store it has ever seen, and a store it did not act on stays untouched.

**The marker is `.memory-kit-marker.json` at the root of the store.** It records the state, the
time, the path the setting names, how the kit reached this store (created, adopted, or copied
into), and the Claude Code version it was written under.

It does not record a kit version. The kit cannot report one yet, and a field holding a guess is
worse than an absent field, because a later reader cannot tell the two apart. The field arrives
when there is a real value to put in it.

**The state is one of three values.** `active` means the setting names this store. `legacy` means
the kit used it before and no longer does. `reverted` means the kit was removed and left the store
as it found it.

**An `initialized` field makes the setup skill idempotent.** Absent means `initialize-memory` still
has work to do, so it re-runs and picks up where it stopped. A timestamp means it finished and the
skill exits early. Re-running a finished setup means deleting the field, which is a deliberate act
rather than a flag someone passes by accident. The field lives here rather than in a second marker
file because this one already sits in the store, already survives `--uninstall`, and already
records what the kit did to it.

**It is deliberately not a `.md` file**, because the index scan and the guardrail lint both select
`*.md` and would otherwise report the marker as an unindexed or badly named memory file. Being
invisible to both is a property of the name, not a pair of new exemptions to keep in step.

**A store under git gets the marker added to `.git/info/exclude`, never to `.gitignore`.** The
marker records what happened on this machine, and the store may sync to others, so committing it
would claim a history that is not true elsewhere. A local exclude keeps a machine-local fact
machine-local and changes no tracked file, which keeps D7 intact.

**Writing the marker is announced once**, on the same reasoning as the frontmatter heal in D7: a
file appearing in someone's repo that they did not create is not something to do quietly.

**`--uninstall` sets the state to `reverted` and does not delete the marker.** This is a
deliberate exception to D5, and the reason is the whole point of the marker: a record of what the
kit did is what makes the change reversible after the kit is gone, so deleting it on the way out
destroys the only copy at the exact moment it becomes useful. `--purge-marker` deletes it, which
matches the existing `--purge-cache` and `--purge-tracker` flags for users who want no trace.

## D10. Consolidation stages per source, promotes what is safe, and reworks the rest

Managed brings several stores into one. Copying them into a single directory as they are cannot
work: memory files are named by convention, so two repositories will both plausibly hold
`user_profile.md` or `feedback_editing.md`. The code this kit replaced used `cp -n`, which skipped
a collision without a word and lost the second copy, and that silent skip is the class of failure
the whole store rework exists to remove.

**Each source is copied into its own folder under `~/.claude/memory/.staged/<source-tag>/`.** A
copy, never a move, so the source store is untouched and undoing is deleting what was copied.
Per-source folders make a collision impossible rather than handled.

**Staging inside the store is invisible to everything that reads it.** The index generator, the
unindexed warning, the guardrail lint and the write guard all select root-level `*.md` only, so a
staged file enters no recall, trips no warning and breaks no naming rule while it waits. That was
measured before the design was chosen rather than assumed.

**A staged file is promoted the moment it can be**, meaning its name is free at the root and it
matches `user_*` or `feedback_*`. Promotion is two string tests and a move, so it needs no
judgement and no model. This is what keeps memory live: without it a machine would install and
have nothing in recall until a person finished a rework.

**What stays staged is exactly what needs a person**: names that collide, and names that do not
conform. The rework goes group by group. One file may split into several because it holds two
ideas, several may merge into one because they say the same thing, and some are a rewrite in
place. A staged file is deleted only once its content is carried into the files that replace it,
so an interrupted rework loses nothing and resumes where it stopped.

**Done means `.staged/` is empty and removed.** That is a checkable finish line rather than a
feeling.

**NOT BUILT: while `.staged/` is non-empty the kit should say so**, because an optional step with
no reminder becomes work nobody ever does. Install points at the skill once; nothing repeats it
afterwards. The natural home is the health notice, throttled like every other one.

**The mode decides who executes, as everywhere else.** Managed states what it intends for a group
and acts on the go-ahead. Advisory produces the plan and writes nothing, so an advisory machine
stays unconsolidated until it is switched, which is the point of advisory rather than a gap.

## What would reopen this

- **D10, if memory filenames ever became unique by construction.** Every part of it exists
  because two stores can hold the same filename. A naming scheme that could not collide would
  reduce staging to a plain copy.
- **D9, if Claude Code gained a place to record which tool manages a store.** The marker exists
  because there is nowhere else to put provenance. A first-class field would make a file in the
  user's own repo unnecessary.
- **D8, if the setting stops applying at user scope, or gains a per-project form.** The whole
  decision rests on one user-scope value covering every repository (O8). A release that scoped it
  per project, or a supported build older than the key itself, would put the symlink back on the
  table.
- **D3, if masking became verifiable.** The evidence section was removed because masking could
  not be enforced, not because evidence is worthless. A check that could prove a quote carries
  no work-identifying name would reopen the trade.
- **D4, if the harness gained a way to ship guidance that is neither user data nor context
  cost.** The current answer is a hook plus a versioned `guidance/` directory because there was
  no third option.
- **D5, if the audit sample grows.** The enforced set is exactly what held across the real files
  examined. A larger sample could promote a guidance rule to enforced, or demote an enforced one.

## Failure posture

Every path here fails toward leaving the user's data alone.

The index is regenerated on the next prompt, so a corrupt or truncated write repairs itself
without anyone noticing. The write-time check denies rather than warns, because a warning about
a file already written is advice arriving too late. Sync classification never gates a sync; it
only changes what the message says. And the repo boundary refuses rather than guesses: a tracked
file the kit would otherwise remove is reported with the command instead, which is slower and
leaves the history to its owner.
