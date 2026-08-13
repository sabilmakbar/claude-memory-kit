# Design: the memory files, and the repo they live in

> **This is a decision record, not a user guide.** It is dense on purpose: it exists so that
> future changes know what they would be overturning. For how the kit behaves day to day, read
> [FLOWS.md](FLOWS.md). For setup, the README.

    Status:            Implemented
    Last revised:      2026-08-12
    Verified against:  Claude Code 2.1.222
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

**A rewrite is never silent**, because a heal the user did not make would otherwise surface as
an unexplained change in `git status`, so the index pass names each file it touched and what it
dropped.

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
a move. So an existing `autoMemoryDirectory` is left exactly as it is; a single existing store is
adopted where it stands; and several stores are reported rather than guessed between, with managed
mode proposing a target and acting only on consent, and advisory mode reporting and changing
nothing. `CLAUDE.md` is untouched throughout: it is a different mechanism, user-written and
per-project, and this setting does not address it.

## What would reopen this

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
