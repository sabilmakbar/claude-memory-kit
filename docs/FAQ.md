# FAQ

Questions about how the kit behaves and what it costs. Something broken rather than
unclear is [TROUBLESHOOTING.md](TROUBLESHOOTING.md), which works by symptom.

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
`/memory-kit:review-memories` finds those and proposes the rename that fixes them. On a synced folder
the commit guardrail checks the same fields, so a malformed file cannot leave the machine.

**Web-only sessions?** No. Everything lives in local hooks and scripts.

