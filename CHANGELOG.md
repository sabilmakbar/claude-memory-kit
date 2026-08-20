# Changelog

Notable changes, newest first, in the spirit of
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

**How entries are written, from 0.2.0 onwards.** Each notable change gets one line under a
category, naming the pull request that delivered it so the reasoning is one click away. Routine
work is folded into a summary line rather than enumerated, because a changelog that lists
everything is a `git log` with extra steps. The date on a version is the date it was released.

0.1.0 below carries no pull request links, on purpose. A large part of what it contains arrived as
direct commits before this repo required pull requests, so anchoring the subset that had one would
make those changes look like the substance of the release when they are not.

**What a version means here.** The kit is installed by cloning and upgraded by re-running
`install.sh`, so there is nothing to pin in a package manager. A version names a state of `main`
that was tagged, and the tag is what you check out to go back to it. Versions move independently
from claude-session-kit: the two share conventions, neither depends on the other, and a bump in one
says nothing about the other.

## 0.3.1

### Added

- `install.sh` names the action for the state the machine is in, rather than reporting a
  single "installed or not". Four states need four different commands: nothing installed,
  marketplace added but plugin missing, installed and matching this checkout, or installed at
  an older version, which is offered `/plugin update` with the version it is on. That last one
  was silent before: the hooks and libraries came up to date while the skills stayed behind.
  `--dry-run` reports the state too, since reading it changes nothing.
- The plugin declares a SessionStart hook that reports a missing kit tree. Installing only the
  plugin is the one state `install.sh` cannot report, because it only speaks while it runs, and
  the hook fires from the plugin cache exactly when the plugin is present. It depends on nothing
  it reports on: no `jq`, no kit file.
- `install.sh` reports when this checkout is behind its tracking branch, from refs already
  fetched, so no network call is added. The plugin lives in its own clone, so a stale checkout
  and a stale plugin are separate facts and get separate lines.

### Tested

- Integration coverage for the installer end to end: a checkout behind its tracking branch is
  reported, a current one says nothing, uninstall prints the plugin removal order with the
  plugin before the marketplace, and uninstall leaves the plugin cache alone because the kit
  does not own it. Filesystem and git only, so it runs on CI.
- `tests/integration-plugin.sh` covers the rest, which needs the real `claude` CLI: that
  `marketplace add` and `plugin install` do not run each other, that a path source is not
  cloned, that the cache is keyed by the manifest version, that add and update are no-ops when
  satisfied, that nothing removes the cache, and that removing the marketplace first leaves
  the plugin unresolvable. It skips itself with exit 0 when the binary is absent, and is wired
  into CI so it starts running if a runner ever ships the CLI.

### Documented

- `docs/INTERNALS.md` records the plugin surface: how a marketplace is stored depends on its
  source, a remote one cloned into `plugins/marketplaces` and independent of your checkout
  while a path is referenced in place, the cache is keyed by the version in plugin.json, nothing runs at install and
  hooks are the only execution surface, removing a marketplace disables its plugin and orphans
  the cache, `plugin install` cannot pin a version or ref, and `marketplace add` and
  `plugin install` are a lookup rather than a chain: neither runs the other, and refreshing
  has two separate rungs in `marketplace update` and `plugin update`.

- Uninstall documents its required order. Taking the marketplace out before the plugin makes
  `plugin uninstall` fail, because it resolves the plugin through the registry, and the cache is
  then unremovable through the CLI. `install.sh --uninstall` prints the order, and the README
  states that neither command removes the plugin's cache directory.

- `docs/DEPENDENCIES.md` names the `claude` CLI as an install-time requirement for the half
  that carries the skills. It was listed only as a runtime dependency, or not at all.
- The documented update command is `claude plugin update`, not `/plugin update`. The slash form
  is not available in every host — the VS Code extension does not provide it — so an
  instruction offering only that form named a command the reader could not run. The slash form
  stays as a parenthetical, and the docs say where the binary lives when it is not on `PATH`.

### Fixed

- A skill now names the fix when the kit half is missing. Installing only the plugin left the
  skills present and failing on first use with a bare "no such file or directory" that never
  mentioned `install.sh`. This is the one state the installer cannot report, because it only
  speaks while it runs, so the skill has to. Each skill that depends on the tree they read from says
  what a missing path means and which command fixes it.

## 0.3.0

### Changed

- Skills now ship as a Claude Code plugin and are invoked with the `memory-kit` namespace
  (`/memory-kit:save-memory`), so they cannot be shadowed by a skill of the same name from
  another kit or from your own `~/.claude/skills`. `install.sh` no longer writes that folder;
  a re-run retires copies an older version left there, and reports rather than deletes anything
  it does not recognise as its own. Both install steps are now required: the plugin carries the
  skills, `install.sh` still carries the hooks, tree and config those skills read.
