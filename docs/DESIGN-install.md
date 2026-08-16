# Design: installing, upgrading, and the knobs

> **This is a decision record, not a user guide.** It is dense on purpose: it exists so that
> future changes know what they would be overturning. For how the kit behaves day to day, read
> [FLOWS.md](FLOWS.md). For setup, the README.

    Status:            Implemented
    Last revised:      2026-08-12
    Verified against:  Claude Code 2.1.222
    Supersedes:        docs/DESIGN.md, split by feature 2026-08-12

How the tree gets deployed, how `settings.json` is shared with every other tool, and where the
knobs live. Nearly every decision here is a scar: the failures are named because each one is now
a test.

## D1. Deployment is a test-gated whole-tree copy

The installer runs the fixture suite first and refuses to deploy a tree the tests reject, so what
ships is always a tested snapshot. It then replaces `~/.claude/memory-kit` as one unit. Scripts,
their core lib, hooks, guardrail and tests move together, so a script can never run against a
stale sibling.

**The earlier layout scattered loose script copies into a shared directory, which drifted from
the checkout four separate times during development.**

**Run-in-place was considered and rejected.** Hooks pointing at the checkout would let `git pull`
ship an untested working tree straight into live sessions, which the gate makes impossible.

The deployed tree also accumulates machine state, `.verified` and the private denylist, that a
redeploy deliberately preserves.

## D2. Upgrades migrate, then merge

Old-layout hook commands are re-pointed onto the tree first, matched strictly by our script
basenames so other tools' hooks in the same directories are never touched. Then the normal
append-and-dedup merge runs. Finally the stale legacy copies, exactly ours and nothing else, are
removed.

## D3. The settings merge is append-only, deduped per hook, by script filename

Three earlier approaches each broke, and each is now a test:

- **Deep-merge** replaced other tools' hook arrays.
- **Deduping by exact command string** broke on `$HOME` versus absolute-path spellings.
- **Deduping per group**, keyed on the group's first hook, silently dropped any hook later added
  to an existing group, which meant upgrades never delivered new hooks to installed machines.

## D4. Ownership is the basename and the directory, so a shared filename is not a collision

**Deduping on the basename alone was wrong in both directions.** Any other tool shipping a file
of the same name could make us skip wiring our own hook, leaving a silently dead kit, and then let
an uninstall delete theirs.

**This kit renamed its own `version-check.sh` once to dodge that, which was a workaround rather
than a fix.**

A hook is ours only when the basename is one we ship and its directory sits inside the deployed
tree. Anything else using one of our names is left alone and reported, because silence there looks
like a bug in us. The managed list is derived from `settings.snippet.json`, so adding a hook is
one edit and both halves see it.

## D5. Uninstall is the same contract in reverse, and `settings.json` is treated as shared

The kit writes hooks, so it removes them: a tool that adds to a file it shares and cannot take
its own additions back out leaves the user no undo except editing by hand.

Four properties make writing a file every other tool shares survivable:

1. It is **written last**, after everything else has installed, so a run that fails earlier never
   touches it.
2. The result is **validated before it replaces the live file**: wiring must not shrink the hook
   count, and removal must leave every hook that was not ours untouched.
3. The merge runs **against a snapshot** and refuses if the live file changed underneath, since
   Claude Code and other installers write it too.
4. A failure after the write is **rolled back** from a kit-specific backup, or by deleting a file
   that did not exist beforehand.

Removal prunes upward, dropping emptied groups, then events, then the `hooks` key.

## D6. The shape check covers the events we wire, not every event in the file

A `settings.json` that parses can still hold a shape the merge cannot use (O7), and finding that
out mid-merge meant a raw parser error at the end of a half-finished install, so a preflight now
refuses first.

**The first version of it checked every event in the file, which was too wide.** An event this
kit never wires belongs to some other tool: the merge only reads the keys
`settings.snippet.json` declares, so a wrong-typed foreign event survives an install and an
uninstall untouched, and refusing over it was judging config we did not write. The list of events
comes from the snippet, so wiring a new one cannot forget to widen the check.

