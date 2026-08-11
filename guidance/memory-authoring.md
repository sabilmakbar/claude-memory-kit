# Writing a memory file

Guidance for whoever is about to save a memory. It lives with the kit rather than in
your memory folder, so it costs nothing to keep and cannot drift out of sync with the
checks that enforce it.

The mechanical rules below are enforced by `hooks/memory-write-guard.sh` at the moment
of writing, and three of them again by the commit guardrail. The judgement calls at the
bottom cannot be checked by any hook, which is the whole reason this document exists.

## Template

```markdown
---
name: feedback_short_slug
description: One line, stating the rule, used as the index entry and for recall
metadata:
  type: feedback
---

The rule itself, stated directly, in a sentence or two.

**Why:** the generalized reason it matters, with no reference to the incident that
prompted it.

**How to apply:** when it fires and what is exempt. Optional when the rule statement
already carries it. Link related memories with [[their_name]].
```

## Enforced when you write

- **Filename is type-prefixed:** <!-- rule: filename-prefix --> `user_`, `feedback_` or `project_`. Facts about the
  person are `user_`, behavioural rules are `feedback_`, project-specific notes are
  `project_` and live in memory-mounts rather than global memory.
- **`name:` equals the filename slug** <!-- rule: name-matches-slug -->, in snake_case. The generated index and every
  `[[wikilink]]` resolve through it. The harness suggests kebab-case, which breaks both,
  so this deliberately overrides it.
- **`description:` is required.** <!-- rule: description-required --> It is the index line and what recall reads to decide
  whether the file is worth loading, so keep it current when the body changes.
- **`metadata.type` is required:** <!-- rule: type-required --> user, feedback, project or reference.
- **A `feedback_` rule needs `**Why:**`.** <!-- rule: why-required-for-feedback --> A rule with no stated reason gets ignored or
  misapplied once the original context is gone.
- **No Evidence section in global memory.** <!-- rule: no-evidence-when-synced --> Quotes, repo names and paths stay in the
  miner tracker and git history. Global memory syncs to a personal GitHub repo, so the
  leak surface was removed structurally rather than policed.

## Not enforced, still expected

- **`**How to apply:**` is optional.** A prescriptive rule can carry its own how. Add
  the section when there is a real "fires when / exempt when" to state.
- **A `[[wikilink]]` may point at a memory that does not exist yet.** That marks
  something worth writing later, so links are never resolved by the check.
- **Never hand-edit `MEMORY.md`.** It is regenerated from the files on every prompt;
  change a file's `description:` instead.

## Judgement, which no check can make for you

- **Is this worth remembering at all?** A single "no, leave it" is a decision about one
  case, not a standing rule. Situational preferences become "ask first", never "never".
- **Could tooling own this instead?** If the behaviour is mechanical enough for a hook
  or script to enforce, build that rather than writing a memory. Memory is for what
  tooling structurally cannot hold: phrasing, framing, habits and judgement.
- **State it project-agnostically.** A rule that names an employer, a client or a path
  cannot live in a repo that syncs.
- **Match the strength of the evidence.** One calm remark is not "always"; a repeated,
  emphatic correction is.
