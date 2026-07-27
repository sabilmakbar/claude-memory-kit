---
name: review-memories
description: Periodic health check of Claude's memory files — merge overlaps, fix stale facts, then reset the review-due reminder. Use when the user says "review my memories" or responds to the session-start "memory review due" reminder.
---

# Review memories

Sync first if the repo has a remote (`git -C ~/.claude/memory pull --ff-only`) so the
review covers the latest memories, not this machine's possibly-stale copies — then read
`~/.claude/memory/MEMORY.md` and every memory file it lists (plus the current
mount's entries under `~/.claude/memory-mounts/` if present).

## What to look for

- **Overlaps / merge candidates** — two files covering the same rule; propose a merge.
- **Stale content** — facts or references that later sessions have superseded; rules
  contradicted by newer feedback files.
- **Broken structure** — `[[wikilinks]]` that don't resolve to an existing `name:`,
  descriptions that no longer match the body, missing frontmatter fields.
- **Over-specific rationales** — "why" lines tied to one incident: generalize the reason
  into a system-wide one and remove the incident citation (quotes, repo, and paths belong
  in the miner tracker and git history, never in a synced memory file).
- **Non-conforming / unindexed files** — files flagged by the index's "Unindexed files"
  warning, or any memory file with a non-conforming name or missing frontmatter (typical
  after adopting pre-kit memories): propose renames to `user_*`/`feedback_*` (move
  project-specific ones to the mount dir) and fill in `name:`/`description:` so they
  (re)enter the index.
- **CLAUDE.md guideline hygiene** — if the memory repo carries a `CLAUDE.md`, review its
  `## Source:` sections too: attribution follows the header's convention (publicly
  available → cite name + URL; otherwise "distilled internally" / "created manually",
  never naming a private origin), and no section carries project- or work-specific
  content that belongs in the owning repo's own `CLAUDE.md`.
- **Stable-fact creep in project memories** — mount project files accumulating durable
  facts (run commands, layout rules, infra details, settled findings): propose
  graduating those into that project's own repo `CLAUDE.md` and shrinking the memory
  file back to volatile state (current progress, pending decisions) plus a pointer.

## How to proceed

Present findings as a short proposal list first — explain why each change is needed
before editing (per the user's editing preferences). Apply only what the user approves,
editing files in place; the index regenerates automatically from the files.

## Wrap up (always, even if nothing changed)

Record the review in the single source of truth:

- **Memory repo has git:** commit the approved changes (one logical change per commit,
  staging and committing as separate steps). The **last** commit's subject must be a
  review marker: `memory review (<machine-label>): <one-line summary>` — machine-label
  is `$MEMORY_MACHINE_LABEL` if set, else the short hostname (`hostname -s`). If the
  review changed nothing, record it anyway:
  `git commit --allow-empty -m "memory review (<machine-label>): no changes"`.
  Then offer to push — the reminder on every machine reads these markers from git
  history (a marker by any machine covers the synced memories; only a marker from this
  machine's label covers its mount-local memories), so an unpushed marker silences
  only this machine.
- **No git repo:** reset the local stamp instead: `date +%s > ~/.claude/memory/.last-review`