Two things are still refused: `hooks` itself being the wrong type, because that is the container
we have to write into rather than someone else's key, and an event of ours holding anything that
is not a hook group. Nothing is ever repaired automatically.

## D7. Uninstall undoes what install did outside its own tree, and nothing else

Deleting the tree while the memory repo's `core.hooksPath` still pointed into it would leave git
finding no hook and running nothing, so the commit guard would stop silently while the repo still
looked configured. **That is the worst failure available here**, so uninstall unsets it, and only
when it points at our tree.

It also clears the `skip-worktree` flag that hid `MEMORY.md`. Memory files are never touched.

The miner's tracker is kept by default because its rejection history is what stops a reinstall
re-proposing what you refused. Two flags remove it, and both say what they are deleting.

## D8. Knobs live in a file, not in `settings.json`

A `KEY=value` file at the deployed kit root is the only mechanism that reaches every context the
kit runs in: hooks, skill and Bash-tool commands, the miner that a hook launches as a grandchild,
and the guardrail that git spawns. Environment variables cannot be relied on to reach all four,
and `settings.json` belongs to the orchestrator.

The file is **parsed, never sourced**, so a stray line in a hand-edited file cannot become code
inside a hook. Precedence is the environment variable, then the file, then the built-in default,
which keeps every existing override working. A malformed value falls back silently, because a
typo must not break a session start.

The file also serves as the inventory: if a knob is not listed there, the kit does not read it.

## D9. The prefix is exact: `MEMORY_KIT_*` is a user knob, `CLAUDE_MEMORY_KIT_*` is not

The value is that a name answers "is this configurable" without anyone reading code to find out.
Getting there cost renaming three knobs that already worked, and one test seam.

**The objection to renaming was that a machine setting an old name in a shell profile would go on
being ignored in silence**, which is the failure this kit works hardest to prevent. That objection
is answered rather than accepted. The installer rewrites old keys inside a live config file,
commented or not, so a file-based setting migrates itself. The one place no installer can reach is
an export in someone's shell profile, so the health hook reports an old name by name, immediately
rather than after the usual grace period, since it is already being ignored and the fix is one
edit away.

Two checks keep the inventory honest alongside the prefix, because a convention that must be
remembered is weaker than a test that cannot be forgotten. One fails when the code reads a knob
`config.example` does not declare. The other fails when a machine's own config sets a knob the
code no longer reads.

## D10. Install writes one setting into `settings.json`, and refuses rather than degrades

`autoMemoryDirectory` is the mechanism the store now relies on (`DESIGN-memory.md` D8), so install
has to write a key into the file D5 already treats as shared. Three constraints follow, and none
of them are new: they are the shared-file discipline applied to a value rather than a hook.

**The key is written, never merged into.** It is a single string, so there is no array to append
to and no other tool's entry to preserve inside it. A value already present is left alone and
reported, on the same reasoning as D4: something we did not write is not ours to overwrite, and
silently replacing it would relocate a user's memory without telling them.

**`--uninstall` removes it, and only if we wrote it**, which is D5 and D7 unchanged. The uninstall
contract is that the kit undoes what it did outside its own tree and nothing else, so a value the
kit adopted rather than authored is left behind on purpose.

**Below the floor, install refuses instead of falling back.** D8 records why there is no symlink
path to fall back to. A kit that half-installs is the failure mode D5 and D6 exist to prevent, so
the check runs before anything is written and says the version it found and the version it needs.
The floor is at or below the oldest build available to test (O12), so this is a guard against a
machine nobody has seen rather than a branch anyone will hit.

The version accessor already exists for the health hook (O4), so this adds a caller rather than a
mechanism.

**Every change this decision makes outside the kit's own tree is reversible, and the reversal is
tested, not assumed.** The key is one line, so removing it returns the machine to the default. The
old symlinks are deliberately left in place (`DESIGN-memory.md` D8), so that reversal needs no
restore step at all. Nothing else is written.

