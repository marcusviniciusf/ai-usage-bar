# AI Usage

macOS menu bar app showing today/week/month spend for Cursor, Claude Code and OpenCode.

## Install

```bash
./install.sh
```

Needs macOS 14+, Xcode Command Line Tools (`xcode-select --install`) and bun or npm.
The first refresh asks for Keychain access to "Cursor Safe Storage": choose **Always Allow**.

## Pieces

- `bin/ai-usage` — collector, prints JSON.
- `bin/cursor-spend` — Cursor dashboard API using the editor's local session. Also a CLI (`cursor-spend today`).
- `main.swift` / `build.sh` — SwiftUI app, installed to `~/Applications/AI Usage.app`.

Claude Code and OpenCode come from local logs via `ccusage`. Each Mac shows only its own usage.

## Updating

Edit in this repo. Scripts in `~/.local/bin` are symlinks here, so collector changes apply on the next refresh.
After changing `main.swift`, run `./build.sh`. After `git pull` on another Mac, run `./install.sh` once.

## Alerts

Notifications at 80% and 100% of the daily budget, each at most once per day (checked every 10 min).
Test them with the cached numbers: `~/Applications/AI\ Usage.app/Contents/MacOS/AIUsage --test-alert`.
Native notifications from "AI Usage" (System Settings → Notifications → AI Usage).

## Pace

Hero shows combined $/h (Cursor last hour, Claude active 5h block) and how long until the daily budget at that pace.
The 80% notification includes the same ETA. Expanding Cursor lists today's most expensive chats.
`build.sh` renders the app icon itself (`AIUsage --icon`), no assets to keep.

## Daily budget

Per Mac, default $60. Set it with:

```bash
ai-usage --set-budget 80
```

That writes `dailyBudget` to `~/.config/ai-usage/config.json` (edit by hand works too). The env var
`AI_USAGE_DAILY_BUDGET` overrides the file. Applies on the next refresh (10 min) or after reopening the app.

Top chats today: Cursor from the dashboard, Claude from session titles in `~/.claude/projects`, OpenCode from its DB.
A session's cost is its lifetime total, so a session spanning several days counts fully.
