# Design

> **This is a decision record, not a user guide.** It is dense on purpose: it
> exists so that future changes know what they would be overturning. For how the
> kit behaves day to day, read [FLOWS.md](FLOWS.md). For setup, the README.

    Status:            Implemented
    Last revised:      2026-08-12
    Verified against:  Claude Code 2.1.222
    Supersedes:        (none)

The decisions that shaped this kit, and the incidents behind them. Without this file
that reasoning would live only in old conversations and commit messages.

## Memory

**Two tiers, split by what may leave the machine.** Global memory (`~/.claude/memory`)
holds project-agnostic preferences and syncs across machines. Mount memory
(`~/.claude/memory-mounts`) holds project facts and never syncs. The boundary is a
privacy line first and an architecture second. Everything below it can name projects
and paths. Everything above it must survive being pushed to a personal GitHub repo.

**The index is generated, never edited.** `MEMORY.md`, the file loaded into every
session, is rebuilt from the memory files on every prompt. Early on it was hand-edited,
and twice an entry silently vanished: once to a hook race, once to an automated rewrite.
A derived index cannot drift or lose entries, and any writer that corrupts it is undone
one prompt later.

**Memory files are What, then Why, then How, with no incident evidence inside.** A rule
states the preference, the generalized reason, and when it applies. The incident that
motivated it (quotes, repo names, file paths) stays in the miner tracker and git
history. The first design allowed a masked evidence section. Work-identifying names kept
riding in through that exception faster than they could be masked, so the leak surface
was removed structurally rather than policed.

**Authoring conventions are a write-time check, not seeded memory files.** They used to
ship as two memory files installed into the user's memory folder, because the commit lint
cannot reach memory-mounts and cannot shape behavior at write time. That diagnosis was
right and the delivery was wrong: it put kit instructions inside the user's data, where
they cost context in every session, could be edited into drift, needed an uninstall
decision, and still verified nothing. A `PreToolUse` hook on Write and Edit now checks a
memory file as it is written, anywhere, with no repo needed, and denies with the specific
rule that was missed. The guidance and template live in `guidance/`, versioned with the
kit, and the deny message points at them, so the advice arrives when it is needed instead
of sitting in context all day. This is the tooling-over-memory rule applied to the kit
itself.

