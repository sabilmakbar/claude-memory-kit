# Claude Code internals, as observed

> **This file is about Claude Code, not about this kit.** It records what was observed about
> undocumented behaviour the kit depends on. The decisions those observations drove live in the
> `DESIGN-*.md` records, which cite these by number. For how the kit behaves, read
> [FLOWS.md](FLOWS.md).

    Observed against:   Claude Code 2.1.222 (O1–O7) · 2.1.228 (O8–O12) · 2.1.234 (O13–O19, O21)
                        2.1.237 (O20) · 2.0.0 through 2.1.246, every published build (O22–O23)
                        2.1.74 through 2.1.246, seven probes by hand (O24) · 2.1.246 (O25–O27)
    Platform:           macOS, VS Code extension
    Last re-verified:   2026-08-12 (O1–O7) · 2026-08-13 (O8–O12) · 2026-08-19 (O13–O17, O21)
                        2026-08-20 (O18–O20) · 2026-08-26 (O18, O22–O27)
    Needs to re-run:    jq, find, a machine with an installed Claude Code; O22 through O24
                        need only npm and grep, and run on any machine; O25 and O27 need the
                        claude CLI and a throwaway HOME, O26 only git

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

### O22. `autoMemoryDirectory` first appears in the published build 2.1.74

    First observed:     2026-08-26 · 2.1.74 through 2.1.246
    Surface:            published npm package
    How:                binary search over the 495 published versions of
                        `@anthropic-ai/claude-code`, installing each into a temporary prefix
                        and reading the shipped executable with `grep -a`; seven probes, and a
                        control string matched none of the same builds
    Needs:              npm, grep
    Checkable:          automated (`tests/version-probe.sh <version>`)
    Supersedes:         O12, which reported no lower bound because the oldest build on that
                        machine was 2.1.205

2.1.73 is the last build without it, so the key is 107 published builds older than the
previous floor suggested. O12 was not wrong: it recorded honestly that no lower bound could be
found from the builds installed on one machine. The registry holds every build, so the question
it left open is answerable by anyone.

**This is a different surface from O12, and weaker.** The extension ships
`claude-code-settings.schema.json`, which declares what that build accepts. The npm package
ships one compiled executable instead, so this reads a string out of it. Finding the string
shows the build carries the name, not that it honours the key. Absence is the strong signal,
which is the direction the automated check relies on.

### O23. Published builds carry the hook event names the installer writes

    First observed:     2026-08-26 · 2.1.74 through 2.1.246
    Surface:            published npm package
    How:                same probe as O22; `PreToolUse`, `SessionStart` and `UserPromptSubmit`
                        each found with `grep -a`, and a control string found in none
    Needs:              npm, grep
    Checkable:          automated (`tests/version-probe.sh <version>`)

`install.sh` keys its hooks by these names, and a build that renamed one would not error. The
hooks would be wired and never fire, so the kit would go quiet rather than break, which is the
failure that takes longest to notice. The names are in every build back to the O22 floor.

### O24. The plugin mechanism first appears in the published build 2.1.75

    First observed:     2026-08-26 · 2.1.75 through 2.1.246
    Surface:            published npm package
    How:                same binary search as O22, seven probes, looking for
                        `extraKnownMarketplaces`; 2.1.74 is the last build without it
    Needs:              npm, grep
    Checkable:          manual. `tests/version-probe.sh` does not look for
                        `extraKnownMarketplaces`, so no row in the index speaks to
                        this boundary

One version after the setting in O22, which is why `install.sh` can carry a single floor rather
than two. The kit needs both: the setting to point auto memory at one store, and the plugin
mechanism to deliver the skills. 2.1.75 is the oldest build that has them together, and it is the
installer's floor. Being the higher of the two, it is also the number that decides every
refusal, and the weekly probe does not re-check it: this floor rests on the bisect above
rather than on the index.

