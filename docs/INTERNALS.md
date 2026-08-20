# Claude Code internals, as observed

> **This file is about Claude Code, not about this kit.** It records what was observed about
> undocumented behaviour the kit depends on. The decisions those observations drove live in the
> `DESIGN-*.md` records, which cite these by number. For how the kit behaves, read
> [FLOWS.md](FLOWS.md).

    Observed against:   Claude Code 2.1.222 (O1–O7) · 2.1.228 (O8–O12) · 2.1.234 (O13–O17)
    Platform:           macOS, VS Code extension
    Last re-verified:   2026-08-12 (O1–O7) · 2026-08-13 (O8–O12) · 2026-08-19 (O13–O17)
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

O5 has since been re-verified and now carries a date, a version and the exact refusal message, so
only its first sighting is undated. O6 is still the weakest entry in the file.

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

### O5. A write inside `~/.claude` is a sensitive-file edit, so it needs permission

    First observed:     not recorded
    Re-verified:        2026-08-13 · 2.1.228
    Surface:            `~/.claude` itself
    How:                one headless session with `--allowedTools Write`, asked to write two
                        files. The write outside `~/.claude` succeeded. The write to
                        `~/.claude/<probe>.txt` was refused with "Claude requested permissions to
                        edit <path> which is a sensitive file". A headless session has nobody to
                        ask, so the write never lands
    Needs:              an installed Claude Code, a headless session
    Docs:               not documented
    Checkable:          automated, but not hermetic: it has to probe the real config root,
                        because a fake HOME cannot authenticate and fails as "Not logged in"
                        before reaching any write

This is why the miner's tracker lives at `~/.local/share/claude-feedback` rather than beside the
kit.

**The original wording said a headless session cannot write inside `~/.claude`. That is nearly
right, and the mechanism is worth having exactly.** The path is not forbidden. It is classified
sensitive, which turns the write into a permission request, and a headless session has no way to
answer one. An interactive session writes there constantly, since that is where every memory file
comes from, so the boundary is the permission prompt rather than the directory.

**Not tested: whether a permission bypass or an explicit allow rule gets a headless session
through.** It probably does, and the kit deliberately does not rely on it. Driving a rewrite of
someone's memory from a headless session with permissions bypassed removes the one thing that
makes the operation safe, which is a person watching it happen.

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
exist on the machine this was observed on, with the kit's symlink in the unread one.

The same sanitizer applies to the transcript directory, not only the memory one: on that machine
the dot-collapsed spelling is the directory that holds real session data, and the kit's spelling
holds nothing but the symlink.

**What the harness-spelled directory holds at any moment was not pinned down**, and an earlier
draft of this entry overstated it. A `memory` directory was observed there once and was absent
about an hour later with no session having run in between, which suggests it is created on demand
rather than kept. The consequence does not rest on that: the kit's symlink is in the directory
Claude Code does not read for memory, so the project does not get the central store either way.

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

## The plugin surface

### O13. A marketplace is a git clone, independent of your working checkout

    First observed:     2026-08-19 · 2.1.234
    Surface:            ~/.claude/plugins/marketplaces/<name>/
    How:                `git -C ~/.claude/plugins/marketplaces/memory-kit remote get-url origin`
                        returns this repo; the directory holds `.claude-plugin/marketplace.json`
    Needs:              git
    Checkable:          automated

`plugin marketplace add <owner>/<repo>` clones the repo and reads which plugins it offers from
that clone. It is a registry pointing at git sources, not a store and not an updater. The clone
is a second copy of the same repo, so `/plugin update` refreshes it and never touches your
checkout, and `git pull` in your checkout never touches the plugin. Two stale states, unrelated,
which is why the installer reports them on separate lines.

### O14. The plugin cache is keyed by the version in plugin.json

    First observed:     2026-08-18 · 2.1.234
    Surface:            ~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/
    How:                ponytail cached as `4.8.4` and dev-pipeline as `0.1.0`, both declaring a
                        version; caveman cached as `0d95a81d35a9`, and its plugin.json has no
                        version field
    Needs:              nothing
    Checkable:          automated

Omit `version` and the cache is keyed by commit SHA instead, which makes "which version is
installed" unanswerable and gives `/plugin update` no version change to react to. It is also why
this kit's changelog test pins plugin.json to the newest released heading: the field has to be
tracked by hand, so it lies the first time a release ships without a bump.

### O15. Nothing runs at plugin install; hooks are the only execution surface

    First observed:     2026-08-18 · 2.1.234
    Surface:            plugin install, and plugin-declared hooks
    How:                installing a plugin clones and reads the manifest, with no shell step;
                        a plugin that declares `hooks` has its commands run on session events,
                        which is how caveman and ponytail activate
    Needs:              nothing
    Checkable:          needs a live session

A plugin can execute arbitrary commands, but only on a hook event, never during install. So the
plugin cannot run install.sh for the half it does not ship, and the two-step install is a
property of the platform rather than a choice. It is also what this kit's own plugin-declared
SessionStart hook relies on: the only way to report a missing kit tree is to run at session
start. `plugin install --help` refers to "a plugin installed by running a marketplace-declared
command", so some install-command path exists; the `$schema` URL in marketplace.json returns a
404 page, none of the marketplaces installed here declare such a field, and its shape is
unverified.

### O16. Removing a marketplace disables its plugin and orphans the cache

    First observed:     2026-08-19 · 2.1.234
    Surface:            settings.json and the plugin cache
    How:                in a sandbox HOME: after install, one marketplace and one enabled plugin;
                        `plugin uninstall` left the marketplace (mkt=1 plugin=0); `plugin
                        marketplace remove` left neither (mkt=0 plugin=0) with the cache directory
                        still on disk
    Needs:              jq
    Checkable:          automated

So "plugin installed without its marketplace" is not a reachable state, which is why the
installer's state check treats `enabledPlugins` as authoritative and reads the marketplace only
to tell "nothing installed" from "one command left". An orphaned cache directory is not evidence
of an installed plugin.

### O17. `plugin install` cannot pin a version or ref

    First observed:     2026-08-18 · 2.1.234
    Surface:            plugin install, plugin marketplace add
    How:                `--help` on both: install takes `--config`, `--scope`, `--yes`; marketplace
                        add takes `--scope`, `--sparse`. Neither accepts a ref, tag or version
    Needs:              nothing
    Checkable:          automated

The marketplace clone tracks the repo's default branch, so a release tag cannot change what the
plugin path delivers. `plugin tag` creates a `<name>--v<version>` tag and validates that
plugin.json agrees with the marketplace entry, but nothing on the install side consumes that tag.

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
