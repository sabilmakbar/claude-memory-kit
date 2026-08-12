# Claude Code internals, as observed

> **This file is about Claude Code, not about this kit.** It records what was observed about
> undocumented behaviour the kit depends on. The decisions those observations drove live in the
> `DESIGN-*.md` records, which cite these by number. For how the kit behaves, read
> [FLOWS.md](FLOWS.md).

    Observed against:   Claude Code 2.1.222
    Platform:           macOS, VS Code extension
    Last re-verified:   2026-08-12
    Needs to re-run:    jq, find, a machine with an installed Claude Code

Nothing here is promised by Claude Code. Every entry carries the date and version it was seen
on, the surface it was read from, how it was checked, and what you need to re-run the check, so
it can be re-run rather than believed.

**Three entries have no recorded provenance**: O5, O6 and O7 were learned from incidents during
development and written down only as a clause inside a decision. They are marked
`First observed: not recorded`, which is a gap rather than a detail. Treat them as the least
trustworthy entries here until someone re-verifies them and fills the date in.

Commands that answer this file's own claims, so none of the counts above have to be believed:

```bash
# which observations a script could re-check, and which need a person or a live session
awk '/^### O/{o=$2} /Checkable: +automated/{print o}' docs/INTERNALS.md

# every version any entry has been seen on
grep -hoE '2\.1\.[0-9]+' docs/INTERNALS.md | sort -u

# which decisions rest on a given observation, before you amend it
grep -rn '\bO1\b' docs/DESIGN-*.md
```

**Numbers run in discovery order, positions run by surface.** An entry can sit between two
lower-numbered neighbours. Numbers are never reused: a retired entry keeps its number and gains
a `Withdrawn:` line, so a citation in a decision record stays valid however this file is later
reorganised.

## The surfaces

| Surface | Path | Written by | Lifetime |
|---|---|---|---|
| Transcript | `~/.claude/projects/<encoded-cwd>/<session-id>.jsonl`, with subagent transcripts deeper (O2) | Claude Code, append-only | permanent |
| Hook stdin | a JSON object on the hook process's stdin | Claude Code, per invocation | one invocation |
| Hook stdout | a JSON object the hook prints | the hook | one invocation |
| CLI binary | on `PATH`, or inside the VS Code extension | Anthropic, per release | per release |
| `settings.json` | `~/.claude/settings.json` | Claude Code, this kit, and any other tool | permanent, shared |
| `~/.claude` itself | the config root | Claude Code | permanent |

## The transcript

### O1. Session transcripts sit exactly two levels under the projects directory

    First observed:     2026-08-12 · 2.1.222
    Re-verified:        2.1.222
    Surface:            transcript
    How:                counted on one machine: 3 encoded-cwd directories, 24 `.jsonl` files, all
                        at `~/.claude/projects/<encoded-cwd>/<session-id>.jsonl`, none shallower
    Needs:              find
    Checkable:          automated

The directory name is the working directory with separators replaced, and the file stem is the
session id. Nothing joins them but that convention.

### O2. Subagent transcripts exist, nested below the session that spawned them

    First observed:     2026-08-12 · 2.1.222
    Re-verified:        2.1.222
    Surface:            transcript
    How:                counted on one machine: 24 session transcripts at depth 2, and 16 more at
                        `<encoded-cwd>/<session-uuid>/subagents/agent-<hex>.jsonl`. Every
                        `<session-uuid>` directory had a real session transcript beside it at
                        depth 2. A sibling `tool-results/` holds `.txt`, not `.jsonl`
    Needs:              find
    Checkable:          automated

**A recursive `*.jsonl` glob over `projects/` therefore returns 40 files where 24 are sessions.**
Depth bounds separate them, because the subagent files are two levels deeper. A name filter on
`agent-*` rejects them a second way.

This was load-bearing before it was written down anywhere: it survived only as a depth bound and
a name filter inside one `find` command in `scripts/extract-user-messages.sh`. A later
simplification of that command would have fed subagent transcripts to the miner as if they were
user messages, and nothing would have failed.

## Hook input and output

### O3. A hook receives its session id as `.session_id` on stdin

    First observed:     2026-08-12 · 2.1.222
    Re-verified:        2.1.222
    Surface:            hook stdin
    How:                fed `{"session_id":"probe-abc123","other":1}` to `mk_session_id` and got
                        `probe-abc123` back. The accessor reads `.session_id` and nothing else
    Needs:              jq
    Checkable:          automated

There is no other reliable route to the id from inside a hook. The accessor returns empty rather
than failing when stdin is a terminal, so a hook run by hand degrades to "no id" instead of
erroring.

### O6. `systemMessage` is not displayed by every interface

    First observed:     not recorded
    Re-verified:        not since
    Surface:            hook stdout
    How:                not recorded. Learned from an incident: a notice emitted only as
                        `systemMessage` ran silently for weeks in an interface that never showed
                        it, and proposals piled up unseen
    Needs:              a second interface to compare against
    Checkable:          manual (requires observing two interfaces)

`additionalContext` reaches the model, which then relays the notice in its first reply. Emitting
both in one payload is what makes a notice arrive regardless of interface.

**This entry is the weakest in the file.** It records a real failure but neither the date, the
version, nor which interface was silent. Anyone who can reproduce it should replace this text.

## The config root

### O5. A headless session cannot write inside `~/.claude`

    First observed:     not recorded
    Re-verified:        not since
    Surface:            `~/.claude` itself
    How:                not recorded. Learned from an incident: the miner's first write was
                        silently blocked, attributed to sensitive-file protection over the config
                        root
    Needs:              a headless session
    Checkable:          manual (requires running a headless session)

This is why the miner's tracker lives at `~/.local/share/claude-feedback` rather than beside the
kit. The mechanism was never confirmed against a version, only inferred from the failure.

### O7. `settings.json` hooks is an object keyed by event, each event an array of groups

    First observed:     2026-08-12 · 2.1.222
    Re-verified:        2.1.222
    Surface:            `settings.json`
    How:                probed the installer against four shapes: `{"hooks":42}` and an event
                        holding a string are both unmergeable, a group holding a string survives
                        untouched, and unparseable text is refused outright
    Needs:              jq
    Checkable:          automated

A file can parse as JSON and still hold a shape no merge can use, which is a different failure
from invalid JSON and needs a different message. The kit shares this file with Claude Code and
with every other tool, so it is the one surface where being wrong damages someone else's work.

## The binary

### O4. The CLI is on `PATH` or inside the VS Code extension, and reports its own version

    First observed:     2026-08-12 · 2.1.222
    Re-verified:        2.1.222
    Surface:            CLI binary
    How:                read the accessor at `core/lib.sh:215`: it falls back to the newest match
                        under `~/.vscode/extensions/anthropic.claude-code-*/resources/native-binary/claude`
                        or the `.vscode-server` equivalent, then takes the first field of
                        `--version`
    Needs:              an installed Claude Code
    Checkable:          automated

The extension path carries a version in the directory name, so the newest match is the current
install. A machine with neither the CLI on `PATH` nor the extension present has no binary to
find, which the kit treats as a blocked feature rather than an error.
