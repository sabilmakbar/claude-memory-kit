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

## A skill is missing, or fails the moment it runs

**Quickest check.** Re-run `install.sh`. It reads the plugin's installed version and says
which of four cases you are in: not installed, marketplace added but plugin missing,
installed and current, or installed behind this checkout with the update command to run.
`--dry-run` reports the same without touching anything.

**On updating.** The installer prints `claude plugin update` rather than `/plugin update`,
because the slash command is not available in every host. The VS Code extension does not have
it, and which hosts do is unconfirmed. If `claude` is not on your `PATH`, the binary ships inside the extension at
`~/.vscode/extensions/anthropic.claude-code-*/resources/native-binary/claude`, or
`~/.vscode-server/...` on a remote host.

**Check.** The skills come from the plugin, everything they read comes from `install.sh`, and
neither half works alone. Run `claude plugin list` and look for `memory-kit@memory-kit`, then
check that `~/.claude/memory-kit/` exists.

**Fix.** Whichever half is missing:

```bash
claude plugin marketplace add sabilmakbar/claude-memory-kit
claude plugin install memory-kit@memory-kit     # skills
~/claude-memory-kit/install.sh                  # hooks, tree, config
```

A skill that appears in the list and then fails on its first step is the second half missing:
`save-memory` opens `~/.claude/memory-kit/guidance/memory-authoring.md`, and
`initialize-memory` reads `~/.claude/memory-kit/config`. Neither exists until the installer has
run. Plugins load at session start, so start a new session after installing.

**If you see each skill twice,** once bare and once as `memory-kit:`, an older version of this
kit left a copy in `~/.claude/skills`. Re-run `install.sh`: it retires copies it recognises as
its own, and names any it will not touch.

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

## A push is rejected, or commits land under the wrong account

These look alike but they are two different problems, and a machine signed into a work
account causes both.

**Commits under the wrong name** is the commit identity step from the README's sync setup.
Set `user.name` and `user.email` on the memory repo and everything from then on is
attributed correctly. Commits already made keep their original author; rewriting them is
possible and rarely worth it on a private memory repo.

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

## The installer says the plugin is "ahead of" the newest release

Not a fault. The skills came from a source that is not a release: an unpinned marketplace
serves the default branch, and a local path serves a working tree. On a development checkout
this is the expected state. To make the number meaningful, pin the marketplace to a tag; the
README's install shows the form, and D12 in [DESIGN-install.md](DESIGN-install.md) holds the
reasoning.

## The installer says a pin "has no effect"

The marketplace pin names a version below one already in the plugin cache, and the newest
cached version is the one that loads. Nothing removes cache directories automatically, so the
pin stays dead until you act. Remove the directory the installer names, then
`claude plugin install memory-kit@memory-kit`, or pin forward to a release at or above the
cached version. Background: O19 and O26 in [INTERNALS.md](INTERNALS.md).

## I edited a skill, but the running copy never changes

`claude plugin update` compares version labels and never content, so an edit under an
unchanged version silently stays out of the loaded copy, even from a marketplace that points
at your working tree. The loop that works is in CONTRIBUTING.md: `claude plugin uninstall`,
then `claude plugin install`, then a new session. Measured as O27 in
[INTERNALS.md](INTERNALS.md).

## Elsewhere

**A push is rejected, or commits land under the wrong account.** Covered in the README, in
the private-repo setup section, because the fix depends on how that machine authenticates.
