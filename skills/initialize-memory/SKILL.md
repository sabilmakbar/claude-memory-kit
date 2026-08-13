---
name: initialize-memory
description: Finish memory setup after install by bringing existing memory stores into one and reworking what collides. Use when the user says "initialize memory", "finish memory setup", "consolidate my memory stores", or responds to a notice that staged memory files are waiting.
---

# Initialize memory

Install is mechanical: it names the store and writes nothing to a memory file. This skill is the
second half, where anything that moves, rewrites or deletes memory happens with a person present.
See `docs/DESIGN-memory.md` D8 and D10.

## Before anything: the mode decides who executes

Read it once and obey it throughout:

```bash
grep -m1 '^MEMORY_KIT_MODE=' ~/.claude/memory-kit/config | cut -d= -f2
```

- **managed** — you make each change, after stating what you intend and getting a yes.
- **advisory** — you write nothing at all. You produce the plan and the user applies it. Say so
  at the start, so nobody waits for changes that are not coming.

If the file or key is missing, stop and tell the user to re-run
`~/claude-memory-kit/install.sh --mode=managed` or `--mode=advisory`. Do not pick for them.

## Step 1: check whether there is anything to do

```bash
jq -r '.initialized // "no"' ~/.claude/memory/.memory-kit-marker.json 2>/dev/null
ls -d ~/.claude/memory/.staged/*/ 2>/dev/null
```

A timestamp in `initialized` and no `.staged/` means setup is finished. Say so and stop. To run
again the user deletes the `initialized` field, which is deliberate rather than a flag passed by
accident.

Anything else means there is work, and it resumes from wherever it stopped.

## Step 2: bring the stores in

Only if `.staged/` does not exist yet. Read the record of stores install found:

```bash
jq -r '.stores[]' ~/.local/share/claude-memory-kit/stores.json 2>/dev/null
```

For each store, copy it into its own folder. **Copy, never move.** The source is what makes this
undoable, so it is never touched, never emptied and never deleted, not even at the end.

```bash
mkdir -p ~/.claude/memory/.staged/<source-tag>
cp ~/.claude/projects/<encoded>/memory/*.md ~/.claude/memory/.staged/<source-tag>/
```

Pick `<source-tag>` from the store's own path so a person can tell where each file came from.
Per-source folders are the whole reason collisions cannot happen: two stores may each hold
`user_profile.md`, and one flat copy would lose one of them.

## Step 3: promote everything that needs no judgement

A staged file moves to the store root when **both** hold:

1. its name is free at `~/.claude/memory/`
2. its name matches `user_*.md` or `feedback_*.md`

That is two string tests. Do not read the file to decide. Promote every file that passes, then say
how many went live. This is what stops the user's memory going dark while the rest is sorted out.

## Step 4: rework what is left, one group at a time

What remains is names that collide and names that do not conform, which is exactly the set that
needs a person. Work in small groups, never all at once.

For each group, read the files and decide which shape fits:

- **one into several** when a file holds two unrelated ideas
- **several into one** when they say the same thing in different words
- **a rewrite in place** when the content is right and the name or frontmatter is not
- **many into many** when a regrouping by topic reads better than either original

Then, for that group:

1. Say what you intend: which staged files, which files result, and what is dropped as duplicated.
2. In managed, wait for a yes. In advisory, stop here and let the user write it.
3. Write the new files at the store root, conforming to `guidance/` and the naming rules.
4. **Only once the content is carried across**, delete the staged originals for that group.

Step 4 is what makes an interruption safe. A staged file still on disk means its content has not
landed yet, so a resumed run picks up exactly where it stopped and nothing is lost in between.

Never delete a staged file because it looks redundant. It goes only when its content lives
somewhere else.

## Step 5: finish

When `.staged/` is empty, remove it, then stamp the marker:

```bash
rmdir ~/.claude/memory/.staged
jq --arg t "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '.initialized = $t' \
   ~/.claude/memory/.memory-kit-marker.json > /tmp/mk.$$ && mv /tmp/mk.$$ ~/.claude/memory/.memory-kit-marker.json
```

Then tell the user what to check: the index rebuilds on the next prompt, so a new session should
show every promoted and reworked memory in `~/.claude/memory/MEMORY.md`.

In advisory, do not stamp anything. Nothing was written, so setup is not finished.

## If the memory store is a git repo

Suggest committing at the end, as one logical change, and leave the commit to the user. The kit
does not commit in someone's repo.

## What this skill never does

- Touch a source store. It is copied from and nothing else.
- Merge two stores without saying which files and which result first.
- Delete a staged file whose content has not been written somewhere else.
- Write anything at all in advisory mode.
