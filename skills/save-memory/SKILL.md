---
name: save-memory
description: Write a new memory file, or amend an existing one, following this machine's memory conventions. Use when the user says "remember this", "save this preference", "add this to memory", or asks for a correction to be made permanent.
---

# Save a memory

Read `~/.claude/memory-kit/guidance/memory-authoring.md` first. It carries the template,
the rules a write-time hook enforces, and the judgement calls no hook can make. Do not
work from memory of the conventions; the file is the current version.

Then:

1. **Decide whether memory is the right home at all.** If the behaviour is mechanical
   enough for a hook or script to enforce, say so and offer to build that instead. Memory
   is for phrasing, framing, habits and judgement.
2. **Decide the tier.** Project-agnostic preferences go to `~/.claude/memory/`. Anything
   naming a project, a path, or an employer goes to the current mount's folder under
   `~/.claude/memory-mounts/`, which never syncs.
3. **Check for an existing file that already covers it.** Amend that rather than adding a
   near-duplicate; the index gets noisier with every overlap. If the memory folder has a
   remote, pull first so you are not amending a stale copy.
4. **Write it to the template.** State the rule, then why, then when it fires. Keep the
   incident out of the file.
5. **Say what you wrote and where**, in one line, so the user can correct the wording
   while it is still fresh.

The write-time hook will refuse a file that misses an enforced rule and name the rule it
missed. Treat that as the check working, fix the file, and write again.
