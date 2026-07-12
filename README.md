# claude-feedback-miner

A daily, self-improving feedback loop for [Claude Code](https://claude.com/claude-code):
it mines your own messages for preferences you keep repeating — corrections, frustration,
"always/never" instructions — that your Claude memory does **not** already capture, scores
them, and proposes them back to you for review. Accept one and it becomes a durable memory;
reject it and it is never proposed again.

Everything runs and stays **on your machine**: transcripts are read locally, the one
LLM call per day goes through your own `claude` CLI, and the proposals tracker is a
local file.

**New to this? Read [HOW-IT-WORKS.md](HOW-IT-WORKS.md)** — the full flow in
non-technical language.

## How it works

```
first session of the day (SessionStart hook, backgrounded)
  └─ run-feedback-miner.sh          daily stamp + lock; resolves your claude CLI
       ├─ extract-user-messages.sh  user-typed messages since the last successful run,
       │                            stripped of tool noise (transcripts → small digest)
       └─ claude -p (headless)      follows feedback-miner.md:
            • finds candidate system-wide preferences (repetition, corrections, emphasis)
            • drops anything your memory/CLAUDE.md already covers ("complementarity")
            • scores each: 2·frequency + 1.5·intensity + 1.5·novelty + generality
            • judge pass to sanity-check its own scores
            • updates ~/.local/share/claude-feedback/proposals.md (pending/accepted/
              rejected + daily log; rejected items are never re-proposed)

every session start
  └─ feedback-proposals-ping.sh     "N feedback proposal(s) pending (top: …)"
```

The extract window advances only after the tracker is verifiably written, so a failed
run never loses messages — they are simply mined next time.

## Install

Requirements: `jq`, and the `claude` CLI (a VS Code extension's bundled binary is
auto-detected as fallback).

```bash
git clone https://github.com/sabilmakbar/claude-feedback-miner.git ~/claude-feedback-miner
~/claude-feedback-miner/install.sh
```

The installer copies the scripts to `~/.claude/scripts/` and **appends** two
`SessionStart` hooks to `~/.claude/settings.json` (existing hooks are left intact;
re-running is a no-op).

## Reviewing proposals

At session start you'll see: `2 feedback proposal(s) pending (top: P-003 · total 21.5 · …)`.
Say **"review feedback proposals"** — Claude reads the tracker with you; accepted items go
into your global memory, rejected ones are remembered as rejected.

## Configuration

- `FEEDBACK_MINER_MODEL` — model for the daily run (default `sonnet`).
- Cost/footprint: one headless call per day over a digest of your typed messages only
  (typically tens of KB, capped at 300 KB), with tools restricted to `Read,Write,Edit`
  and a 10-minute timeout.

## Uninstall

Remove the two `SessionStart` hooks from `~/.claude/settings.json`, then:

```bash
rm ~/.claude/scripts/{extract-user-messages.sh,run-feedback-miner.sh,feedback-proposals-ping.sh,feedback-miner.md}
rm -rf ~/.local/share/claude-feedback   # tracker + state
```

## Privacy notes

- The digest and tracker can quote what you typed to Claude — they live in
  `~/.local/share/claude-feedback/` and are never transmitted anywhere by this tool.
- The tracker sits outside `~/.claude` deliberately: headless Claude sessions are not
  allowed to write inside it (sensitive-file protection).
