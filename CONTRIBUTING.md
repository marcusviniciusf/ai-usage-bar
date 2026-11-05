# Contributing

Thanks for looking. This is a small project: one SwiftUI source file and two Python collectors. Keep changes scoped and the diff readable.

## Setup

```bash
git clone https://github.com/marcusviniciusf/ai-usage-bar.git
cd ai-usage-bar
./build.sh
```

Requires macOS 14+ and Xcode Command Line Tools. Bun or npm is only needed for the Claude Code and OpenCode collectors (`ccusage`).

## Before opening a PR

```bash
python3 -m unittest discover -s tests -v
python3 tests/check_swift.py
./scripts/build_app.sh /tmp/ai-usage-build
```

All three must pass. The app must still decode payloads produced by older collector versions; `check_swift.py` compiles the previous wire model for that.

## Rules

- The collector runs under `/usr/bin/python3` (3.9): standard library only, no new dependencies.
- Reads must stay read-only towards provider accounts: never start a turn, change auth, reset credits or spend money.
- Costs from local logs are estimates, never invoices. Say so in UI copy and docs.
- Nothing leaves the Mac except calls to the providers' own endpoints.
- Keep the JSON payload backward compatible: an old app binary must decode a new collector payload.
- UI text goes through `tr()` with entries in the English, Portuguese and Spanish tables.
- Screenshots use fictional demo data, rendered by `scripts/render_demo_screenshots.py`.

## Adding a tool

1. Add a collector function to `bin/ai-usage` that returns the shared cost payload (`today`, `week`, `month`, `daily`, `models`, `chats`, `rate`).
2. Append it to `SOURCES` so budgets, alerts, pinning and CLI flags pick it up automatically.
3. Add detection in `detected_sources()`.
4. Add a palette, a fallback SF Symbol and, if the tool ships a macOS app, an icon name in `Tool`/`ToolAppIcon` in `main.swift`.
5. Add tests with fixture logs, and document pricing assumptions in `docs/REFERENCE.md`.

## Reporting bugs

Use the issue templates and include your macOS version, the affected tool, and the collector error text. Never paste tokens, session contents or account balances.
