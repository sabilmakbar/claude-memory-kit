# How this works — in plain language

The idea in one sentence: **you keep correcting Claude about the same things; this tool
notices, and turns those corrections into permanent preferences — but only with your
approval.**

## The daily rhythm

**1. Once a day, quietly, Claude re-reads what you typed.**
The first time you open Claude Code each day, a small background job wakes up. It gathers
everything *you* typed into Claude since the last time it ran — just your side of the
conversations, across all your projects. Claude's replies, code, and command output are
all left out.

**2. It looks for things you keep saying.**
A separate, private Claude session reads those messages looking for signs of a lasting
preference rather than a one-off instruction:

- you corrected Claude ("no, do it this way", "I told you already")
- you said the same thing on different days or in different projects
- you sounded frustrated, or used words like "always" / "never" / "from now on"

**3. It checks whether Claude already knows.**
Each candidate is compared against Claude's existing memory of you. If the preference is
already recorded, it's dropped — no point proposing what's already known. If it's
*partly* known, only the missing piece is proposed.

**4. What's left becomes a proposal, with a score.**
Each surviving candidate is written into a small file — the **tracker** — with:

- the proposed rule, in one or two sentences
- when it would apply and when it wouldn't ("in practice")
- how often you said it, how strongly, and quotes as evidence
- a score, so the strongest patterns rise to the top

The same proposal seen again on a later day isn't duplicated — its evidence and score
just grow.

## Your part (the only part that needs you)

**5. You get a one-line nudge.**
Whenever proposals are waiting, each new Claude session starts with a note like:

> *2 feedback proposal(s) pending (top: P-901 · Show cost estimate before batch jobs).
> Say: review feedback proposals.*

Ignore it as long as you like — nothing happens without you.

**6. When you're ready, say "review feedback proposals"** (or run `/review-feedback-proposals`)**.**
Claude shows you each proposal in full — the rule, when it fires, the evidence — and asks
for one of:

- **Accept** — the rule becomes a permanent memory. From then on, every Claude session
  starts already knowing it, and you should never have to repeat that correction again.
- **Reject** — the proposal is filed away. By default that's "not now": if the same
  pattern clearly keeps happening afterwards (several separate days of fresh evidence),
  it may come back **once**, marked as resurfaced — reject it a second time and it's
  gone for good. If you already know it's a never, say "never" and it's final
  immediately.
- **Rephrase** — you like the idea but not the wording; give your own phrasing and that's
  what gets saved.
- **Leave it** — undecided items simply stay in the list and keep collecting evidence.

That's the whole loop: **notice → check → propose → you decide → Claude remembers.**

## Things worth knowing

- **Nothing leaves your machine.** Your messages, the digest, and the tracker are local
  files. The daily analysis runs through your own Claude account, like any other session.
- **It never changes Claude's behavior by itself.** Only proposals you explicitly accept
  become memory. The miner writes to exactly one file: the tracker.
- **Cost is small.** One short Claude call per day, reading only what you typed
  (typically a few dozen messages).
- **Telling Claude directly still works — and wins.** Saying "remember this" /
  "add this to feedback" in any session saves a preference immediately, no review needed.
  The miner only fills the gaps you *didn't* think to dictate: anything already in memory
  is never proposed, and if you manually add something that was sitting in the proposal
  list, the proposal quietly retires itself. Rules that arrived via the miner carry a
  small provenance marker, so you can always tell the two apart.
- **"Nothing today" is normal.** On most days everything you emphasized is either
  project-specific or already in memory — the tracker just logs "0 new" and moves on.
- **You can always just read the file.** The tracker is plain markdown at
  `~/.local/share/claude-feedback/proposals.md` — open it anytime.
