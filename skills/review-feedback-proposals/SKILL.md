---
name: review-feedback-proposals
description: Walk the user through pending auto-mined feedback proposals (accept/reject/rephrase). Use when the user says "review feedback proposals", invokes /review-feedback-proposals, or responds to a session-start ping about pending proposals.
---

# Review feedback proposals

The tracker is `~/.local/share/claude-feedback/proposals.md`. Read it first.
If `## Pending` is empty, tell the user there is nothing to review and stop.

## Walk Pending top-down (it is sorted by score)

For each entry, present it **in full** — the complete proposed rule, the "in practice"
line (when it fires / what's exempt), kind (new-rule or amendment + the gap), scores with
the judge note, and the evidence quotes. Never present just the title.

Collect the decision with a question dialog whose question text **embeds the rule,
scope, and evidence gist** — the dialog must be self-contained; never assume the user
read the chat text above it. Options: Accept / Reject / Rephrase first / Leave pending.

## Executing decisions

Before executing any **Accept**, sync the memory repo if it has a remote
(`git -C ~/.claude/memory pull --ff-only`) so the new rule lands on top of other
machines' latest memories — then re-check the accepted rule isn't already covered by a
freshly pulled file (if it is, follow the Accept bookkeeping but point the tracker entry
at the existing file instead of writing a duplicate).

- **Accept** → create the rule in the user's global memory, following the memory-authoring
  conventions: **What / Why / How** format, stated **project-agnostic**, with **no in-file
  Evidence section** — the incident (quotes, repo, paths) stays in this tracker and git
  history, never in the synced memory file. Mark provenance
  in the file's metadata: `source: feedback-miner (P-NNN, accepted YYYY-MM-DD)`. Then move the
  tracker entry to `## Accepted`, appending `- **reviewed:** <date> · accepted → <file>`.
- **Rephrase first** → ask for (or propose) better wording, get their confirmation, then
  follow the Accept path with their wording.
- **Reject** → ask whether it's "not now" (default) or "never". Move the entry to
  `## Rejected` with `- **rejected:** <date> · <one-line reason>`; append `(final)` to
  the rejection line if "never", or if this entry was already a `[resurfaced]` item
  (second rejection is automatically final). Never delete Rejected entries — the miner
  uses them to avoid re-proposing.
- **Leave pending** → keep the entry untouched.

## Wrap up

Summarize what was decided in one short list. If the user's memory lives in a git repo,
offer to commit the new memory files (following their commit workflow), and to push so
other machines' miners see the accepted rules on their next daily pull.
