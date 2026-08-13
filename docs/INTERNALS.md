# Claude Code internals, as observed

> **This file is about Claude Code, not about this kit.** It records what was observed about
> undocumented behaviour the kit depends on. The decisions those observations drove live in the
> `DESIGN-*.md` records, which cite these by number. For how the kit behaves, read
> [FLOWS.md](FLOWS.md).

    Observed against:   Claude Code 2.1.222 (O1–O7) · 2.1.228 (O8–O13)
    Platform:           macOS, VS Code extension
    Last re-verified:   2026-08-12 (O1–O7) · 2026-08-13 (O8–O13)
    Needs to re-run:    jq, find, a machine with an installed Claude Code

Nothing here is promised by Claude Code. Every entry carries the date and version it was seen
on, the surface it was read from, how it was checked, and what you need to re-run the check, so
it can be re-run rather than believed.

Entries that touch something Anthropic has published carry a `Docs:` line naming the page and
saying whether it agrees. Documentation is not a substitute for the observation: it describes
intent, it is versioned separately from the binary, and on two entries here it disagrees with
what the binary itself declares (O8, O10). Where the two conflict, the entry records both and
the observation decides.

**Two entries have no recorded provenance**: O5 and O6 were learned from incidents during
development and written down only as a clause inside a decision. They are marked
`First observed: not recorded`, which is a gap rather than a detail. Treat them as the least
trustworthy entries here until someone re-verifies them and fills the date in. The count is `grep -c '^ *First observed: *not recorded' docs/INTERNALS.md`, anchored to the
field so it cannot count this sentence, and so it cannot drift from the entries again.

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
| Memory directory | `~/.claude/projects/<encoded-cwd>/memory/`, or wherever `autoMemoryDirectory` points (O8) | Claude Code and this kit | permanent |

## The transcript

### O1. Session transcripts sit exactly two levels under the projects directory

    First observed:     2026-08-12 · 2.1.222
    Re-verified:        2.1.222
    Surface:            transcript
    How:                counted on one machine: 3 encoded-cwd directories, 24 `.jsonl` files, all
                        at `~/.claude/projects/<encoded-cwd>/<session-id>.jsonl`, none shallower
    Needs:              find
    Checkable:          automated

The directory name is the working directory with separators replaced, dots included (O11), and the
file stem is the session id. Nothing joins them but that convention.

This describes the transcript directory only. Memory for the same session can sit under a
different encoded name, because it derives from the repository root rather than the working
directory (O13).

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

## The memory directory

### O8. `autoMemoryDirectory` in user settings redirects auto memory for every working directory

    First observed:     2026-08-13 · 2.1.228
    Re-verified:        2.1.228
    Surface:            memory directory
    How:                set the key in `~/.claude/settings.json` to a path outside `~/.claude`,
                        then asked a headless session in three working directories (two unrelated
                        git repositories and one non-repository) for its memory directory. All
                        three reported the configured path. Restored the file from a copy after
    Needs:              jq, an installed Claude Code, a writable `~/.claude/settings.json`
    Docs:               https://code.claude.com/docs/en/memory. Documents the key, the accepted
                        scopes and the `~/` or absolute value rule, but not that one user-scope
                        value covers every repository. That is the part this entry tests
    Checkable:          automated, but it writes user settings, so copy the file first

This is what lets the kit make memory global by declaration rather than by symlinking each
project's directory onto one store. Only user scope was tested. For project scope the published
documentation and the schema shipped inside the binary disagree: the schema says a checked-in
`.claude/settings.json` value is ignored for security, the documentation says it is honoured once
the workspace trust dialog is accepted. Neither was tested, and the kit needs neither.

### O9. The configured directory wins over a symlink left at the default location

    First observed:     2026-08-13 · 2.1.228
    Re-verified:        2.1.228
    Surface:            memory directory
    How:                during the O8 probe, all three default locations still held the kit's
                        `memory` symlink, and the non-repository one held a real directory at the
                        spelling Claude Code reads. Every session followed the setting anyway
    Needs:              the O8 setup, plus a pre-existing symlink or directory
    Docs:               not documented
    Checkable:          automated, same caveat as O8

This is the exact state a machine is in while migrating off the symlink, so a migration can set
the key first and clean up links afterwards, rather than having to unwind them in the right order.
It says nothing about what happens when the setting is later removed while the links remain.

