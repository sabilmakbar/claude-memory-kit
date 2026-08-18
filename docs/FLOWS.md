# How the kit behaves

Diagrams of what runs when, plus the specifics [HOW-IT-WORKS.md](HOW-IT-WORKS.md)
deliberately leaves out. The reasons behind each choice live in the five decision records:
[DESIGN-memory.md](DESIGN-memory.md), [DESIGN-miner.md](DESIGN-miner.md),
[DESIGN-guardrail.md](DESIGN-guardrail.md), [DESIGN-install.md](DESIGN-install.md) and
[DESIGN-health.md](DESIGN-health.md). What those decisions rest on, meaning the observed Claude
Code behaviour rather than our choices, is [INTERNALS.md](INTERNALS.md).

One rule keeps this file from growing into a second copy of the plain-language version: a
sentence that also belongs in HOW-IT-WORKS goes there and not here. What lives here is the
diagrams, and the detail a reader has to have asked for.

## Everything that runs in a session

```mermaid
flowchart TD
    subgraph session["Every Claude Code session"]
        UPS[UserPromptSubmit] --> ENGINE[refresh-memory-index.sh<br/>symlink + regenerate index]
        UPS --> DELTA[memory-delta-ping.sh<br/>announce changed memory]
        SS[SessionStart] --> REMIND[memory-review-reminder.sh]
        SS --> PING[feedback-proposals-ping.sh]
        SS --> MINERRUN[run-feedback-miner.sh<br/>once per day, backgrounded]
        SS --> VCHECK[memory-kit-version-check.sh]
        PTU[PreToolUse: Write] --> EOW[edit-over-write.sh<br/>deny Write on existing files]
    end

    subgraph stores["Data"]
        MEM[("~/.claude/memory<br/>global memories + generated index<br/>(optionally a private git repo)")]
        MOUNTS[("~/.claude/memory-mounts<br/>machine-local project memory")]
        TRACKER[("~/.local/share/claude-feedback<br/>proposals tracker + miner state")]
    end

    ENGINE --> MEM
    ENGINE --> MOUNTS
    MINERRUN --> TRACKER
    PING --> TRACKER
    GUARD[guardrail/pre-commit<br/>leak guard + convention lint] --> MEM
    SKILLS[skills: review-feedback-proposals,<br/>review-memories] --> MEM
    SKILLS --> TRACKER
```

Three hook events carry the whole kit. `UserPromptSubmit` fires on every message, which is
why the index can be rebuilt from disk rather than cached. `SessionStart` carries everything
that speaks to you, plus the miner, which runs once a day and in the background so a slow
run never delays a prompt. `PreToolUse` carries one guard, on `Write` only.

Of the three stores, only `~/.claude/memory` can leave the machine. `memory-mounts` is
machine-local by design, and the tracker sits outside `~/.claude` entirely because a headless
session cannot write inside it.

## Where a memory can come from, and what gates it

```mermaid
flowchart LR
    MANUAL["You: 'remember this'"] --> CONV[write-time guard:<br/>denies a file that<br/>misses a rule]
    MINED["Miner proposal accepted<br/>(review skill)"] --> CONV
    CONSOL["/memory-kit:review-memories<br/>consolidation"] --> CONV
    CONV --> FILES[memory files]
    FILES --> INDEX[index regenerated<br/>every prompt]
    FILES --> COMMIT{git commit}
    COMMIT -->|leak guard +<br/>convention lint| REPO[(private repo)]
    COMMIT -->|blocked| FIX[genericize / fix<br/>and retry]
```

Three ways in, one gate out. Every path passes through the same authoring conventions,
because those ship as memory files and are therefore in context at the moment of writing.
The commit gate only exists if you sync; on an unsynced folder the right-hand half of this
diagram never runs.

## The daily loop, and how a proposal ends

```mermaid
flowchart TD
    A[first session of the day] --> B[extract user-typed messages<br/>since last successful run]
    B -->|digest empty| Z[advance window, stop]
    B --> C[headless Claude reads digest<br/>+ memory + guidelines]
    C --> D{candidate is a lasting,<br/>system-wide preference?}
    D -->|already in memory| E[drop / retire]
    D -->|new or partial gap| F[score: frequency, intensity,<br/>novelty, generality + judge pass]
    F --> G[(tracker: Pending,<br/>sorted by score)]
    G --> H[SessionStart ping:<br/>toast + model context]
    H --> I{you review<br/>via skill}
    I -->|accept / rephrase| J[memory file written<br/>per conventions]
    I -->|reject: not now| K[dormant, may resurface<br/>once on fresh evidence]
    I -->|reject: never /<br/>second reject| L[final, never again]
    I -->|leave| G
    J --> M[index picks it up;<br/>guardrail vets the commit]
```

The part worth reading twice is the bottom right. Rejection is two-strike, so "not now" and
"never" are different answers: the first leaves a proposal dormant and lets it return once,
and only on fresh evidence spanning new days; the second is final. "Leave" is a third answer
that changes nothing and keeps the proposal pending.

The window advances only after the tracker is confirmed rewritten, which is why an
interrupted run costs you a delay rather than a day of messages.
