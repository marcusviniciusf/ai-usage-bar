# AI Usage Bar

macOS 14+ menu bar app that shows AI tool spend and subscription quota. One SwiftUI file plus a Python collector. English, Portuguese and Spanish UI.

## Layout

- `main.swift` — app, panel, menu bar indicator, preferences, notifications. Built by `build.sh` into `~/Applications/AI Usage.app`.
- `bin/ai-usage` — collector the app runs as a separate process per tool; prints one JSON payload. Also the `ai-usage` CLI for preferences.
- `bin/cursor-spend` — Cursor dashboard helper the collector loads.
- `tests/` — collector unit tests (`test_collector.py`) and `check_swift.py`, which compiles the real app models against old and current payloads.
- `docs/REFERENCE.md` — behaviour users care about (detection, budgets, modes, flags). `docs/STATUS.md` — current validated state.
- `tasks/ai-usage/tasks.json` — local backlog (`tasks list`, `tasks new ai-usage`, `tasks done`).

## Commands

```bash
python3 -m unittest discover -s tests -v
python3 tests/check_swift.py          # needs rtk and the legacy commit 2bfe2d7
./build.sh                            # compile, install, relaunch the app
./install.sh                          # collectors to ~/.local/bin, ccusage, then build
~/Applications/AI\ Usage.app/Contents/MacOS/AIUsage --snapshot /tmp/out.png Today
```

## Constraints

- The app launches the collector with `/usr/bin/python3` (3.9) and `~/.local/bin/ai-usage`: keep the collector stdlib-only and 3.9-compatible.
- Reads must stay read-only towards provider accounts: never start a turn, change auth, reset credits, or spend money.
- Costs from local logs are API list-price estimates, never invoices or account balances; label them that way in UI and docs.
- Nothing leaves the Mac except calls to the providers' own endpoints (Cursor dashboard, `codex app-server`, DeepSeek logs stay local).
- Keep the payload backward compatible: an old app binary must decode a new collector payload, and a new app must read old payloads.
- On macOS 14, no third-party Swift packages and no new runtime dependencies.