- `install.sh` now reports whether the plugin half is present, and no longer says it loads
  skills, which it has not done since they moved to the plugin. A half-install is the failure
  mode the split introduced: skills registered with no guidance file or config under them fail
  on first use, and the run is the cheapest place to name that (#58).

## 0.2.0

Released on 2026-08-18.

**Upgrading from 0.1.0.** Re-run `install.sh` from your checkout. Two changes can stop a run that
used to work: a first install now requires `--mode=managed` or `--mode=advisory`, and the
installer refuses a Claude Code older than 2.1.205. An install that already recorded its mode
needs no flag. Memory files are not touched by the upgrade.

### Added

- Auto memory is pointed at one store with the `autoMemoryDirectory` setting, replacing the
  derived path and the per-project symlinks. `install.sh` requires `--mode=managed` or
  `--mode=advisory` and records the answer, and `/initialize-memory` is the second half of setup,
  where anything that moves or rewrites a memory file happens with a person present. [#41](https://github.com/sabilmakbar/claude-memory-kit/pull/41)
- `/review-memories` measures whether a rule is obeyed, rather than only whether it is well
  written. Compliant and non-compliant cases are counted separately, so the result is a rate: a
  rule broken twice in three occasions and one broken twice in two hundred call for opposite
  responses. A rule that scores badly gets a hook proposed before it is reworded or retired. [#44](https://github.com/sabilmakbar/claude-memory-kit/pull/44)
- The failure report names which release of the kit is installed. The value comes from
  `git describe` at install time rather than from a tracked version file, so a tree whose
  provenance cannot be established reports `unknown` instead of a confident wrong answer. [#43](https://github.com/sabilmakbar/claude-memory-kit/pull/43)

### Fixed

- The `settings.json` backup is taken before anything rewrites the file. It used to be taken after
  two `jq` passes had run, so a legacy hook the install had just unwired was missing from the
  backup and a failed run restored a file still lacking it while reporting success. [#52](https://github.com/sabilmakbar/claude-memory-kit/pull/52)
- The list of non-memory filenames the checks skip is three names rather than seven. The extra four
  were only carried because the frontmatter lint used to run in this kit's own checkout. A store
  keeping its own `CHANGELOG.md` is now told to rename it. [#52](https://github.com/sabilmakbar/claude-memory-kit/pull/52)
- Four user-facing messages named the default store path rather than the store actually in use,
  one of them written into `MEMORY.md`. An adopted store therefore carried an unindexed-files
  warning pointing at a directory holding none of its files, in every session. The pass that
  retires old seeded files had the same fault and ran before the store was chosen, so on an
  adopted store it looked in the wrong place and left the old copy behind. [#50](https://github.com/sabilmakbar/claude-memory-kit/pull/50)
- The commit guardrail enforces the same seven memory-file rules as the write-time hook, from one
  implementation, instead of re-checking three of them by hand. A file arriving without passing
  through Write or Edit, such as a pull from another machine or a hand edit, previously met only
  those three before becoming permanent history. [#48](https://github.com/sabilmakbar/claude-memory-kit/pull/48)
- The memory frontmatter lint runs only inside the memory store, and the list of non-memory
  filenames it skips has one definition instead of four. Four copies had drifted into two lengths,
  so a `CONTRIBUTING.md` in the store was exempt from the commit lint and denied by the write-time
  hook at the same moment. A skipped lint now says so instead of passing silently. [#47](https://github.com/sabilmakbar/claude-memory-kit/pull/47)
- Every consumer reads the store named by `autoMemoryDirectory` rather than recomputing the
  default, and the commit guardrail is wired to that store. An install that adopted a project store
  previously left the index, the write guard and the reminders pointed at an empty directory. [#45](https://github.com/sabilmakbar/claude-memory-kit/pull/45), [#46](https://github.com/sabilmakbar/claude-memory-kit/pull/46)
- `--uninstall` acts only on a store inside the `$HOME` it was invoked with. It followed the
  absolute path in `autoMemoryDirectory` wherever it pointed, so a suite running in a throwaway
  `$HOME` seeded from the real `settings.json` reverted the real store. `--purge-marker` now
  sweeps rather than reading that setting, so it still works after a plain uninstall. [#42](https://github.com/sabilmakbar/claude-memory-kit/pull/42)

### Documentation

- The install output and the README name the settings scope the kit writes, and say what that
  excludes. [#51](https://github.com/sabilmakbar/claude-memory-kit/pull/51)
- Issue forms and a pull request template. The bug form asks for the `tests/smoke.sh` output
  first, which names the installed release since #43, because the README said the output was safe
  to share without ever saying where to send it. Nothing about the installed kit changes. [#54](https://github.com/sabilmakbar/claude-memory-kit/pull/54)

### Known limitations

- **The kit reads `autoMemoryDirectory` from the user settings file only.** Claude Code also reads
  the key from project and local settings. A per-project store set by hand is therefore honoured
  by Claude Code and missed by the index, the write guard, the reminders and the commit guardrail,
  which all go on watching the store named in the user file. The installer never writes the other
  scopes, so this needs someone to have set the key themselves. Recorded in
  [docs/DESIGN-memory.md](docs/DESIGN-memory.md) D8.
- **Verified against Claude Code 2.1.231**, and the installer refuses anything below 2.1.205.

The two guardrail limitations listed under 0.1.0 are closed: the commit hook now runs all seven
rules, and the frontmatter lint no longer runs in this kit's own checkout.

## 0.1.0

Released on 2026-08-12.

First tagged release, so there is nothing to compare against: what follows describes what 0.1.0
contains rather than what changed. It is the point at which the interface is considered settled
enough to name.

### Added

- **Preferences that persist**, as small text files loaded into every session, split across two
  tiers by what may leave the machine: global memory syncs, mount memory never does.
- **A generated index.** The file every session reads is rebuilt from your memory files on every
  prompt rather than edited, so it cannot drift or silently lose an entry.
- **A commit guardrail for a private memory repo.** Generic patterns catch any home path and any
  email, so the hook itself carries nothing identifying and can be public; your own private terms
  come from an untracked `denylist.local`. Commit time is the last moment before content becomes
  irreversible history.
- **A write-time check on memory files.** A `PreToolUse` hook holds a memory file to the kit's
  conventions as it is written, anywhere, with no git repo needed, and denies with the specific
  rule that was missed.
- **A daily suggestion loop**, started by your first session of the day rather than by cron. It
  reads what you typed and proposes preferences worth keeping. Rejection is two-strike: a proposal
  may return once on fresh evidence, then never.
- **Three skills**: save a memory directly, review pending proposals, and run a periodic review of
  what you have accumulated.
- **Health reporting.** A feature that cannot run records why, and says so once a day only after
  three days, because a warning you see constantly is one you learn to ignore.
- **Hook wiring at install time**, added to `~/.claude/settings.json` and removed again by
  `--uninstall`, along with the two git settings the installer made in your memory repo. Memory
  files are never touched. The installer refuses a file whose shape it cannot merge into before
  deploying anything.
- **Tunable knobs in a config file**, parsed rather than sourced, with the file doubling as the
  inventory: a knob not listed there is not read.
- **Two test suites.** A fixture suite that gates every install, and a real-data suite that checks
  the kit against your own `~/.claude` and skips where you have no data.

### Documentation

A plain-language `HOW-IT-WORKS.md`, a diagram-led `FLOWS.md`, five decision records split by
feature with numbered decisions, and a separate `INTERNALS.md` recording what was observed about
Claude Code rather than what this kit decided. Plus `TROUBLESHOOTING.md` by symptom,
`DEPENDENCIES.md`, `CONTRIBUTING.md` and a LICENSE.

### Known limitations

- **The commit guardrail checks three of the seven rules** the write-time hook checks. The gap
  includes the no-Evidence rule on the tier that syncs, which matters because a memory file that
  never passed through the Write or Edit tools can carry one past the commit check. Recorded, with
  the intended fix, in [docs/DESIGN-guardrail.md](docs/DESIGN-guardrail.md) D3.
- **The frontmatter lint also runs in this kit's own checkout**, where no memory file has ever
  lived, so every new root-level document has to be added to an exemption list. That list is
  duplicated across two files in two syntaxes and has already drifted between them once. Same
  record, same decision.
- **Two of the seven observations in [docs/INTERNALS.md](docs/INTERNALS.md) have no recorded
  provenance.** They were learned from incidents during development and never dated, so they are
  marked as such and are the least trustworthy entries there.
- **The fixture suite cannot detect drift.** Fixtures encode what we believe Claude Code's format
  to be, so they pass forever against a stale belief. Only the real-data suite closes that, and it
  needs your machine.
- **Verified against Claude Code 2.1.222.** The real-data suite also passes over transcripts
  written by 20 versions, 2.1.177 through 2.1.222. Older versions are untested.

### Compatibility

Bash and zsh, macOS and Linux, including stock BSD userland and bash 3.2. Needs `jq`; the miner and
sync also use `git` and the `claude` CLI.
