# Contributing

The short version: read [docs/INTERNALS.md](docs/INTERNALS.md) first, then the decision record
for the area you are touching. Both exist so that a change knows what it would be overturning.

## Start with what is observed, not with what we decided

This kit reads files Claude Code owns, and Claude Code documents none of them.
[docs/INTERNALS.md](docs/INTERNALS.md) records what was actually observed, with the date and
version each entry was seen on, the surface it was read from, how it was checked, and what you
need to re-run the check yourself.

**Two of its seven entries have no recorded provenance.** They were learned from incidents
during development and written down only as a clause inside a decision, so they carry
`First observed: not recorded`. Those are the entries to doubt, and re-verifying one is a genuinely
useful contribution.

Two more cannot be checked automatically at all: one needs a headless session, one needs two
different interfaces to compare.

## Then the decision record

Five files under `docs/`, one per feature:

| Record | Covers |
|---|---|
| [DESIGN-memory.md](docs/DESIGN-memory.md) | the memory files, the two tiers, and the repo the kit does not own |
| [DESIGN-miner.md](docs/DESIGN-miner.md) | the daily loop that proposes preferences |
| [DESIGN-guardrail.md](docs/DESIGN-guardrail.md) | the commit check and the write guard |
| [DESIGN-install.md](docs/DESIGN-install.md) | deployment, the shared `settings.json`, and the knobs |
| [DESIGN-health.md](docs/DESIGN-health.md) | how you find out the kit has stopped working |

Each opens with its status and the Claude Code version behind it, numbers its decisions `D<n>`,
and ends with two sections worth reading before you change anything: **What would reopen this**,
and **Failure posture**.

Decisions cite observations by number rather than restating them, so a fact has one home. Before
amending an observation, check what rests on it:

```bash
grep -rn '\bO7\b' docs/DESIGN-*.md
```

## Code layout

**One accessor layer, `core/lib.sh`.** Every path into Claude Code internals, meaning transcript
layout, session ids from hook stdin, and binary and version discovery, and every behaviour shared
by more than one script, meaning notice markers, dual-audience emission and the GNU/BSD `stat`
shim, lives in a single sourceable file. The scripts stay thin.

Before the lib, the same logic existed in two or three slightly different copies: two binary
resolvers and three session-id parsers, and each harness change had to be found and fixed per
script.

Functions fail quiet, returning empty and non-zero rather than an error, so a harness change
degrades hooks to "no data" instead of breaking prompts.

## Proposing something different

That is what these files are for, so it is welcome. What helps:

- **Name the observation you are relying on.** If it is not in `INTERNALS.md`, say how you checked
  it, on which version, and how someone else would re-run it. An observation with no method behind
  it is a guess, and this kit has been wrong that way before.
- **Name the decision you would overturn.** Cite it as `D<n>` in its file. Every record says why
  each rule exists, including the ones that look arbitrary.
- **Read "What would reopen this" first.** Several decisions already name the condition that would
  break them. If yours is on that list, the argument is half made.
- **Say what would reopen your own proposal.** Every decision here that has been reversed was
  reversed because someone wrote down the condition that would break it.

## Before you open a pull request

```bash
bash tests/run.sh      # the fixture suite; install.sh refuses to deploy a tree it rejects
bash tests/smoke.sh    # the real-data suite, against your own ~/.claude
```

`run.sh` is the gate. `smoke.sh` passes or skips depending on the machine it runs on, which is the
point, so it is never a required check.

Point the commit guardrail at your checkout too. It adds one house rule on top of the leak
checks: no em-dashes on lines added to `README.md` or `docs/*.md`.

```bash
git -C . config core.hooksPath guardrail
```

One thing the fixture suite cannot do: notice that Claude Code changed. Fixtures encode what we
believe the format to be, so they pass forever against a stale belief. That is what `smoke.sh` and
`INTERNALS.md` are for, and why re-verification is a manual pass rather than a green check.
