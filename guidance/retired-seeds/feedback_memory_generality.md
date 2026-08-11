---
name: feedback_memory_generality
description: Feedback/memory rules must be stated project-agnostic — no incident evidence in synced files; specifics stay in the tracker and git history
metadata:
  type: feedback
---

When writing or mining feedback/memory entries, state the rule itself project-agnostic — repo, file, project, and person names must never appear in the rule, **Why**, or **How to apply** prose, where they make a general preference read as tied to one codebase.

**Why:** a rule phrased around one project looks non-transferable and won't be applied elsewhere, even when the preference is system-wide. Naming a work repo or handle also copies it into memory that syncs across machines, outside the access controls of the project it came from.

**How to apply:** state the rule in general terms, and distill whatever incident motivated it into the generalized reason (**Why**) and application (**How to apply**) — not a cited example. Do not add an **Evidence** section to a synced memory file; the concrete incident (quotes, repo, paths) stays in the machine-local miner tracker and git history, which are traceable but never synced. Exempt: project-memory files under `memory-mounts/`, project-specific by design and never synced.

Related: [[feedback_editing]].
