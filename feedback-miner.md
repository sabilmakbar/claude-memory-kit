# Feedback miner — daily headless run

You are running as an unattended daily job. Your only output is the tracker file
`~/.local/share/claude-feedback/proposals.md`. Do not ask questions; do not touch any
other file except the tracker. Be terse.

## Inputs (read all before writing anything)

1. `~/.local/share/claude-feedback/digest-latest.txt` — user-typed messages since the last
   run, tagged `[project/session timestamp]`. If missing/empty: append a Daily-log row
   noting 0 messages and stop.
2. `~/.claude/memory/MEMORY.md` and every `~/.claude/memory/*.md` — current memory.
3. `~/.claude/CLAUDE.md` — current global guidelines.
4. `~/.local/share/claude-feedback/proposals.md` — the tracker (create from the template
   below if missing).

## What counts as a candidate

A **system-wide behavioral rule** the user seems to want from Claude in general — not a
task instruction for one session. Signals, strongest first:

- **Corrections / rejections**: "no, do X instead", a rejected edit followed by a
  re-instruction, "I told you", "again".
- **Repetition**: the same instruction phrased across ≥2 sessions or days.
- **Emotional emphasis**: frustration, exclamations, ALL-CAPS, "always"/"never" phrasing.
- **Stated preferences**: "I want…", "from now on…", "by default…".

Not candidates: one-off task directions, project-specific facts (those belong to
mount-local memory, not here), anything fully covered by an existing memory file or
CLAUDE.md section.

## Complementarity check (do this per candidate, before scoring)

Compare against memory + CLAUDE.md:
- **Fully covered** → drop it (novelty 0).
- **Partially covered** → keep as an *amendment* proposal: name the existing file and
  state exactly the uncovered gap.
- **Uncovered** → new-rule proposal.

## Scoring (1–5 each) and judging

- **frequency** — distinct sessions/days it appears in (1 = once, 5 = daily habit).
- **intensity** — strength of emphasis (1 = mild mention, 5 = frustrated correction).
- **novelty** — how uncovered it is (0 = drop; 5 = nothing like it in memory).
- **generality** — how system-wide (1 = narrow situation, 5 = applies everywhere).

`total = 2*frequency + 1.5*intensity + 1.5*novelty + generality` (max 30).

**Judge pass:** after scoring all candidates, re-read each score against its evidence
and adjust anything inflated or understated; write a one-line judge note per entry
(e.g. "freq held at 2 — same session repeated, not cross-session").

## Updating the tracker

- **Match first** against ALL existing entries (Pending, Accepted, Rejected):
  - Matches **Pending** → append new evidence (max 3 quotes kept, ≤140 chars each,
    count the rest), update `last_seen`, increment `days_seen`, rescore, re-judge.
  - Matches **Rejected** → do NOT re-propose. Optionally add one `resurfaced:` line
    under the rejected entry with the new date.
  - Matches **Accepted** → skip.
- New candidates get the next `P-NNN` id.
- Keep `## Pending` sorted by total score, descending (the session-start ping shows the top one).
- Keep entries compact; keep the file under ~300 lines by trimming old evidence.
- Append one row to `## Daily log`.

## Tracker template (when creating the file)

```markdown
# Feedback proposals (auto-mined daily)
> Say **"review feedback proposals"** in any Claude session to accept/reject pending items.
> Accepted → add it to your global Claude memory (or CLAUDE.md). Rejected → stays here
> so it is never re-proposed.

## Pending

## Accepted

## Rejected

## Daily log
| date | msgs | sessions | new | bumped |
|------|------|----------|-----|--------|
```

## Entry format

```markdown
### P-001 · total 21.5 · <short title>
- **proposed rule:** <one/two sentences, written as a feedback memory would be>
- **kind:** new-rule | amendment(<existing_file.md>: <gap>)
- **scores:** freq N · intensity N · novelty N · generality N — **judge:** <one line>
- **evidence:** [YYYY-MM-DD proj/sess] "quote" · [..] "quote" (+K more)
- **first_seen:** YYYY-MM-DD · **last_seen:** YYYY-MM-DD · **days_seen:** N
```
