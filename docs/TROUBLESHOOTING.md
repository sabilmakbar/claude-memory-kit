# Troubleshooting

Symptom, then check, then fix. If you are not sure anything is wrong, run the doctor first:
`bash ~/.claude/memory-kit/tests/smoke.sh`. The README explains what its output means.

This file covers faults. Questions about behaviour that is working as intended live in the
README's FAQ.

## The guardrail blocked my commit

It blocks for three different reasons and says which. Match the line you got.

**`staged content looks like a private/machine leak`.** An added line matched an email
address, a home directory path, or one of your own private terms. The blocked lines are
printed under the message.

Fix the line, not the hook: generalise the wording so the rule still reads correctly without
the specific name. If it is a genuine false positive, the term came from
`~/.claude/memory-kit/guardrail/denylist.local` and you can edit it there.

**`added doc lines use an em-dash`.** House style, and it only applies to `README.md` and
`docs/*.md`. Replace it with a comma, colon, semicolon, or period. Code, tests, and memory
files are out of scope and keep theirs.

**`memory frontmatter issues`.** The message names each file and what is wrong. Three rules:

| Rule | Why |
|---|---|
| `name:` must equal the filename without `.md` | the index and wikilinks resolve by that slug |
| `description:` is required | it is what recall matches against |
| the filename starts with `user_`, `feedback_`, or `project_` | the prefix carries the memory's type |

## The index does not list a file I can see on disk

**Check.** Open `~/.claude/memory/MEMORY.md` and look for the file. If it is absent while the
`.md` file exists, its frontmatter is not readable by the index.

**Fix.** Run `/memory-kit:review-memories`. It finds exactly this case and proposes the rename or the
missing field. The rules are the three in the table above, and the FAQ explains them from the
authoring side.

The index is rebuilt from disk on every prompt, so a fix takes effect on your next message.
There is no cache to clear.

## The miner never runs

Work through these in order; each is cheap to check.

1. **Is it switched off?** `echo $MEMORY_KIT_NO_MINER`. Any value means the miner exits
   immediately, on purpose.
2. **Is the `claude` CLI on PATH?** `command -v claude`. Without it the miner no-ops. The
   installer warns about this but does not fail.
3. **Are the hooks wired?** `jq '.hooks | tostring | test("memory-kit")' ~/.claude/settings.json`.
   `false` means re-run `install.sh`.
4. **Did it try?** Open `~/.local/share/claude-feedback/proposals.md` and read the
   `## Daily log` table. A row for today or yesterday means it ran, and `0 new` is the normal
   result on most days. The FAQ explains how to read that table.
5. **Did it fail?** `~/.local/share/claude-feedback/miner.log` holds the last run, and
   `miner.log.1` the one before.

It runs once per day, on your first session, in the background. It is not late until a day
has passed.

## I get a daily notice about a feature I chose not to use

The kit treats a feature that goes quiet as a fault, which is what makes the notices worth
reading. So opting out silently looks identical to being broken.

**Fix.** Say it explicitly. Set `MEMORY_KIT_NO_MINER=1` in the environment your sessions
start in. That does not merely skip the miner: it clears the health record, so the notice
stops.

Memory, the index, and the guardrail all carry on regardless.

## Two machines disagree about a memory

Both are right about their own copy. The memory folder is an ordinary git repo, so the
reconciliation is ordinary git:

```bash
git -C ~/.claude/memory pull
git -C ~/.claude/memory push
```

Two things make this less painful than it sounds. `MEMORY.md` is marked `skip-worktree` by
the installer, so the generated index never shows up as a conflict. And the miner reads your
memory files as input, so once a preference has synced, the other machine stops proposing it
and retires its own copy of that proposal.

If the two machines have genuinely different content in the same file, that is a normal merge
conflict. Resolve it in the file, and remember the guardrail runs on the resulting commit.

## Elsewhere

**A push is rejected, or commits land under the wrong account.** Covered in the README, in
the private-repo setup section, because the fix depends on how that machine authenticates.
