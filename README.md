# claude-memory-kit

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

## Using the guardrail with your memory repo

If you keep your actual memories in their own git repo (recommended, so they sync across
machines), point that repo's git hooks at the kit's guardrail:

```bash
git -C ~/your-memory-repo config core.hooksPath ~/claude-memory-kit/guardrail
```

Add your private terms (employer, machine mounts) to `~/claude-memory-kit/guardrail/denylist.local`
(gitignored) or export `CLAUDE_CONFIG_DENYLIST="term1|term2"`. The built-in patterns are
generic, so the kit itself carries no identifying information.

## Uninstall

Remove the kit's hooks from `~/.claude/settings.json`, then delete the installed scripts,
skills, and seed memories from `~/.claude`, and `rm -rf ~/.local/share/claude-feedback`
(the miner's tracker and state).
