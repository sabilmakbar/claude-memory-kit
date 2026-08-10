# How it works

The idea in one sentence: you keep correcting Claude about the same things, and this tool
notices, then turns those corrections into permanent preferences, but only with your
approval.

## The daily rhythm

**1. Once a day, quietly, Claude re-reads what you typed.**
The first time you open Claude Code each day, a small background job wakes up. It gathers
what you typed into Claude since the last run, across all your projects. Only your side of
the conversation is read. Claude's replies, code, and command output are left out.

**2. It looks for things you keep saying.**
A separate, private Claude session reads those messages and looks for lasting preferences
rather than one-off instructions. The signs it watches for:

- you corrected Claude ("no, do it this way", "I told you already")
- you said the same thing on different days or in different projects
- you sounded frustrated, or used words like "always", "never", "from now on"

The full brief that session works from is checked into the repo at
[scripts/feedback-miner.md](../scripts/feedback-miner.md), if you want to read exactly what
it is told to look for and how it scores what it finds.

**3. It checks whether Claude already knows.**
Each candidate is compared against your existing memory. Anything already recorded is
dropped. If a preference is partly known, only the missing piece is proposed.

**4. What's left becomes a proposal, with a score.**
Each surviving candidate goes into a small file called the tracker. A proposal records
the rule in a sentence or two, when it applies, how often and how strongly you said it,
and your own words as evidence. A score puts the strongest patterns on top. Seeing the
same pattern again later doesn't create a duplicate; the existing proposal just gains
evidence.

If you would rather see all of that as a picture, [FLOWS.md](FLOWS.md) has the same loop as
a diagram, along with what runs at which point in a session.

## Your part (the only part that needs you)

**5. You get a one-line nudge.**
Whenever proposals are waiting, a new session starts with a note like:

> *2 feedback proposal(s) pending (top: P-901 · total 24 · Show cost estimate before
> batch jobs). Say: review feedback proposals.*

Ignore it as long as you like. Nothing happens without you.

**6. When you're ready, say "review feedback proposals".**
(Or run `/review-feedback-proposals`.) Claude shows you each proposal in full: the rule,
when it fires, and the evidence. You answer one of four ways.

- **Accept.** The rule becomes a permanent memory. Every future session starts already
  knowing it, and you should never have to repeat that correction again.
- **Reject.** The proposal is filed away. By default that means "not now": if the same
  pattern clearly keeps happening on later days, it may come back once, marked as
  resurfaced. Reject it a second time and it is gone for good. If you already know it's
  a never, say "never" and it is final immediately.
- **Rephrase.** You like the idea but not the wording. Give your own phrasing and that
  is what gets saved.
- **Leave it.** Undecided items stay in the list and keep collecting evidence.

That is the whole loop. The tool notices, checks what Claude already knows, proposes,
you decide, and Claude remembers.

## Where your memories live (and how they follow you)

Each preference is a small text file in one folder on your machine. On every prompt, the
kit rebuilds the index Claude loads from whatever files are actually there, so the index
can never drift out of date.

Syncing is optional. If you turn that folder into a **private** GitHub repo (the README
shows how), your memories survive a dead laptop and follow you to new machines. The first
machine creates the repo; every later machine clones the same one. There is only ever one
repo, because a second machine creating its own would end up with two disagreeing
memories.

Because synced memories leave your machine, a guardrail checks every commit before it
happens. Emails, home paths, private terms you list (like your employer's name), and
malformed memory files all block the commit until fixed. Nothing sensitive slips out in
a moment of autopilot.

## Things worth knowing

- **Nothing leaves your machine.** Your messages, the digest, and the tracker are local
  files. The daily analysis runs through your own Claude account, like any other session.
- **It never changes Claude's behavior by itself.** Only proposals you explicitly accept
  become memory. The miner writes to exactly one file: the tracker.
- **Cost is small.** One short Claude call per day. It reads what you typed (typically a
  few dozen messages) plus your existing memory files, which is how it can tell what is
  already known. If your memory repo has a remote, the miner pulls first, so "already
  known" includes what your other machines recorded since yesterday.
- **Telling Claude directly still works, and wins.** Saying "remember this" in any
  session saves a preference immediately, no review needed. The miner only fills the gaps
  you didn't think to dictate. If you save something by hand while a matching proposal is
  waiting, the proposal quietly retires itself.
- **"Nothing today" is normal, and a broken day is not the same thing.** On most days
  everything you emphasized is either project-specific or already in memory. The tracker
  logs "0 new" and moves on. A day where the job could not run at all is different, say
  because the `claude` CLI is missing or the memory repo will not sync. That used to look
  identical to a quiet week. Now the reason is recorded, and once a block has lasted a few
  days you get one note a day until it is fixed.
- **You can always just read the file.** The tracker is plain markdown at
  `~/.local/share/claude-feedback/proposals.md`. Open it anytime.