The same caveat as O22 applies, and harder here. A build carrying the marketplace key is not
proof that `claude plugin install` behaves as it does today; it dates the mechanism rather than
describing it.

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

### O21. A marketplace is a registry entry; a remote source is cloned, a path is not

    First observed:     2026-08-19 · 2.1.234
    Surface:            ~/.claude/plugins/marketplaces/<name>/
    How:                `git -C ~/.claude/plugins/marketplaces/memory-kit remote get-url origin`
                        returns this repo; the directory holds `.claude-plugin/marketplace.json`
    Needs:              git
    Checkable:          automated

`plugin marketplace add` records the source in `extraKnownMarketplaces` and reads which plugins
it offers. It is a registry pointing at sources, not a store and not an updater.

**How it is stored depends on the source.** `add <owner>/<repo>` clones into
`~/.claude/plugins/marketplaces/<name>/`, which is a second copy of the repo: `/plugin update`
refreshes that clone and never touches your checkout, and `git pull` in your checkout never
touches the plugin. Two stale states, unrelated, which is why the installer reports them on
separate lines. `add <path>` creates no clone and references the directory in place, so there the
marketplace tracks whatever that working tree holds, including an unmerged branch. An earlier
version of this entry claimed the clone unconditionally; it was written from a GitHub-sourced
install and only checked against one.

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

`plugin tag` creates a `<name>--v<version>` tag and validates that plugin.json agrees with the
marketplace entry, but nothing on the install side consumes that tag.

**Superseded by O25 on the part that matters.** This record concluded that the marketplace clone
tracks the default branch and a release tag therefore cannot change what the plugin path
delivers. The first half is the default, not a limit: the ref rides in the source string rather
than in a flag, so `--help` could not show it and reading `--help` alone was not enough.

### O25. A plugin source pins to a tag through the source string, not through a flag

    First observed:     2026-08-26 · 2.1.246
    Surface:            plugin marketplace add, settings.json, the plugin cache
    How:                in a throwaway HOME, `marketplace add sabilmakbar/claude-memory-kit@v0.3.0`
                        then `plugin install`: the cache directory came out `0.3.0` while the
                        default branch declares 0.3.2, so the ref decided the content. The
                        source schema was also read out of the binary with `grep -a`
    Needs:              the claude CLI, jq
    Checkable:          manual (needs a throwaway HOME; nothing here scripts a marketplace)
    Supersedes:         O17, which read `--help` on both commands, found no ref flag, and
                        concluded that a release tag could not change what the plugin delivers

The schema shipped inside the binary carries `ref`, described as "Git branch or tag to use (e.g.
\"main\", \"v1.0.0\"). Defaults to repository default branch.", and an optional `sha`, "Specific
commit SHA to use". The pin is enforced rather than advisory: `sha_pin_mismatch` sits beside
"Failed to checkout commit" as a real failure path. Source types are `npm`, `url`, `github`,
`git-subdir`, `archive`, `command`, plus `local` and `git`.

Three forms, all tested:

| form | result |
|---|---|
| `owner/repo@v0.3.0` | pins; clone at a detached HEAD, cache named from the tag |
| `https://github.com/owner/repo.git#v0.3.0` | pins, same |
| `https://github.com/owner/repo.git@v0.3.0` | fails; git is handed the whole string as a repository name |

The `@` form works on the owner/repo shorthand and not on a URL, which is worth knowing because
the failure names a repository nobody typed.

The pin persists into `extraKnownMarketplaces` in `settings.json` and into
`plugins/known_marketplaces.json`, both as `{"source":"github","repo":...,"ref":"v0.3.0"}`.
Moving it is a re-add: `marketplace add ...@v0.3.1` rewrote the ref, after which `plugin update`
reported "updated from 0.3.0 to 0.3.1". While pinned, `plugin update` refuses to go past the pin
and answers "already at the latest version", which is the pin working rather than a failure.