### O10. The default directory is derived from the git repository root, not the working directory

    First observed:     2026-08-13 · 2.1.228
    Re-verified:        2.1.228
    Surface:            memory directory
    How:                asked a headless session started in `~/claude-memory-kit/core` for its
                        memory directory; it reported the encoding of the repository root, not of
                        the subdirectory
    Needs:              an installed Claude Code, a repository with a subdirectory
    Docs:               https://code.claude.com/docs/en/memory. Agrees: "derived from the git
                        repository, so all worktrees and subdirectories within the same repo share
                        one auto memory directory. Outside a git repo, the project root is used
                        instead"
    Checkable:          automated

The settings schema shipped with 2.1.228 contradicts this, describing the default as
`~/.claude/projects/<sanitized-cwd>/memory/`. The observed behaviour follows the repository root
and matches the documentation, so the schema's wording is the thing that is wrong. Worth knowing
because the schema is otherwise the more reliable of the two surfaces (O8).

The schema's `<sanitized-cwd>` is not simply loose wording. The transcript directory really is
derived that way (O1), so the schema states a real rule against the wrong directory. The two
derivations differ, which is O13.

### O11. The encoded directory name replaces dots as well as path separators

    First observed:     2026-08-13 · 2.1.228
    Re-verified:        2.1.228
    Surface:            memory directory
    How:                a headless session started in `~/.local/share/claude-feedback`, which is
                        not a repository, reported a memory directory whose encoded name ended
                        `--local-share-claude-feedback`, where the kit computes
                        `-.local-share-claude-feedback`. The leading dot of `.local` had collapsed
                        into a second dash
    Needs:              an installed Claude Code, a path containing a dot segment
    Docs:               not documented; the page describes how the name is derived but never which
                        characters are replaced
    Checkable:          automated

The kit replaces only path separators, so for any path with a dot segment it computes a different
name than Claude Code does, and writes its symlink into a directory nothing reads. Both spellings
exist on the machine this was observed on, with the kit's symlink in the unread one and a real,
isolated memory directory in the one Claude Code uses.

The same sanitizer applies to the transcript directory, not only the memory one: on that machine
the dot-collapsed spelling is the directory that holds real session data, and the kit's spelling
holds nothing but the symlink.

### O13. Transcripts and memory derive from different paths, so the two directories can differ

    First observed:     2026-08-13 · 2.1.228
    Re-verified:        2.1.228
    Surface:            transcript and memory directory
    How:                started two sessions in a subdirectory of a git repository. Both transcripts
                        landed under the subdirectory's encoded name, while both sessions reported
                        their memory directory under the repository root's encoded name
    Needs:              an installed Claude Code, a repository with a subdirectory
    Docs:               not documented. The page gives the memory directory's derivation (O10) and
                        never says that transcripts follow a different rule
    Checkable:          automated

O1 records the transcript directory as the working directory encoded. O10 records the memory
directory as the repository root encoded. Both are correct, and they are not the same path, so a
session started below a repository root writes its transcript under one encoded name and reads its
memory from another.

Anything that computes one of these and uses it as the other is wrong for every session started
below a repository root. That is the second fault in issue 40, and it is why fixing the dot
sanitizing alone would not have been enough.

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

### O12. Each extension build ships the settings schema it accepts, and `autoMemoryDirectory` is in every one back to 2.1.205

    First observed:     2026-08-13 · 2.1.228
    Re-verified:        present in all 20 builds on the machine, 2.1.205 through 2.1.228
    Surface:            CLI binary
    How:                read `claude-code-settings.schema.json` from every
                        `~/.vscode/extensions/anthropic.claude-code-*` build present and checked
                        for the property; found in all of them, the oldest being 2.1.205
    Needs:              jq, more than one installed extension build
    Docs:               https://code.claude.com/docs/en/memory. Documents the key but states no
                        minimum version, unlike several neighbouring behaviours on the same page
    Checkable:          automated

No lower bound was found, because the key predates the oldest build available to test. A version
gate for it would therefore never fire on any machine that can run the kit at all.

The schema sits next to the binary and declares what that build accepts, which makes it better
evidence than the documentation for questions of the form "does this version know this key". It
is not evidence of behaviour: it is a declaration of accepted input, and O10 is a case where its
prose describes the behaviour wrongly. Use it to date a key, and a probe to learn what the key
does.
