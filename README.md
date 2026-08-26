# Claude Memory Kit

[![tests](https://github.com/sabilmakbar/claude-memory-kit/actions/workflows/tests.yml/badge.svg)](https://github.com/sabilmakbar/claude-memory-kit/actions/workflows/tests.yml)

Claude Code forgets you between sessions. Preferences you explain on Monday are gone by
Wednesday, and nothing you teach it survives a new laptop. This kit fixes that. It keeps
your preferences as small files that load into every session, backs them up to a private
repo if you want, and once a day it notices the corrections you keep repeating and offers
to remember them for you. Everything runs on your machine, and nothing is saved without
your approval.

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

Reading order for the rest of the docs: [HOW-IT-WORKS.md](docs/HOW-IT-WORKS.md) is the
plain-language story and the only one you need to use the kit. [FLOWS.md](docs/FLOWS.md)
has the diagrams, the `docs/DESIGN-*.md` records hold every rule with its reason, and
[INTERNALS.md](docs/INTERNALS.md) records what was observed about Claude Code itself.
Something broken rather than unclear: [TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md).

## Getting started

**The installer edits `~/.claude/settings.json`**, your global Claude Code config, because
registering a hook is the only way the memory index can rebuild itself on every prompt.
The test suite runs first and refuses to install if anything fails, the merge into your
file only ever adds, and `--dry-run` shows the plan before anything happens. The full
safety rules are in [DESIGN-install.md](docs/DESIGN-install.md).

You need `jq`. The miner and sync also use `git` and the `claude` CLI. Details in
[DEPENDENCIES.md](docs/DEPENDENCIES.md).

```bash
git clone --branch v0.4.0 https://github.com/sabilmakbar/claude-memory-kit.git ~/claude-memory-kit
~/claude-memory-kit/install.sh --mode=managed
```

Then add the skills, which ship as a Claude Code plugin:

```bash
claude plugin marketplace add sabilmakbar/claude-memory-kit@v0.4.0
claude plugin install memory-kit@memory-kit
```

**Both steps are needed.** The plugin brings the skills, `/memory-kit:save-memory` and so
on. `install.sh` brings the hooks, the kit tree and the config those skills read. Order
does not matter. The tag appears twice on purpose: without it, both halves track the
default branch instead of a release ([DESIGN-install.md](docs/DESIGN-install.md), D12).

**`--mode` is asked once and remembered.** It decides who may change your memory:
`managed` means the kit makes the change and says so first, `advisory` means it tells you
and you do it yourself. The installer will not pick for you.

### Where your memory ends up

Claude Code normally keeps one memory folder per repository. The kit makes memory global
by setting `autoMemoryDirectory` in your user settings, so every project reads and writes
one store. The installer prints what it found and what it did:

| What you have | What it does |
|---|---|
| `autoMemoryDirectory` already set | Leaves it alone |
| One memory store | Points the setting at it, nothing moved |
| Several memory stores | Lists them, never merges, the mode decides who acts |
| No memory at all | Uses `~/.claude/memory` |

To undo, delete the `autoMemoryDirectory` key, or run `./install.sh --uninstall`. Your
memory files are never moved, copied or deleted by any of this.

### Check it worked

Start a new Claude Code session, then:

```
$ head -3 ~/.claude/memory/MEMORY.md
# Memory Index
...
```

The index is rebuilt on every prompt, so if that file is missing after a fresh session,
the hooks did not run and nothing else will work either. If you had memories before
installing, run `/memory-kit:review-memories` once to bring them into the index. For a
deeper check any time, `bash ~/.claude/memory-kit/tests/smoke.sh` tests the kit against
this machine's real data, and its output is safe to paste when reporting a problem.

### Back your memories up to a private repo (recommended)

Memories are the one part of this setup you cannot regenerate. Behind a private repo, a
dead laptop costs you nothing and a new machine starts already knowing what you have
taught Claude.

**Before the first commit**, put your own private terms, such as employer, clients, and
handles, in `~/.claude/memory-kit/guardrail/denylist.local`. The guardrail already blocks
emails and home paths on its own, but it cannot guess what is specific to you, and once
something is committed it is in history whether you push it or not.

On the first machine, use the
[claude-memories-template](https://github.com/sabilmakbar/claude-memories-template): "Use
this template", make it **private**, clone it to `~/.claude/memory`, then re-run
`~/claude-memory-kit/install.sh`, which wires the guardrail into the new repo. To convert
an existing folder instead: `git init` in `~/.claude/memory`, re-run `install.sh`, then
make the first commit and push it to a private repo you create.

On every other machine, never create a second repo. Join the one you have:

```bash
mv ~/.claude/memory ~/.claude/memory.local-backup    # keep what this machine learned
git clone <your-memories-repo> ~/.claude/memory
~/claude-memory-kit/install.sh                       # wires the guardrail into the clone
```

Copy anything worth keeping out of the backup, then delete it. From then on, plain
`git pull` and `git push` in `~/.claude/memory` is how your machines share what they
learn.

Two finishing touches on each machine: link the repo's global `CLAUDE.md` if it ships one
(`ln -sfn ~/.claude/memory/CLAUDE.md ~/.claude/CLAUDE.md`), and give the repo its own
commit identity (`git -C ~/.claude/memory config user.name` and `user.email`), so memory
commits are attributed to you rather than to whatever this machine defaults to. If a push
is rejected, or commits land under the wrong account, see
[TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md).

### Upgrading

```bash
git -C ~/claude-memory-kit pull && ~/claude-memory-kit/install.sh
claude plugin update memory-kit@memory-kit      # restart to apply
```

To move between releases, repeat the install commands with the new tag. Pin forward, not
back. You do not have to track any of this yourself: the installer says which state you
are in and names the command that fixes it, halves on different releases are reported once
a day, and a pull that leaves the deployed tree behind is reported the moment it happens.
If `claude` is not on your `PATH`, see [TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md).

The installer replaces kit code only. Your memory files, your `denylist.local`, your
edited `config`, and other tools' hooks in `settings.json` all survive, and renamed knobs
are rewritten with their values kept.

## What it does day to day

Session starts may greet you with a short note: a reminder that a memory review is due,
that the daily loop found something worth keeping, or that some part of the kit has been
unable to run for three days or more. Say "review feedback proposals" and Claude walks you
through each suggestion. Say "remember this" at any time to save a preference directly.
That is the whole interface.

Under it sit three parts:

- **Hooks** rebuild the memory index on every prompt and run the daily checks. They are
  wired into `settings.json` by the installer and removed by `--uninstall`.
- **Skills** are the commands: `/memory-kit:save-memory`, `/memory-kit:review-memories`,
  `/memory-kit:review-feedback-proposals`. They ship as a plugin so their names cannot
  collide with anything else.
- **The guardrail** is a commit hook in your memory repo that blocks PII before it can
  leave the machine.

Three checks keep the kit honest: a fixture suite gates every install and every push, a
smoke suite checks the kit against your machine's real data after each Claude Code update,
and a weekly workflow probes every newly published Claude Code build for what the
installer depends on. The story is in [DESIGN-health.md](docs/DESIGN-health.md); the
probed-build ledger is `tests/versions-checked.tsv`, covering every published build from
2.0.0 to 2.1.246, and it is where the installer's version floor comes from.

## FAQ and troubleshooting

[FAQ.md](docs/FAQ.md) answers the questions that come up before anything is wrong: MCP,
the built-in memory, what the daily miner costs and reads, editing files by hand.
[TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) works by symptom when something is wrong.

## Uninstall

```bash
~/claude-memory-kit/install.sh --uninstall     # or ~/.claude/memory-kit/install.sh
```

It removes its own hooks from `~/.claude/settings.json` and leaves every other hook in
that file alone, deletes the tree and any bare skill copy an older version left in
`~/.claude/skills`, and undoes the two settings it made in your memory repo: the guardrail
wiring and the flag that hid `MEMORY.md` from git. That last part matters, because a
guardrail still wired to a deleted tree would stop checking commits without saying
anything.

**What stays.** Every memory file, in both tiers. The miner's tracker at
`~/.local/share/claude-feedback` also stays, since it holds the proposals you accepted
and rejected, and the rejections are what stop a later reinstall from asking again. Add
`--purge-cache` to drop the cached digest and logs, or `--purge-tracker` to remove all of
it. Both say what they are deleting. `--dry-run` prints what either direction would do
and changes nothing.

The skills come from the plugin, so remove that separately, and **order matters**:

```bash
claude plugin uninstall memory-kit@memory-kit    # first
claude plugin marketplace remove memory-kit      # only after
```

Reversed, the uninstall fails: it resolves the plugin through the marketplace and cannot
find it once that entry is gone. Neither command removes the plugin's cache under
`~/.claude/plugins/cache/memory-kit/`; delete it by hand if you want the disk space back.

## Working on the kit

`bash tests/run.sh` is the gate: `install.sh` runs it first and refuses to deploy a tree
it rejects. [CONTRIBUTING.md](CONTRIBUTING.md) is the way in, including the guardrail
wiring for your checkout and the development loop for skills. The five decision records
say why every rule exists; read the one covering what you are changing before you change
it.

## Related projects

- **[claude-session-kit](https://github.com/sabilmakbar/claude-session-kit)**: the sibling
  kit. It gives sessions real names, leaves you a note for next time, and moves or splits
  them cleanly, where this kit looks after what Claude remembers about you.
- **[claude-memories-template](https://github.com/sabilmakbar/claude-memories-template)**:
  the starting point for the private memory repo described above.

Released versions and what changed in each: [CHANGELOG.md](CHANGELOG.md).

MIT licensed, see [LICENSE](LICENSE).
