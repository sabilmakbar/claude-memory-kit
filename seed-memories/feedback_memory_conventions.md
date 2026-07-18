---
name: feedback_memory_conventions
description: Structural rules for writing any memory file — snake_case name==filename (overrides the kebab default), required description, type prefix, and a What/Why/How body with no in-file incident evidence
metadata:
  type: feedback
---

Structural conventions for every memory file written, in global memory AND memory-mounts:

- **`name:` equals the filename slug, in snake_case** — e.g. `feedback_gh_rest_api.md` →
  `name: feedback_gh_rest_api`. This deliberately overrides the harness default that
  suggests a kebab-case slug; kebab names break `[[wikilinks]]` and the generated index.
- **Filename is type-prefixed:** `user_*`, `feedback_*`, or `project_*`.
- **`description:` is required** — one line; it is both the index hook and what recall
  uses to judge relevance, so keep it current when the body changes.
- **Body = What → Why → How.** State the rule/fact directly (the *what*), then `**Why:**`
  (the generalized reason it matters) and `**How to apply:**` (when it fires, what's
  exempt) — for an inherently prescriptive rule, the rule statement itself can carry the
  how, no separate header needed. Do **not** add an `**Evidence**` section or cite a specific incident in a synced
  file — distill any incident's generalizable lesson into Why/How and leave the actual
  quotes, repo, and paths to the miner tracker and git history. Link related memories with
  `[[name]]` targeting their `name:` field.
- **Provenance:** miner-accepted rules carry `source: feedback-miner (P-NNN, accepted date)`
  in metadata; manual saves carry none.
- **Never hand-edit `MEMORY.md` content** — it is regenerated from the files each prompt;
  change a file's `description:` instead.

**Why:** the repo's pre-commit lint enforces these only at commit time and only for global
memory — memory-mounts have no lint, so the in-context convention is their only guard.
Following the harness's kebab default produced repeated broken-wikilink bugs.

**How to apply:** at every memory write — manual saves, miner acceptance, consolidation
rewrites — in both `~/.claude/memory/` and `~/.claude/memory-mounts/`. Content rules
(generality, masking) live in [[feedback_memory_generality]].
