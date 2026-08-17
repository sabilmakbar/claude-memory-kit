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

- **Harness-stamped frontmatter** — `node_type`, `originSessionId` and `modified` keys that
  Claude Code's own writer adds on every save. They carry nothing across machines, and
  `modified` changes on every write, which turns a synced memory repo into commit noise and
  merge conflicts over metadata nobody typed. The index pass reports these and deliberately
  no longer strips them, because a hook cannot ask first. Strip them here: remove only those
  keys, leave every other field and the entire body alone, and drop the trailing space the
  writer leaves after `metadata:`. Never touch a `modified:` that sits in the body rather
  than the frontmatter. Expect them back after the next save; that is the harness, not a
  failed strip.
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

## Check which rules are actually followed

Reading the files asks whether each rule is well written. It never asks the question that decides
a rule's fate: is it obeyed? Some rules leave a machine-checkable trace in the session
transcripts, and for those the answer is countable rather than a matter of impression.

Do this for a handful of rules per review, not all of them. Pick the ones naming a concrete
action, since those are the ones a transcript records.

Extract the tool calls once, then count against them:

```bash
find ~/.claude/projects -name '*.jsonl' ! -name 'agent-*' | while IFS= read -r f; do
  jq -c 'select(.message.content? != null) | .message.content[]?
         | select(type=="object" and .type=="tool_use" and .name=="Bash")
         | .input.command // empty' "$f" 2>/dev/null
done > /tmp/cmds.txt
```

Count the compliant and non-compliant shapes separately, so the result is a rate rather than a raw
number. A rule broken twice out of three times and a rule broken twice out of two hundred call for
opposite responses.

Three traps make these counts wrong, and all three are easy to hit:

- **The audit counts itself.** A command that searches for a pattern contains that pattern, and it
  lands in a transcript too. Exclude the scratch files this pass creates, then re-read the
  surviving matches to confirm each is a real occurrence.
- **A mention is not a use.** A grep pattern, a commit message, or a document discussing the rule
  all match a naive search. Require the verb to sit where a command actually runs, or strip quoted
  spans before matching.
- **One session is not a trend.** Report per-session rates beside the total. A single session can
  be dominated by one task and say nothing about the habit.

What to do with a rule that scores badly, in order of preference:

1. **Memory cannot enforce it.** It governs the shape of the work rather than its output, so
   nothing checks it at the moment it is broken. Propose a hook instead, which is
   [[feedback_tooling_over_memory]] applied to a rule that has now failed in measurement rather
   than in principle. This is the most common outcome and the most useful one.
2. **The rule is unclear.** Sharpen it until what counts as compliance is unambiguous, then
   re-measure at the next review.
3. **The rule is wrong.** One that nobody follows and nobody misses is one to retire. Say so
   plainly rather than leaving it to decay in place.

Never delete a rule quietly because it scored badly. A low rate is evidence about the rule's
mechanism, not permission to drop the intent behind it.

## How to proceed

Present findings as a short proposal list first — explain why each change is needed
before editing (per the user's editing preferences). Apply only what the user approves,
editing files in place; the index regenerates automatically from the files.

Never edit a file's `source:` field. It records where a rule came from, which a review
cannot change: coupling, decoupling, tightening and generalizing all change what a rule
says, not its origin. Describe what you changed in the review commit message instead,
which is where that history stays accurate and syncs to other machines. Treating the
field as a log is what once grew one into a four-event line.

## Wrap up (always, even if nothing changed)

Record the review in the single source of truth:

- **Memory repo has git:** commit the approved changes (one logical change per commit,
  staging and committing as separate steps). The **last** commit's subject must be a
  review marker: `memory review (<machine-label>): <one-line summary>` — machine-label
  is `$MEMORY_KIT_MACHINE_LABEL` if set, else the short hostname (`hostname -s`). If the
  review changed nothing, record it anyway:
  `git commit --allow-empty -m "memory review (<machine-label>): no changes"`.
  Then offer to push — the reminder on every machine reads these markers from git
  history (a marker by any machine covers the synced memories; only a marker from this
  machine's label covers its mount-local memories), so an unpushed marker silences
  only this machine.
- **No git repo:** reset the local stamp instead: `date +%s > ~/.claude/memory/.last-review`
