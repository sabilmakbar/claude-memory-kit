# Dependencies

Tools the kit expects. `install.sh` checks for them before it does anything: a missing
`jq` stops the install, and the others are only reported, because the kit still works
without them. The report tells you which features will sit idle.

## Required
- **jq 1.5 or newer**. Merges the kit's hooks into `~/.claude/settings.json`, parses hook
  input, and lints memory frontmatter at commit time. Without it `install.sh` stops before
  changing anything. The 1.5 floor is the regex functions (`capture`, `gsub`, named
  captures); nothing here needs 1.6 or later, so any `jq` you are likely to already have
  will do. Developed against 1.7.

## Required for the other half of the install

- **the `claude` CLI**, to install the plugin that carries the skills. `install.sh` gives you
  the hooks, the kit tree and the config; the skills come from `claude plugin marketplace add`
  and `claude plugin install`, and neither half works alone. This is separate from the runtime
  use below: the miner spawns the CLI headless, while this is an install-time requirement, and
  `install.sh` reports which half is missing rather than assuming.

  If the CLI is not on `PATH` it ships inside the VS Code extension, at
  `~/.vscode/extensions/anthropic.claude-code-*/resources/native-binary/claude`.

## Used when you use the feature
- **claude** CLI, runnable headless (`claude -p`). The daily miner spawns it. If it is
  not on `PATH`, the miner falls back to the newest VS Code extension's bundled binary
  (under `~/.vscode-server/extensions` on Linux/remote, `~/.vscode/extensions` on
  desktop including macOS).

  On a machine where you do not want the miner at all, say so instead of letting the
  dependency go unmet: uncomment `MEMORY_KIT_NO_MINER=1` in
  `~/.claude/memory-kit/config`. A missing `claude` CLI and a deliberate opt-out look
  identical to the kit otherwise, and it reports the first as a fault after three days.
- **git**. Three features need it: the commit guardrail, which runs as a git hook and blocks
  emails, home paths, your private terms and malformed memory files before they can be
  committed, syncing your memory folder as a repo, and the deploy-drift check, which runs in a
  development checkout as a post-merge, post-checkout and post-rewrite hook and says when a
  pull has left the deployed tree behind. Without git none of them run; memory, the index and
  the miner carry on.

## Platform
- **bash, including 3.2**, the version macOS still ships. The scripts target it rather
  than assuming a newer bash from Homebrew.
- **macOS and Linux** with their stock userland, no Homebrew coreutils needed. Portable
  calls throughout, with dual GNU/BSD fallbacks such as `stat -c || stat -f`. `timeout`
  is used when present and skipped when not. CI runs the suite on `ubuntu` and `macos`.
- **Claude Code** itself. The kit reads its undocumented internals, so a version-check
  hook re-runs the real-data suite after an update and records the result.

## Never used
No network calls, no package installs, no daemons, no telemetry. The kit is files reading
files, plus one local `claude` call a day if you leave the miner on.
