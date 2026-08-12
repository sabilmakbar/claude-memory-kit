# Claude Memory Kit

[![tests](https://github.com/sabilmakbar/claude-memory-kit/actions/workflows/tests.yml/badge.svg)](https://github.com/sabilmakbar/claude-memory-kit/actions/workflows/tests.yml)

Claude Code forgets you between sessions. Preferences you explain on Monday are gone by
Wednesday, and nothing you teach it survives a new laptop. This kit fixes that. It keeps
your preferences as small files that load into every session, backs them up to a private
repo if you want, and once a day it notices the corrections you keep repeating and offers
to remember them for you.

Everything runs on your machine, and nothing is saved without your approval.

Three docs form the reading path, shortest first. New here?
[HOW-IT-WORKS.md](docs/HOW-IT-WORKS.md) explains the daily loop in plain language, and it is
the only one you need in order to use the kit. [FLOWS.md](docs/FLOWS.md) is the next step
down: diagrams of what runs when, with the specifics the plain-language version leaves out.
[DESIGN.md](docs/DESIGN.md) is for anyone changing the kit rather than running it: every rule
in the code with the reason it exists.

If something is broken rather than unclear, go straight to
[TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md).

## What you get

- Preferences that stick. Each one is a small text file, loaded into every session, on
  every machine you sync.
- A safety net for your privacy. If you back memories up to GitHub, a commit check blocks
  emails, machine paths, and any private terms you list before they can leave the machine.
- A daily suggestion loop. Claude reads what you typed yesterday, spots the corrections
  you keep making, and proposes them as permanent preferences. You accept or reject each
  one.

It works anywhere you run Claude Code on a machine you control: the CLI, the desktop app,
or an IDE extension. It cannot help web-only sessions on claude.ai.

## Install

**Read this first: the installer edits `~/.claude/settings.json`.** That file is your global
Claude Code config, shared with every other tool you have installed. The kit writes to it
because registering a hook is the only way the memory index can rebuild itself on every
prompt.

Two things make that safe, and neither is good intentions. The test suite runs first and refuses
to install if anything fails. Then, before anything at all is deployed, your file is checked: if
it cannot be parsed, or if the part the kit merges into is not the shape it expects, the run
stops and names the key to fix, with nothing installed and your file untouched. Past that point
the merge only ever adds. A second run adds nothing, settings unrelated to hooks survive, a hook
belonging to another tool is reported rather than claimed, an event the kit does not wire is
never even read, and a run that fails later puts the previous contents back. Add `--dry-run` to
see the plan before any of it happens.

[DESIGN.md](docs/DESIGN.md) says why each of those rules exists, including why the shape check
deliberately stops at the events this kit wires rather than judging the rest of your file.

You need `jq`. The miner and sync also use `git` and the `claude` CLI. Details in
[DEPENDENCIES.md](docs/DEPENDENCIES.md).

```bash
git clone https://github.com/sabilmakbar/claude-memory-kit.git ~/claude-memory-kit
~/claude-memory-kit/install.sh
```

The installer runs its own test suite first and refuses to install if anything fails.
It then places the kit in `~/.claude/memory-kit`, adds its hooks to your Claude Code
settings without touching hooks from other tools, and keeps any memory files you already
have. Re-running it is always safe, and is also how you upgrade (see below).

Start a new Claude Code session, then confirm the index got built:

```
$ head -3 ~/.claude/memory/MEMORY.md
# Memory Index
> Two-tier system: global memories always load; mount-specific appear in "## Mount:" section below.
> Write global preferences/feedback to ~/.claude/memory/; write filesystem/project-specific memories to ~/.claude/memory-mounts/<encoded-mount>/ (mount path with `/` replaced by `-`).
```

Below those lines you get one entry per memory file you have. The index is regenerated on
every prompt, so if the file is missing or empty after a fresh session, the hooks did not
run and nothing else will work either.

If you had memories before installing, run `/review-memories` once. It finds files the
index cannot see yet and proposes the small renames that fix them.

## What you will notice day to day

Session starts may greet you with a short note: a reminder that a memory review is due,
that the daily loop found something worth keeping, or that some part of the kit has been
unable to run for three days or more. Say "review feedback proposals"
and Claude walks you through each suggestion. Say "remember this" at any time to save a
preference directly, no review needed. That is the whole interface.

## Keep your memories in a private git repo (recommended)

Do this unless you have a reason not to. Memories are small text files you accumulate
slowly, and they are the one part of this setup you cannot regenerate. Behind a private
repo, a dead laptop costs you nothing and a new machine starts already knowing what you
have taught Claude. Skip it only if one machine is all you use and you are willing to
lose the files.

**Before your first commit, tell the guardrail which terms are yours.** It already blocks
generic PII on its own: any email address, any home directory path. What it cannot guess
is the PII specific to you, such as your employer, your client or project names, and any
handle you go by. Put those terms in `~/.claude/memory-kit/guardrail/denylist.local`.
This has to happen before the first commit, not the first push: the guardrail runs at
commit time, and once something is committed it is in history whether you push it or not.

### First machine: create the repo

The easy path is the
[claude-memories-template](https://github.com/sabilmakbar/claude-memories-template):

1. Click "Use this template".
2. Make the repo **private**.
3. Clone it to `~/.claude/memory`.
4. Re-run `~/claude-memory-kit/install.sh`. This is the step that wires the guardrail
   into the new repo, so do not skip it.

<details>
<summary>Or turn an existing memory folder into the repo</summary>

Create the empty private repo on GitHub first, then:

```bash
cd ~/.claude/memory
git init
~/claude-memory-kit/install.sh               # wires the guardrail into the repo you just created
git add . && git commit -m "Initial memory"  # now genuinely vetted
git remote add origin https://github.com/<your-user>/claude-memories.git
git push -u origin main
```

Run `install.sh` between `git init` and the first commit. That commit carries everything
you have accumulated unchecked, so it is the one that most needs vetting.

With the GitHub CLI installed, `gh repo create <your-user>/claude-memories --private
--source . --push` replaces the last two lines and creates the repo for you.
</details>

### Every other machine: join the repo you already have

Never create a second repo. Two repos means two memories that disagree, and nothing to
reconcile them.

```bash
mv ~/.claude/memory ~/.claude/memory.local-backup    # keep what this machine learned
git clone <your-memories-repo> ~/.claude/memory
~/claude-memory-kit/install.sh                       # wires the guardrail into the clone
```

Copy anything worth keeping out of the backup, commit it, then delete the backup. From
then on, plain `git pull` and `git push` in `~/.claude/memory` is how your machines share
what they learn.

### Finish the setup on each machine

If the repo carries a global `CLAUDE.md` (the template ships one), link it so Claude
loads it:

```bash
ln -sfn ~/.claude/memory/CLAUDE.md ~/.claude/CLAUDE.md
```

Give the repo its own commit identity, so memory commits are attributed to you rather
than to whatever account this machine's git defaults to:

```bash
git -C ~/.claude/memory config user.name  "<your name>"
git -C ~/.claude/memory config user.email "<your personal email>"
```

The guardrail cannot do this one for you. It reads the lines you commit, and the author
identity is not one of them.

### If a push is rejected, or commits land under the wrong account

These look alike but they are two different problems, and a machine signed into a work
account causes both.

**Commits under the wrong name** is the commit identity step above. Set `user.name` and
`user.email` on the repo and everything from then on is attributed correctly. Commits
already made keep their original author; rewriting them is possible and rarely worth it
on a private memory repo.

**A rejected push** is authentication, and the fix depends on how this machine talks to
GitHub, so there is no single command to give you. The goal is the same whichever method
you use: the memory repo authenticates as the account that owns it, independently of
whatever this machine defaults to.

- **SSH:** the repo needs a key belonging to the personal account, and ssh has to offer
  only that key for this remote. A machine holding several keys otherwise authenticates
  as whichever one GitHub accepts first, and the push succeeds as the wrong account
  rather than failing.
- **HTTPS, whether through the GitHub CLI or a keychain:** the stored credential the repo
  uses has to belong to the personal account. Most credential stores key on the hostname
  alone, so two accounts on github.com collide and whichever was saved first wins.

When a sync fails, the kit's own message names the mechanism your repo is configured
with, which tells you where to look.

## Upgrading

Re-run the installer. That is the whole upgrade path:

```bash
git -C ~/claude-memory-kit pull && ~/claude-memory-kit/install.sh
```

It runs the test suite first and refuses to deploy a tree the tests reject. Then it replaces
kit code only, and carries the rest forward:

| Kept as it is | Why it survives |
|---|---|
| your memory files | the installer only ever adds the two convention seeds, never overwrites |
| `guardrail/denylist.local` | the guardrail folder is overlaid, never wiped |
| your edited `config` | seeded once; later installs refresh `config.example` only |
| other tools' hooks in `settings.json` | the hook merge is append-only and deduped per hook |

Two things it does rather than just preserve. A knob that has been renamed since your last
install gets rewritten in place in your `config`, keeping its value, and it tells you when it
does. And `config.example` is refreshed every time, so knobs added since your last upgrade
show up there with their defaults.

## Is it working?

If something seems off, or Claude Code has just updated itself, run the smoke suite. It
checks the installed kit against this machine's real data rather than against fixtures:

```
$ bash ~/.claude/memory-kit/tests/smoke.sh
syntax (tested on bash 3.2.57(1)-release):
  ✓ all entrypoints parse
extract-user-messages.sh (real transcripts, 7-day window):
  ✓ block headers have [project/session timestamp] shape (441 msgs)
...
smoke: 25 passed, 0 failed, 1 skipped
smoke: stamped .verified = 2.1.222
```

`0 failed` is the answer you want. A skip is normal and means a check had nothing on this
machine to run against. The last line records which Claude Code version the kit has been
checked against here, and it is what the daily version check compares against.

There is nothing to redact before sharing this. The output is check names, counts, and version
strings, plus the name of the credential helper your memory repo uses if you sync one. No
memory file names, no memory contents, no paths, no username. Paste it as it is.

## How it stays trustworthy

Two test suites cover the kit: a fixture suite that gates every install and every push,
and a smoke suite that checks the kit against your machine's real data. After a Claude
Code update, a background hook re-runs the smoke suite and records the result, so a
harness change that breaks something gets noticed instead of failing silently. The full
story is in [DESIGN.md](docs/DESIGN.md).

Verified against Claude Code 2.1.222. The smoke suite also passes over transcripts written
by 20 versions, 2.1.177 through 2.1.222. Older versions are untested.

## FAQ

**Does this conflict with MCP servers?** No. The kit is built from ordinary lifecycle
hooks and plain files, and registers no MCP surface. One caveat: running a
memory-flavored MCP server alongside it gives you two memories that can disagree. Pick
one.

**Does it conflict with Claude Code's built-in memory?** No, it *is* the built-in
per-project memory, redirected to one central folder and given a generated index. If
Claude Code reshapes its memory layout, the kit needs a patch, and the version check
exists to surface exactly that.

**Can I turn the daily miner off on one machine?** Uncomment `MEMORY_KIT_NO_MINER=1` in
`~/.claude/memory-kit/config`. Memory, the index, and the guardrail carry on. Saying it
explicitly matters, because the kit treats a feature that has been silent for three days as
a fault and tells you about it once a day. That file holds every setting the kit has, each
one listed with its default, and your edits survive upgrades. `MEMORY_KIT_HEALTH_GRACE` is
the three, if you want a longer fuse on a machine you use rarely.

**What does the daily miner cost?** One Claude call a day, on Sonnet by default. It reads
what you typed since the last run plus your memory files and global `CLAUDE.md`, which on
a mature setup is roughly 25,000 input tokens and a couple of thousand out. It runs
through your own Claude account, so on a subscription plan that is a small slice of your
daily usage rather than a separate bill; on an API key it works out to a few cents a day.
The number grows with your memory folder, not with how much you used Claude. Change the
model with `MEMORY_KIT_MINER_MODEL` in `~/.claude/memory-kit/config`.

**Does it read my code?** No. The digest contains only messages you typed. Claude's
replies, tool output, command output, and your editor selection are all stripped out
before the miner sees anything, and it is never pointed at your repository. The one thing
worth knowing: code you paste into a message is part of what you typed, so it can appear
in the digest. The digest is a plain text file at
`~/.local/share/claude-feedback/digest-latest.txt` if you want to look.

**How do I know the daily miner is running?** Open the tracker at
`~/.local/share/claude-feedback/proposals.md` and look at the `## Daily log` table near
the bottom. One row per run, with how many messages and sessions it read. A row for today
or yesterday means it is running; `0 new` is the normal result on most days. If something
has stopped it from running at all, the kit tells you once a day rather than staying
quiet.

**What if two machines mine on the same day?** Nothing collides. The miner's tracker lives
outside your memory folder, so it is never synced: each machine keeps its own window and
its own proposal list, and each reads only the transcripts on that machine. The one shared
thing is the memory files themselves. So if you accept a preference on one machine and pull
it on the other, the second machine's miner sees it is already covered and retires its own
copy of that proposal instead of asking you twice.

**Can I edit a memory file by hand?** Yes, and it takes effect on your next prompt, because
the index is rebuilt from whatever files are actually on disk rather than from a cached
list. Two things to keep right: the `name` in the frontmatter has to match the filename, and
the file needs its `description`. If either is off, the file is invisible to the index;
`/review-memories` finds those and proposes the rename that fixes them. On a synced folder
the commit guardrail checks the same fields, so a malformed file cannot leave the machine.

**Web-only sessions?** No. Everything lives in local hooks and scripts.

## Uninstall

```bash
~/claude-memory-kit/install.sh --uninstall     # or ~/.claude/memory-kit/install.sh
```

It removes its own hooks from `~/.claude/settings.json` and leaves every other hook in
that file alone, deletes the tree and the kit's skills, and undoes the two settings it
made in your memory repo: the guardrail wiring and the flag that hid `MEMORY.md` from
git. That last part matters, because a guardrail still wired to a deleted tree would stop
checking commits without saying anything.

**What stays.** Every memory file, in both tiers. Nothing the kit installs lives in your
memory folder, so there is nothing to sort through. The miner's tracker at
`~/.local/share/claude-feedback` also stays, since it holds the proposals you accepted
and rejected, and the rejections are what stop a later reinstall from asking again. Add
`--purge-cache` to drop the cached message digest and the run logs, or `--purge-tracker`
to remove all of it. Both say what they are deleting.

`--dry-run` prints what either direction would do and changes nothing.

## Working on the kit

```bash
bash tests/run.sh          # the fixture suite, runs on any machine, gates every install
bash tests/smoke.sh        # the real-data suite, checks the kit against your ~/.claude
```

`run.sh` is the gate: `install.sh` runs it first and refuses to deploy a tree it rejects.
`smoke.sh` passes or skips depending on the machine it runs on, which is the point, so it is
never a required check.

Point the commit guardrail at your own checkout too, and it adds one house rule on top of
the leak checks: no em-dashes on lines added to `README.md` or `docs/*.md`.

```bash
git -C . config core.hooksPath guardrail
```

[DESIGN.md](docs/DESIGN.md) says why every rule exists, including the ones that look
arbitrary. Read it before changing one.

## Related projects

- **[claude-setup-template](https://github.com/sabilmakbar/claude-setup-template)**: one
  manifest for a whole Claude Code setup. You declare the kits, CLI tools, plugins, and
  hooks a machine should have, and its `setup.sh` converges the machine onto it. Its
  example manifest installs this kit, so start there if you are setting up a machine
  rather than adding one piece.
- **[claude-session-kit](https://github.com/sabilmakbar/claude-session-kit)**: the sibling
  kit. It gives sessions real names, leaves you a note for next time, and moves or splits
  them cleanly, where this kit looks after what Claude remembers about you.
- **[claude-memories-template](https://github.com/sabilmakbar/claude-memories-template)**:
  the starting point for the private memory repo described above.

MIT licensed, see [LICENSE](LICENSE).
