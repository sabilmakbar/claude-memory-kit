---
name: review-memories
description: Periodic health check of Claude's memory files — merge overlaps, fix stale facts, then reset the review-due reminder. Use when the user says "review my memories" or responds to the session-start "memory review due" reminder.
---

# Review memories

Read `~/.claude/memory/MEMORY.md` and every memory file it lists (plus the current
mount's entries under `~/.claude/memory-mounts/` if present).

## What to look for

- **Overlaps / merge candidates** — two files covering the same rule; propose a merge.
- **Stale content** — facts or references that later sessions have superseded; rules
  contradicted by newer feedback files.
- **Broken structure** — `[[wikilinks]]` that don't resolve to an existing `name:`,
  descriptions that no longer match the body, missing frontmatter fields.
- **Over-specific rationales** — "why" lines tied to one incident that should be
  generalized (keep the incident as an example, not as the rule).

## How to proceed

Present findings as a short proposal list first — explain why each change is needed
before editing (per the user's editing preferences). Apply only what the user approves,
editing files in place; the index regenerates automatically from the files.

## Wrap up (always, even if nothing changed)

1. Reset the reminder stamp: `date +%s > ~/.claude/memory/.last-review`
2. If changes were made, offer to commit them in the memory repo (one logical change
   per commit, staging and committing as separate steps).
