# Dependencies

External tools this kit expects. `install.sh` checks them and warns about anything missing.

## Required
- **jq** — merges the kit's hooks into `~/.claude/settings.json` and parses tool input in
  the Edit-over-Write hook.

## For the miner and cross-machine sync
- **claude** CLI, runnable headless (`claude -p`) — the daily miner spawns it. If it isn't
  on `PATH`, the miner falls back to the newest VS Code extension's bundled binary
  (`~/.vscode-server/extensions/…` on Linux/remote, `~/.vscode/extensions/…` on desktop
  incl. macOS).
- **git** — the commit guardrail runs as a git hook; syncing a memory repo needs git.
- **gh** (GitHub CLI) — only if you sync your memory repo to GitHub.

## Platform
- Linux and macOS, stock userland. The scripts stick to POSIX-portable calls (or dual
  GNU/BSD fallbacks, e.g. `stat -c || stat -f`) and run on **bash ≥ 3.2** (macOS's
  default shell) — no Homebrew coreutils needed. `timeout` is used when present and
  skipped when not. CI runs the test suite on both `ubuntu` and `macos`.