The pin only counts when `marketplace add` writes it. Adding a `ref` by hand to an
already-materialised entry in `settings.json` is ignored: `plugins/known_marketplaces.json`
keeps the old source, `marketplace update` re-fetches the default branch, and `plugin update`
declines. The re-add is the only pin that takes.

### O27. `plugin update` compares version labels, never content

    First observed:     2026-08-26 · 2.1.246
    Surface:            plugin update, plugin uninstall, the plugin cache
    How:                in a throwaway HOME with a `directory` marketplace pointed at a clone:
                        edited a skill in the tree, `plugin update` answered "already at the
                        latest version" and the edit was absent from the cache copy while
                        present in the tree; `plugin uninstall` then `plugin install` refreshed
                        the same cache directory in place; bumping plugin.json in the tree made
                        `plugin update` pull into a new directory
    Needs:              the claude CLI, git
    Checkable:          manual (needs a throwaway HOME)

The update decision reads the two version labels and stops there. Content that changes under an
unchanged label never propagates: an unpinned user mid-cycle stays on whatever the branch held
when their label last moved, and a contributor's skill edits never reach the loaded copy, even
though a `directory` marketplace reads the tree in place, because the harness loads the cache
copy rather than the marketplace (O14).

Two refresh paths work. Reinstalling under the same label rewrites the cache directory in place,
which with O19's "uninstall keeps the cache" makes `plugin uninstall` then `plugin install` the
development loop for skills. Bumping the label pulls into a new directory, which works but
leaves a directory per bump behind. CONTRIBUTING.md carries the loop.

### O26. Unpinned, the plugin cache is labelled with a version that was never released

    First observed:     2026-08-26 · 2.1.246
    Surface:            the plugin cache
    How:                compared `~/.claude/plugins/cache/memory-kit/memory-kit/0.3.1` against
                        `git archive v0.3.1`: 7 files differ, including `install.sh` and
                        `tests/run.sh`, and the directory's mtime is 4 hours older than the tag
                        itself. Control: the same comparison against v0.3.0 differs in 15
    Needs:              git
    Checkable:          automated

The cache is keyed by plugin.json's version (O14), the marketplace serves the default branch, and
plugin.json carries the next release's number for the whole of a development cycle. So an add
performed mid-cycle files the default branch's content under a number that has not shipped, and
the number stays on that directory afterwards.

Any static label inside a moving branch mislabels; when the bump happens only decides which
number is wrong. Bumping at release instead would put the same lie on an already-published
number, which is worse. Pinning the source is what makes the label true (O25), and this is why
`install.sh` compares the plugin against the pin or the newest release rather than against the
version in this checkout.

### O18. `marketplace add` and `plugin install` are a lookup, not a chain

    First observed:     2026-08-20 · 2.1.234
    Surface:            plugin marketplace add, plugin install
    How:                in a sandbox HOME, `marketplace add <path>` alone left
                        `extraKnownMarketplaces` at 1 with `enabledPlugins` at 0 and no cache
                        directory; `plugin install memory-kit@memory-kit` with no marketplace
                        added failed with "not found in marketplace"; `plugin install <path>`
                        failed with "not found in any configured marketplace". Re-verified
                        2026-08-26 from the other side: `extraKnownMarketplaces` written by
                        hand left `marketplace update` reporting "Available marketplaces: "
                        empty, with no clone on disk
    Needs:              jq
    Checkable:          automated

Neither command runs the other. `add` writes the registry and installs nothing; `install` only
resolves names inside registries already configured, and will not take a repo or path to
bootstrap itself. `plugin@marketplace` is a lookup key, not a source. That is why both commands
appear in every install instruction, and why the installer distinguishes "nothing installed" from
"one command left".

Writing the settings key by hand is therefore not an install path. The entry becomes a real
marketplace only once something reconciles it into `plugins/known_marketplaces.json` with a
clone, which happens when a session starts, not when a `plugin` subcommand runs. Until then
`plugin install` reports the plugin missing and `marketplace update` lists no marketplaces at
all. `marketplace add` does both halves in one step, which is why the install instructions name
it rather than a settings edit.