Because those symlinks stay, the sentence install prints when it writes the key says the machine
goes back to where it was before the install, not that each project goes back to its own store.
The second phrasing is true only on a machine that never had the symlinks, and it was the phrasing
shipped first. On an upgraded machine, deleting the key sends every project back through its
symlink into the central store, which is the pre-install behaviour and is exactly what reversal is
supposed to mean. The wording had to name that, rather than describe the fresh case and leave every
upgraded machine reading a false statement about its own rollback.

**Renaming a wired hook breaks that reversibility unless the old name is remembered, so it is.**
`managed_names` is derived from `settings.snippet.json`, which after a rename lists only the new
name, so an uninstall would leave the old entry standing and pointing at a script that no longer
exists. That is the D3 failure mode in a new disguise: a spelling the merge cannot see. The kit
therefore carries an explicit list of names it has previously wired, and both the upgrade and the
uninstall act on the current names plus that list. The list only grows, and a rename adds to it in
the same commit that performs the rename, so the two cannot drift apart.

This is the general rule the rest of the file already follows and is worth stating once: an
operation the kit cannot undo is not performed automatically. Refusing below the version floor,
leaving a value the kit did not write, and reporting several stores rather than merging them are
all the same rule.

## D11. The mode is a required argument on a first install, and remembered after that

`MEMORY_KIT_MODE` decides whether the kit may rewrite a user's memory, so it is the one setting
this installer will not pick for you. A first install on a machine with no recorded mode refuses
until given `--mode=managed` or `--mode=advisory`, and prints what it found first so the choice is
informed rather than a coin toss.

**Requiring it on every run was considered and rejected.** `README.md` states in two places that
re-running the installer is the upgrade path, and 44 invocation sites across the tests and docs
call it. A flag mandatory on every run would mean every upgrade restates the mode, and a value
that differs from last time would change how the machine behaves during what the user thought was
a routine upgrade. The hard stop belongs where the decision is actually made, and nowhere else.

**So the choice is recorded in the config file** beside every other knob (D8), and later runs read
it. Passing `--mode` again overrides, re-records, and says out loud that it changed, because a
mode flip is a behaviour change and silence there is the failure this whole file guards against.

This replaces the detection default that an earlier draft carried, where several stores implied
advisory. Detection still runs and still prints what it found; it just advises instead of
deciding.

## What would reopen this

- **D11, if the installer ever needs to run unattended on a fresh machine.** A required argument
  is fine for a person at a terminal and fatal for provisioning. The answer then is a recorded
  mode shipped with the machine's config, not a default.
- **D10, if Claude Code gained a settings scope the kit should prefer over user scope.** The key
  is written at user scope because that is what covers every repository (O8). A managed or policy
  scope with different precedence would change where it belongs, not whether it is written.
- **D1, if the fixture suite ever became slow enough that the gate is skipped in practice.** A
  gate people work around is worse than no gate, because it carries the reassurance without the
  check.
- **D4, if Claude Code gained a real ownership marker in `settings.json`.** Basename plus
  directory is an inference. A first-class owner field would replace it outright.
- **D6, if the shape ever needs repairing rather than refusing.** The current rule is that a
  wrong-typed key holds something the installer did not write and must not guess at. A shape the
  kit demonstrably wrote itself would be a different case.
- **D8, if a mechanism appeared that reached all four execution contexts.** The file exists
  because environment variables do not, and `settings.json` is not ours.
- **D9, if the migration ever misses a case.** It is the whole reason the rename was acceptable.

## Failure posture

The ordering is the safety property: everything reversible happens before anything shared.

The tests gate the deploy, the deploy happens before `settings.json` is touched, and the write to
that file is validated against a snapshot before it replaces anything. A run that dies at any
point leaves the shared file either untouched or restored, never half-merged. A shape the merge
cannot use stops the run before a single file is deployed, so the failure costs nothing to undo.

Uninstall inverts the same order and is deliberately conservative: it removes only what it can
prove it owns, keeps the rejection history unless told twice, and never touches a memory file.
Config reads fail toward the default rather than toward an error, because a typo in a knob must
not break a session start.
