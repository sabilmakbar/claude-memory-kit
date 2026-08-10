# Dependencies

Tools the kit expects. `install.sh` checks for them before it does anything: a missing
`jq` stops the install, and the others are only reported, because the kit still works
without them. The report tells you which features will sit idle.

## Required
- **jq**. Merges the kit's hooks into `~/.claude/settings.json` and parses hook input.

## For the miner and cross-machine sync
- **claude** CLI, runnable headless (`claude -p`). The daily miner spawns it. If it is
  not on `PATH`, the miner falls back to the newest VS Code extension's bundled binary
  (under `~/.vscode-server/extensions` on Linux/remote, `~/.vscode/extensions` on
  desktop including macOS).
- **git**. The commit guardrail runs as a git hook, and syncing a memory repo needs it.

## Optional
- **gh** (GitHub CLI). Only for the setup shortcuts in the README. Sync is plain `git`,
  so any credential setup works: a keychain helper, an SSH key, or one of your own.

## Platform
Linux and macOS with their stock userland. The scripts stick to portable calls (with
dual GNU/BSD fallbacks such as `stat -c || stat -f`) and run on bash 3.2, the macOS
default. No Homebrew coreutils needed. `timeout` is used when present and skipped when
not. CI runs the test suite on both `ubuntu` and `macos`.