Refreshing has two rungs, and they are separate commands: `marketplace update [name]` re-fetches
the registry clone, so a newly published plugin becomes visible, while `plugin update
<plugin>@<marketplace>` moves an installed plugin to what that clone now offers. For a
single-plugin marketplace the first rarely matters, because the plugin list never changes. The
failure message for a missing plugin points at `marketplace update`, not at `add`.

### O19. Nothing removes a plugin's cache, and removal order decides whether you can

    First observed:     2026-08-20 · 2.1.234
    Surface:            plugins/cache, plugin uninstall, marketplace remove, plugin prune
    How:                in a sandbox HOME: after install, cache=1. `plugin uninstall` left
                        cache=1. `plugin marketplace remove` left cache=1. `plugin prune`
                        answered "Nothing to prune (no auto-installed plugins at user scope)".
                        Removing the marketplace first made `plugin uninstall` fail with
                        "Plugin not found", leaving the cache with no command able to remove it
    Needs:              jq
    Checkable:          automated

Two consequences. Cache directories accumulate and are only ever cleaned by hand; `prune` is for
auto-installed dependencies, not for orphans. And uninstall has a required order: take the plugin
out before the marketplace, because `uninstall` resolves the plugin through the registry and
cannot find it once the registry entry is gone. Reversing the order is not recoverable through
the CLI, which is why this kit's uninstall documentation states the order rather than listing the
commands in either order.

### O20. The VS Code extension installs plugins by command and URI, not by a slash command

    First observed:     2026-08-20 · extension 2.1.237
    Re-verified:        2026-08-26 · CLI 2.1.246, interactive session and `-p`
    Surface:            the extension manifest and bundle
    How:                `claude-vscode.installPlugin` is one of the 23 declared commands, titled
                        "Claude Code: Install Plugin" and gated on `claude-vscode.updateSupported`.
                        The bundle registers a URI handler whose `/install-plugin` path reads
                        `plugin` and `marketplace` query parameters and defaults the marketplace to
                        `anthropics/claude-plugins-official`. Typing `/plugin` in a session here
                        answers "isn't available in this environment". That string is absent from
                        the extension bundle and present in the native binary, as is the literal
                        `"/plugin"`, so the gate is in the CLI layer and not in the extension
    Needs:              jq, grep over a 302MB binary
    Checkable:          automated

So `/plugin` is real and gated by host and by mode. **Settled 2026-08-26 on 2.1.246 by typing
it:** an interactive CLI session provides the command, this extension answers "isn't available in
this environment", and `claude -p "/plugin"` does not resolve it either. So the earlier reading,
implemented and gated rather than absent, was right, and the gate is not only about the extension:
headless mode does not carry it. The docs still lead with `claude plugin update`, because that form
works in every host, including `-p` and any wrapper that shells out.

**The distinction worth keeping:** the command is not missing from the product, it is unavailable
in this environment. Both the `"/plugin"` literal and the refusal message live in the same binary.
Finding a string was never proof that it is a registered command, which is why this was recorded as
a reading rather than a finding until someone typed it. Typing it is what closed it, and the result
split three ways rather than two, so "which host" was the wrong question: the same binary answers
differently interactively and under `-p`.

`/install-plugin` is a deep-link path, not a chat command, and the two are easy to conflate from a
grep alone.

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
gate for it would therefore never fire on any machine that can run the kit at all. O22 found that
bound by going to the registry rather than to one machine: 2.1.74.

The schema sits next to the binary and declares what that build accepts, which makes it better
evidence than the documentation for questions of the form "does this version know this key". It
is not evidence of behaviour: it is a declaration of accepted input, and O10 is a case where its
prose describes the behaviour wrongly. Use it to date a key, and a probe to learn what the key
does.