**Only rules that hold for every legitimate file are enforced.** An audit of real memory
files set that boundary. Several correct rules carry their own "how" with no section
header, a `user_` profile has no `**Why:**` because it is not a rule, and a `[[wikilink]]`
may point at a memory not written yet. Denying any of those would make the check worse
than the drift it replaces, so they stay guidance, each with a test proving it is not
denied. Enforced: the type-prefixed filename, `name` equal to the filename slug (which
the harness's kebab-case default breaks, repeatedly, until this became mechanical), a
present `description` and `metadata.type`, a `**Why:**` on a `feedback_` rule, and no
Evidence section in the tier that syncs. An Edit shows only a fragment, so absence is
never judged from one.

## The daily feedback loop

**Started by your first session of the day, not by cron.** Running on session start
guarantees a working environment (auth, PATH). The miner reads "since the last
successful run", so idle days delay mining rather than losing messages. Cron would add
mining on days the machine sits unused, which buys nothing when nothing was said, and
costs a second environment to keep healthy.

**The window only advances on a verified write.** An early version advanced its
extraction window when the headless session exited zero. A session whose only write was
denied also exits zero, and a day of messages would have been skipped. Now the window
moves only after the tracker file is confirmed re-written. Related: the tracker lives
outside `~/.claude` because headless sessions cannot write inside it (sensitive-file
protection). That was discovered when the miner's first-ever write was silently blocked.

**Proposals die slowly, not instantly.** Rejection is two-strike. A rejected proposal
may resurface once, only on fresh evidence spanning several new days. A second
rejection, or an explicit "never", is final. A hard "never re-propose" fossilizes a snap
judgment made on thin evidence; unbounded re-proposal is nagging. One justified re-ask
is the compromise.

**The miner may not write absolutes from one-off remarks.** A single "no need, leave it"
is a judgment about one case, not a standing rule. Turning it into "never do X" is
dangerous precisely when X is a safety or cleanup action. Candidate rules must match the
strength of their evidence, and situational preferences become "ask first", not "never".
The review step caught the miner doing exactly this once, so the phrasing rule moved
upstream into the brief.

**Pings speak to both audiences.** Every notice is emitted twice in one JSON payload:
`systemMessage` for the human (a toast not every UI shows) and `additionalContext` for
the model, so Claude relays it in its first reply. The dual emission exists because the
toast-only version ran silently for weeks in a UI that never displayed it, and proposals
piled up unseen. Repeats are bounded by a once-per-session-per-day marker: resumes and
compactions of the same session stay silent, a new day re-notices (a week-long session
still hears about overdue reviews), and a missing session id fails open to the old
always-notice behavior.

**Review protocols are skills, not file headers.** The accept/reject protocol first
lived in the tracker's header, written once at file creation. After the third protocol
revision, live trackers still carried the first draft. A skill is versioned with the
kit, updated by `install.sh`, and invoked by the natural phrase. Interactive rituals
belong in skills; the miner's headless brief stays a prompt file.

## Guarding

**The guardrail is generic patterns plus a local denylist.** The built-in patterns catch
any home path, any email, and a mount section, so the hook itself carries no identifying
information and can be public. Employer names and other private terms come from an
untracked `denylist.local` or an environment variable. It runs as the memory repo's
pre-commit and enforces both leak-safety and the file conventions. Commit time is the
last moment before content becomes irreversible history.

The same hook also guards this repo's own checkout (`git config core.hooksPath
guardrail`), where it adds a style rule: no em-dashes on lines added to `README.md` or
`docs/*.md`. Code, tests, and memory files are outside the scope on purpose: only
reader-facing prose is checked, which leaves the rule with no exemptions to remember and
so nothing to drift.

**A blocked feature records why, and says so once a day.** The background work fails
quiet, because a hook cannot tell a machine that skips a feature from one that is broken,
and a warning at every session start becomes noise you learn to ignore. Quiet alone was
not enough though: a miner with no `claude` CLI used to exit before writing even a log
line, so months of no proposals looked exactly like months of nothing worth saving. Now
each feature records the reason it could not run, a notice fires once a day only after the
block has lasted three days (`MEMORY_KIT_HEALTH_GRACE`, which is a knob because the right
grace period depends on how often you open a session), and any successful run clears its own
record, so a fixed machine goes quiet without anyone dismissing anything. Set `MEMORY_KIT_NO_MINER=1` to
skip the miner deliberately, which is what makes every other silence a fault worth
reporting.

**Knobs live in a file, not in `settings.json`.** A `KEY=value` file at the deployed kit
root is the only mechanism that reaches every context the kit runs in: hooks, skill and
Bash-tool commands, the miner that a hook launches as a grandchild, and the guardrail that
git spawns. Environment variables cannot be relied on to reach all four, and
`settings.json` belongs to the orchestrator. The file is parsed, never sourced, so a stray
line in a hand-edited file cannot become code inside a hook. Precedence is the environment
variable, then the file, then the built-in default, which keeps every existing override
working. A malformed value falls back silently, because a typo must not break a session
start. The file also serves as the inventory: if a knob is not listed there, the kit does
not read it.

**The prefix is exact: `MEMORY_KIT_*` is a user knob, `CLAUDE_MEMORY_KIT_*` is not.**
The value is that a name answers "is this configurable" without anyone reading code to find
out. Getting there cost renaming three knobs that
already worked and one test seam. The objection to renaming was that a machine setting an
old name in a shell profile would go on being ignored in silence, which is the failure this
kit works hardest to prevent. That objection is answered rather than accepted. The
installer rewrites old keys inside a live config file, commented or not, so a file-based
setting migrates itself. The one place no installer can reach is an export in someone's
shell profile, so the health hook reports an old name by name, immediately rather than
after the usual grace period, since it is already being ignored and the fix is one edit
away.

Two checks keep the inventory honest alongside the prefix, because a convention that must
be remembered is weaker than a test that cannot be forgotten. One fails when the code reads
a knob `config.example` does not declare. The other fails when a machine's own config sets
a knob the code no longer reads. `CLAUDE_CONFIG_DENYLIST` stays outside all of this: the
guardrail is wired into other repos on its own, so its interface is not the kit's to rename.

**Sync failures are classified, not swallowed.** A pull that fails is sorted into
offline, refused credentials, or diverged history, because each one sends you somewhere
different. For refused credentials the message reads the repo's own configuration to name
the mechanism in use, whether that is an SSH key, a keychain, or a helper. That detection
only shapes the wording. Nothing in the kit checks for a credential tool or gates a sync
on one.

**What the kit may do to the memory repo, which it does not own.** `~/.claude/memory` is
the user's repo, and the kit reaches into it three ways: it writes the generated index, it
heals harness-stamped frontmatter, and it sets two git settings. The boundary that keeps
that honest has three parts. Nothing that git tracks is ever deleted, because staging a
deletion in someone's history is a commit for them to make; a file the kit once seeded is
removed only when it is still byte-identical to the copy the kit ships, so anything deleted
is reproducible from this tree, and when the repo tracks it the installer says so and names
the command instead. A rewrite is never silent, because a heal the user did not make would
otherwise surface as an unexplained change in `git status`, so the index pass names each
file it touched and what it dropped. And the two git settings, the guardrail `hooksPath`
and the `skip-worktree` flag on the generated index, are undone by `--uninstall`.

**Edit-over-Write.** A `PreToolUse` hook denies the `Write` tool on any existing file,
so every change lands as a reviewable diff. Memory used to tell the agent to prefer
Edit. Memory is advisory, and it was eventually ignored. The hook is not advisory.

## Code layout

**One accessor layer (`core/lib.sh`).** Every path into Claude Code internals
(transcript layout, session ids from hook stdin, binary and version discovery) and every
behavior shared by more than one script (notice markers, dual-audience emission, the
GNU/BSD `stat` shim) lives in a single sourceable file. The scripts stay thin. Before
the lib, the same logic existed in two or three slightly different copies (two binary
resolvers, three session-id parsers), and each harness change had to be found and fixed
per script. Functions fail quiet: empty and non-zero, never an error, so a harness
change degrades hooks to "no data" instead of breaking prompts.

## Installing and upgrading

**Deployment is a test-gated whole-tree copy.** The installer runs the fixture suite
first and refuses to deploy a tree the tests reject, so what ships is always a tested
snapshot. It then replaces `~/.claude/memory-kit` as one unit. Scripts, their core lib,
hooks, guardrail, and tests move together, so a script can never run against a stale
sibling. The earlier layout scattered loose script copies into a shared directory, which
drifted from the checkout four separate times during development. Run-in-place (hooks
pointing at the checkout) was considered and rejected: `git pull` would ship an untested
working tree straight into live sessions, where the gate makes that impossible. The
deployed tree also accumulates machine state (`.verified`, the private denylist) that a
redeploy deliberately preserves.

**Upgrades migrate, then merge.** Old-layout hook commands are re-pointed onto the tree
first, matched strictly by our script basenames so other tools' hooks in the same
directories are never touched. Then the normal append-and-dedup merge runs. Finally the
stale legacy copies (exactly ours, nothing else) are removed.

**The settings merge is append-only, deduped per hook, by script filename.** Merging by
deep-merge replaced other tools' hook arrays. Deduping by exact command string broke on
`$HOME` versus absolute-path spellings. Deduping per group (keyed on the group's first
hook) silently dropped any hook later added to an existing group, which meant upgrades
never delivered new hooks to installed machines. Each of those failures is a test now.

**Ownership is the basename and the directory, so a shared filename is not a collision.**
Deduping on the basename alone was wrong in both directions: any other tool shipping a
file of the same name could make us skip wiring our own hook, leaving a silently dead
kit, and then let an uninstall delete theirs. This kit renamed its own `version-check.sh`
once to dodge that, which was a workaround rather than a fix. A hook is ours only when
the basename is one we ship and its directory sits inside the deployed tree. Anything
else using one of our names is left alone and reported, because silence there looks like
a bug in us. The managed list is derived from `settings.snippet.json`, so adding a hook
is one edit and both halves see it.

**Uninstall is the same contract in reverse, and `settings.json` is treated as shared.**
The kit writes hooks, so it removes them: a tool that adds to a file it shares and cannot
take its own additions back out leaves the user no undo except editing by hand. Four
properties make writing a file every other tool shares survivable: it is written last, after everything else has installed, so a run
that fails earlier never touches it; the result is validated before it replaces the live
file, where wiring must not shrink the hook count and removal must leave every hook that
was not ours untouched; the merge runs against a snapshot and refuses if the live file
changed underneath, since Claude Code and other installers write it too; and a failure
after the write is rolled back from a kit-specific backup, or by deleting a file that did
not exist beforehand. Removal prunes upward, dropping emptied groups, then events, then
the `hooks` key.

**The shape check covers the events we wire, not every event in the file.** A
`settings.json` that parses can still hold a shape the merge cannot use, and finding that
out mid-merge meant a raw parser error at the end of a half-finished install, so a
preflight now refuses first. The first version of it checked every event in the file,
which was too wide. An event this kit never wires belongs to some other tool: the merge
only reads the keys `settings.snippet.json` declares, so a wrong-typed foreign event
survives an install and an uninstall untouched, and refusing over it was judging config we
did not write. The list of events comes from the snippet, so wiring a new one cannot forget
to widen the check. Two things are still refused: `hooks` itself being the wrong type,
because that is the container we have to write into rather than someone else's key, and an
event of ours holding anything that is not a hook group. Nothing is ever repaired
automatically.

**Uninstall undoes what install did outside its own tree, and nothing else.** Deleting
the tree while the memory repo's `core.hooksPath` still pointed into it would leave git
finding no hook and running nothing, so the commit guard would stop silently while the
repo still looked configured. That is the worst failure available here, so uninstall
unsets it, and only when it points at our tree. It also clears the `skip-worktree` flag
that hid `MEMORY.md`. Memory files are never touched. The miner's tracker is kept by
default because its rejection history is what stops a reinstall re-proposing what you
refused; two flags remove it, and both say what they are deleting.

## Self-verification

**Two suites with opposite premises.** `tests/run.sh` is the gate: fixtures in throwaway
directories, runs everywhere, asserts exact outcomes. It can only confirm what its
author believed the data looks like. `tests/smoke.sh` is the reality check: no fixtures,
real transcripts and settings on the machine at hand, every check an invariant
("whatever the answer is, it must have this shape"), skipping where data does not exist.
Its first two runs caught a real extractor leak (a truncated injected block with no
closing tag) and the group-dedup upgrade bug. Both were invisible to the fixture suite.
Both lived in the gap between belief and disk.

**The version stamp closes the loop.** The kit parses undocumented Claude Code
internals, so a harness update can silently break it. A clean smoke pass stamps the
current Claude Code version into `.verified` (machine-local). A SessionStart hook
compares the stamp to the running version and re-runs the suite when they differ, once
per version per day, in the background. On failure nothing is stamped and the log holds
the receipt: the missing write is the report. A warning that fired on every update,
already-checked or not, would be ignored within a month.

```mermaid
flowchart LR
    A[SessionStart] --> B{running version<br/>== .verified?}
    B -->|yes| C[silent, done]
    B -->|no| D{already attempted<br/>this version today?}
    D -->|yes| C
    D -->|no| E[run smoke.sh<br/>backgrounded, quiet]
    E -->|all pass| F[stamp .verified<br/>= running version]
    E -->|any fail| G[no stamp,<br/>.smoke-last.log holds the receipt]
    F --> C
```
