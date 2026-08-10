# Claude Memory Kit

A self-maintaining memory system for [Claude Code](https://claude.com/claude-code). It
keeps a durable, portable memory of your preferences, guards how that memory is written and
committed, and — once a day — notices preferences you keep repeating and proposes them back
to you. Everything runs on your machine.

**New here? Read [HOW-IT-WORKS.md](HOW-IT-WORKS.md)** for the daily feedback loop in
non-technical language.

## Who this is for

Anyone who runs Claude Code on a machine they control — the CLI, the desktop app, or an
IDE extension — since everything here lives in local `~/.claude` hooks and scripts (it
can't help web-only sessions on claude.ai). It pays off most once you've used Claude Code
enough to feel the pains it fixes: preferences that don't survive a new machine, an index
that drifts, the same correction typed for the third time. If you're brand new to Claude
Code, it will still work, but you may want to build those scars first.

## Why

Claude Code stores its memory and settings under `~/.claude` — per-machine, easy to lose,
easy to let drift, and (if you ever sync it) easy to leak private details into. This kit
turns that loose setup into something dependable:

- **Memory that travels and can't drift.** Preferences live as small files; the always-loaded
  index is regenerated from those files on every prompt, so it can never fall out of sync or
  silently drop an entry.
- **Guarded authoring.** A pre-commit guardrail keeps employer names, emails, and machine
  paths out of a synced memory repo, and enforces the file conventions. An Edit-over-Write
  hook makes every change to an existing file show up as a reviewable diff.
- **Self-improving.** A daily miner reads your own messages, finds preferences you emphasized
  but haven't recorded, and proposes them for one-tap review — accepted ones become permanent
  memory.

## What's inside

| Piece | What it does |
|-------|--------------|
| `scripts/ensure-memory-symlink.sh` | Symlinks the per-project memory dir to a central store and regenerates the `MEMORY.md` index from the files (drift-proof). Runs on `UserPromptSubmit`. |
| `scripts/edit-over-write.sh` | `PreToolUse` hook that denies `Write` on a file that already exists, so edits land as auditable diffs. |
| `scripts/memory-review-reminder.sh` · `feedback-proposals-ping.sh` | `SessionStart` notices: memory-review-due, and pending mined proposals. |
| `scripts/run-feedback-miner.sh` · `extract-user-messages.sh` · `feedback-miner.md` | The daily miner: extract your typed messages, score preference candidates, write a proposals tracker. |
| `guardrail/pre-commit` | Commit guardrail for a memory repo: blocks PII/machine-path leaks and enforces frontmatter conventions. |
| `skills/review-feedback-proposals` · `skills/review-memories` | Interactive review flows (accept/reject proposals; periodic memory health-check). |
| `seed-memories/` | The memory-authoring conventions (What/Why/How format, naming, no in-file evidence) — installed into your memory so any session follows them. |

## Install

Requirements: `jq` (required), plus `git`, `gh`, and the `claude` CLI for the miner and
sync — see [DEPENDENCIES.md](DEPENDENCIES.md).

```bash
git clone https://github.com/sabilmakbar/claude-memory-kit.git ~/claude-memory-kit
~/claude-memory-kit/install.sh
```

The installer copies the scripts to `~/.claude/scripts`, the skills to `~/.claude/skills`,
seeds the authoring conventions into `~/.claude/memory`, and **appends** its hooks to
`~/.claude/settings.json` (existing hooks are left intact; re-running is a no-op). Start a
new Claude Code session to load everything.

## Adopting with existing memories

The installer never overwrites memory files you already have — it only adds the two seed
conventions when absent. Adoption then happens on your first prompt in each project: the
hook merges that project's old memory files into the central store. Top-level files are
copied in (on a name collision the central copy wins), and the old directory is kept next
to the new symlink as `memory.pre-kit.<timestamp>.bak`, so nothing is ever destroyed —
delete the backups once you're satisfied.

Files whose names don't match the indexed patterns (`user_*`/`feedback_*`) survive on
disk but are flagged in the regenerated index with an "Unindexed files" warning: they are
invisible to recall until renamed. So after installing, run `/review-memories` once — it
walks those warnings and proposes the renames and frontmatter fixes that bring adopted
files into the index and up to the authoring conventions.

## Syncing memories across machines (optional)

Without this step everything works, but your memories live on one disk. With it, they
live in a **private GitHub repo**: a dead laptop loses nothing, and a new machine starts
with everything you've ever taught Claude. You create the repo **once**, on your first
machine — every other machine joins the same repo, never creates a second one.

**Before the first push, on every machine:** add your private terms (employer name,
anything identifying) to `~/claude-memory-kit/guardrail/denylist.local` (gitignored), or
export `CLAUDE_CONFIG_DENYLIST="term1|term2"`. The built-in guardrail patterns catch
generic leaks (emails, home paths); only you know what else is sensitive.

### First machine — create the repo

Fastest: use the
[claude-memories-template](https://github.com/sabilmakbar/claude-memories-template) —
click "Use this template", create a **private** repo, clone it to `~/.claude/memory`, and
re-run `install.sh`. Or turn your existing memory folder into the repo by hand:

```bash
cd ~/.claude/memory
git init
git config core.hooksPath ~/claude-memory-kit/guardrail   # wire the guardrail FIRST
git add . && git commit -m "Initial memory"               # ← now genuinely vetted
gh repo create <your-user>/claude-memories --private --source . --push
```

Wire the guardrail **before** the first commit — that commit carries your accumulated,
never-vetted memories, so it's the one that needs checking most. Afterwards, re-running
`~/claude-memory-kit/install.sh` keeps things wired automatically whenever
`~/.claude/memory` is a git repo (and hides index churn from your diffs); the manual
line is also how you wire a memory repo kept somewhere other than `~/.claude/memory`.

### Every other machine — join the existing repo

Do **not** create a new repo or reuse the template here; clone the one you already have:

```bash
mv ~/.claude/memory ~/.claude/memory.local-backup    # keep anything this machine learned
git clone <your-existing-memories-repo> ~/.claude/memory
~/claude-memory-kit/install.sh                       # wires the guardrail automatically
```

Then compare `~/.claude/memory.local-backup/` against the clone: copy in any memory file
this machine had that the repo lacks, commit (the guardrail checks it), and delete the
backup. From here on, `git pull`/`git push` in `~/.claude/memory` is how machines share
what they learn — run `/review-memories` occasionally to keep the merged set tidy.

Two small extras for the join:

- **If the repo carries a global `CLAUDE.md`** (the template ships one), link it:
  `ln -sfn ~/.claude/memory/CLAUDE.md ~/.claude/CLAUDE.md`.
- **If this machine's `gh`/git is logged into a different account** (e.g. a work one),
  give the memory repo its own credentials so pushes go out under the account that owns
  it — keep the username in the remote URL
  (`https://<personal-user>@github.com/...`) and set a repo-local helper:

  ```bash
  cd ~/.claude/memory
  git config credential.https://github.com.helper ''
  git config --add credential.https://github.com.helper \
    '!f() { test "$1" = get && echo "password=$(gh auth token --user <personal-user>)"; }; f'
  ```

## Testing & self-verification

Two complementary suites:

- **`tests/run.sh`** — the CI gate. Self-contained fixtures in throwaway temp dirs;
  never touches your real `~/.claude`. Runs on every push.
- **`tests/smoke.sh`** — the reality check, run on *your* machine against your real
  transcripts, settings, and shell. It has no fixtures, so every check is an invariant
  ("whatever the answer is, it must have this shape"), and checks with no local data
  skip rather than fail. Mutating steps run in a throwaway `$HOME`, and one of its own
  checks is that your real state was left untouched. Never wire it into CI — passing
  or skipping depends on the machine, which is the point.

On a clean pass, `smoke.sh` stamps the current Claude Code version into `.verified`
(machine-local, gitignored). The `hooks/version-check.sh` SessionStart hook compares
that stamp against the running version: after a Claude Code update it re-runs the
smoke suite once, in the background. Success re-stamps and everything stays quiet;
failure stamps nothing — the missing write is the report, and `.smoke-last.log`
holds the receipt. The kit parses undocumented Claude Code internals (transcript
JSONL, settings layout), and this is what turns a silent format break into a
detected one.

## FAQ

**Does this conflict with MCP servers?** No — the kit registers no MCP surface at all.
It is built from harness lifecycle hooks (`UserPromptSubmit`, `SessionStart`, one
`PreToolUse` matcher on the built-in `Write` tool), plain files, and a git pre-commit
hook; MCP tools are neither wrapped nor intercepted. One practical caveat: running a
memory-flavored MCP server *alongside* the kit gives you two memories that can disagree,
and things saved to the MCP store are invisible to the miner and guardrail — pick one.

**Does it conflict with Claude Code's built-in memory?** It *is* the built-in per-project
memory, redirected: the symlink hook points each project's memory directory at one
central store and regenerates the index from the files there. That makes it a dependency
rather than a conflict — if Claude Code reshapes its memory layout, the kit will need a
patch, and the version-check hook exists to surface exactly that (see "Testing &
self-verification").

**Web-only sessions?** Everything lives in local `~/.claude` hooks and scripts, so
sessions on claude.ai without a local harness can't use it (see "Who this is for").

## Uninstall

Remove the kit's hooks from `~/.claude/settings.json`, then delete the installed scripts,
skills, and seed memories from `~/.claude`, and `rm -rf ~/.local/share/claude-feedback`
(the miner's tracker and state).
