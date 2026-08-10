# Claude Memory Kit

Claude Code forgets you between sessions. Preferences you explain on Monday are gone by
Wednesday, and nothing you teach it survives a new laptop. This kit fixes that. It keeps
your preferences as small files that load into every session, backs them up to a private
repo if you want, and once a day it notices the corrections you keep repeating and offers
to remember them for you.

Everything runs on your machine, and nothing is saved without your approval.

New here? [HOW-IT-WORKS.md](docs/HOW-IT-WORKS.md) explains the daily loop in plain language.
Engineers who want the architecture and the reasoning behind it should read
[DESIGN.md](docs/DESIGN.md).

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

You need `jq`. The miner and sync also use `git`, `gh`, and the `claude` CLI. Details in
[DEPENDENCIES.md](docs/DEPENDENCIES.md).

```bash
git clone https://github.com/sabilmakbar/claude-memory-kit.git ~/claude-memory-kit
~/claude-memory-kit/install.sh
```

The installer runs its own test suite first and refuses to install if anything fails.
It then places the kit in `~/.claude/memory-kit`, adds its hooks to your Claude Code
settings without touching hooks from other tools, and keeps any memory files you already
have. Re-running it is always safe. Start a new Claude Code session afterwards.

If you had memories before installing, run `/review-memories` once. It finds files the
index cannot see yet and proposes the small renames that fix them.

## What you will notice day to day

Session starts may greet you with a short note: a reminder that a memory review is due,
that the daily loop found something worth keeping, or that some part of the kit has been
unable to run for a few days. Say "review feedback proposals"
and Claude walks you through each suggestion. Say "remember this" at any time to save a
preference directly, no review needed. That is the whole interface.

## Keeping memories on GitHub (optional)

Without this, everything works but your memories live on one disk. With it, a dead laptop
loses nothing and a new machine starts off knowing everything you have taught Claude.

One rule before the first push: tell the guardrail what counts as private for you. Add
your employer's name and any other identifying terms to
`~/.claude/memory-kit/guardrail/denylist.local`. The built-in checks catch emails and
machine paths, but only you know the rest.

**On your first machine**, create the repo once. The easy way is the
[claude-memories-template](https://github.com/sabilmakbar/claude-memories-template):
click "Use this template", make the repo **private**, clone it to `~/.claude/memory`, and
re-run `install.sh`.

<details>
<summary>Or turn an existing memory folder into the repo by hand</summary>

```bash
cd ~/.claude/memory
git init
git config core.hooksPath ~/.claude/memory-kit/guardrail  # wire the guardrail FIRST
git add . && git commit -m "Initial memory"               # now genuinely vetted
git remote add origin https://github.com/<your-user>/claude-memories.git  # create it first
git push -u origin main
```

Wire the guardrail before the first commit. That commit carries everything you have
accumulated unchecked, so it is the one that needs vetting most.

With the GitHub CLI installed, `gh repo create <your-user>/claude-memories --private
--source . --push` replaces those last two lines and creates the repo for you.
</details>

**On every other machine**, never create a second repo. Join the one you have:

```bash
mv ~/.claude/memory ~/.claude/memory.local-backup    # keep what this machine learned
git clone <your-memories-repo> ~/.claude/memory
~/claude-memory-kit/install.sh
```

Copy anything worth keeping from the backup into the clone, commit, and delete the
backup. From then on, plain `git pull` and `git push` in `~/.claude/memory` is how your
machines share what they learn.

<details>
<summary>Two extras some machines need</summary>

If the repo carries a global `CLAUDE.md` (the template ships one), link it:

```bash
ln -sfn ~/.claude/memory/CLAUDE.md ~/.claude/CLAUDE.md
```

If this machine's git is signed into a different account (a work one, say), give the
memory repo its own credentials so pushes go out under the right name. Keep your
username in the remote URL (`https://<personal-user>@github.com/...`) and set:

```bash
cd ~/.claude/memory
git config credential.https://github.com.helper ''
git config --add credential.https://github.com.helper \
  '!f() { test "$1" = get && echo "password=$(gh auth token --user <personal-user>)"; }; f'
```

That version borrows the token from the GitHub CLI. If you prefer SSH, a host alias in
`~/.ssh/config` pointing at your personal key does the same job with no helper at all,
and nothing to expire.
</details>

## How it stays trustworthy

Two test suites cover the kit: a fixture suite that gates every install and every push,
and a smoke suite that checks the kit against your machine's real data. After a Claude
Code update, a background hook re-runs the smoke suite and records the result, so a
harness change that breaks something gets noticed instead of failing silently. The full
story is in [DESIGN.md](docs/DESIGN.md).

## FAQ

**Does this conflict with MCP servers?** No. The kit is built from ordinary lifecycle
hooks and plain files, and registers no MCP surface. One caveat: running a
memory-flavored MCP server alongside it gives you two memories that can disagree. Pick
one.

**Does it conflict with Claude Code's built-in memory?** No, it *is* the built-in
per-project memory, redirected to one central folder and given a generated index. If
Claude Code reshapes its memory layout, the kit needs a patch, and the version check
exists to surface exactly that.

**Can I turn the daily miner off on one machine?** Set `MEMORY_KIT_NO_MINER=1`. Memory,
the index, and the guardrail carry on. Saying it explicitly matters, because the kit
treats a feature that goes quiet for days as a fault and tells you about it once a day.

**Web-only sessions?** No. Everything lives in local hooks and scripts.

## Uninstall

Remove the kit's hooks from `~/.claude/settings.json`, then delete
`~/.claude/memory-kit`, the kit's skills in `~/.claude/skills`, the two seed convention
files in `~/.claude/memory`, and `~/.local/share/claude-feedback` (the miner's tracker).
Your memory files themselves are yours and stay where they are.
