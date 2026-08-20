# Design: the daily feedback loop

> **This is a decision record, not a user guide.** It is dense on purpose: it exists so that
> future changes know what they would be overturning. For how the kit behaves day to day, read
> [FLOWS.md](FLOWS.md). For setup, the README.

    Status:            Implemented
    Last revised:      2026-08-12
    Verified against:  Claude Code 2.1.222
    Supersedes:        docs/DESIGN.md, split by feature 2026-08-12

The loop that reads yesterday's messages, proposes preferences, and remembers what you refused.
Most of these decisions exist because an earlier version lost data quietly.

## D1. Started by your first session of the day, not by cron

Running on session start guarantees a working environment, meaning auth and `PATH`. The miner
reads your own messages out of the session transcripts (O1), skipping the subagent transcripts
nested below them (O2), and it reads "since the last successful run", so idle days delay mining
rather than losing messages.

**Cron was considered and rejected.** It would add mining on days the machine sits unused, which
buys nothing when nothing was said, and costs a second environment to keep healthy.

## D2. The window only advances on a verified write

**An early version advanced its extraction window when the headless session exited zero.** A
session whose only write was denied also exits zero, so a day of messages would have been
skipped. Now the window moves only after the tracker file is confirmed re-written.

Related, and discovered the same way: the tracker lives outside `~/.claude` because a headless
session cannot write inside it (O5). That was found when the miner's first-ever write was
silently blocked.

## D3. Proposals die slowly, not instantly

Rejection is two-strike. A rejected proposal may resurface once, only on fresh evidence spanning
several new days. A second rejection, or an explicit "never", is final.

Both extremes were rejected. A hard "never re-propose" fossilizes a snap judgment made on thin
evidence. Unbounded re-proposal is nagging. One justified re-ask is the compromise.

## D4. The miner may not write absolutes from one-off remarks

A single "no need, leave it" is a judgment about one case, not a standing rule. Turning it into
"never do X" is dangerous precisely when X is a safety or cleanup action.

Candidate rules must match the strength of their evidence, and situational preferences become
"ask first", not "never".

**The review step caught the miner doing exactly this once**, so the phrasing rule moved upstream
into the brief rather than staying a thing the reviewer had to notice.

## D5. Pings speak to both audiences

Every notice is emitted twice in one JSON payload: `systemMessage` for the human and
`additionalContext` for the model, so Claude relays it in its first reply.

**The dual emission exists because the toast-only version ran silently for weeks** in an
interface that never displayed it, and proposals piled up unseen. That is O6, and it is the
weakest-provenance observation in the record.

Repeats are bounded by a once-per-session-per-day marker, keyed on the session id the hook
receives on stdin (O3): resumes and compactions of the same
session stay silent, a new day re-notices, so a week-long session still hears about overdue
reviews, and a missing session id fails open to the old always-notice behaviour.

## D6. Review protocols are skills, not file headers

**The accept/reject protocol first lived in the tracker's header**, written once at file
creation. After the third protocol revision, live trackers still carried the first draft.

A skill is versioned with the plugin that carries it, updated by `claude plugin update` (or `/plugin update` where the host offers it), and invoked
by the natural phrase.
Interactive rituals belong in skills; the miner's headless brief stays a prompt file.

## What would reopen this

- **D1, if the kit ever needed to run on a machine nobody opens a session on.** The whole
  argument rests on a session being the natural trigger for work about that session's user.
- **D3, if the two-strike rule turns out to be either too forgiving or too harsh.** It was chosen
  as a compromise between two rejected extremes, not measured. The tracker holds the data that
  would settle it.
- **D5, if `systemMessage` becomes reliably visible everywhere.** The dual emission is a
  workaround for an interface gap, and O6 has never been re-verified. If that gap closed, the
  duplication would be noise.

## Failure posture

The loop is built so that silence is never mistaken for "nothing to say".

A run that cannot complete leaves the window where it was, so the messages it did not read are
read next time. A blocked feature records the reason rather than exiting quietly, which is what
turns months of no proposals from an ambiguous silence into a reported fault. A missing session
id degrades to notifying every time rather than never. And a rejection is remembered across
reinstalls, because the tracker survives uninstall by default: forgetting what you refused would
mean re-proposing it.
