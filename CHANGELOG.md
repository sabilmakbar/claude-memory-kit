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

## Unreleased

### Added

- Auto memory is pointed at one store with the `autoMemoryDirectory` setting, replacing the
  derived path and the per-project symlinks. `install.sh` requires `--mode=managed` or
  `--mode=advisory` and records the answer, and `/initialize-memory` is the second half of setup,
  where anything that moves or rewrites a memory file happens with a person present. [#41](https://github.com/sabilmakbar/claude-memory-kit/pull/41)

### Fixed

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
