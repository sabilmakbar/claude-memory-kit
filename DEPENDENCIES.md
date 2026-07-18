# Dependencies

External tools this kit expects. `install.sh` checks them and warns about anything missing.

## Required
- **jq** — merges the kit's hooks into `~/.claude/settings.json` and parses tool input in
  the Edit-over-Write hook.

## For the miner and cross-machine sync
- **claude** CLI, runnable headless (`claude -p`) — the daily miner spawns it. If it isn't
  on `PATH`, the miner falls back to the newest VS Code extension's bundled binary
  (`~/.vscode-server/extensions/anthropic.claude-code-*/resources/native-binary/claude`).
- **git** — the commit guardrail runs as a git hook; syncing a memory repo needs git.
- **gh** (GitHub CLI) — only if you sync your memory repo to GitHub.

## Platform
- Scripts assume **GNU coreutils** behavior (`df --output`, `sed -E`, `stat -c`). Default on
  Linux; on macOS install `coreutils`/`gnu-sed` or adjust the calls.
