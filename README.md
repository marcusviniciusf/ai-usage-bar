# AI Usage

A macOS menu bar app for AI tool consumption and subscription quotas. Requires macOS 14+.

## Install

```bash
./install.sh
```

Requires Xcode Command Line Tools and Bun or npm. Installs to `~/Applications/AI Usage.app`.
Scripts in `~/.local/bin` are symlinks to this checkout. Rebuild Swift changes with `./build.sh`.

## Automatic detection

Only detected tools appear. Cursor is detected by its app or local database; Claude Code by its CLI or projects directory; OpenCode by its CLI or data directory; Codex by its CLI, including the CLI bundled with ChatGPT or Codex.
A detected tool with a collection error stays visible. Missing tools are hidden.
Cursor dashboard access uses its existing local login and may ask for Keychain access.

## Two monitoring modes

- **Subscription quotas:** Codex shows current account quota windows and reset times from the official local app-server `account/rateLimits/read` method. This is account-wide usage, including other devices, and is separate from ChatGPT browser conversations. No turns, logins, credit resets or purchases are initiated.
- **Cost:** OpenCode, Claude Code and Cursor show local usage costs. Each tool can optionally have a daily or monthly USD budget. Without a budget, only consumption is shown. Estimates from logs are not invoices. OpenCode totals, history, models and top sessions exclude model IDs ending in `-free` or `:free` (case-insensitive), plus the exact ID `free`. Mixed sessions include only non-free model costs. Unknown free tiers without those markers cannot be inferred from the name. If per-model costs are unavailable, the tool reports an error rather than using an unfiltered total. Cursor's month value follows its billing period.

The menu bar defaults to a compact combined summary: the most consumed subscription quota remaining (percent) plus today's combined cost (USD), identified by icons. Fixed and urgent modes also use compact values; percentages always mean remaining capacity. Full tool names and details remain in the tooltip and app window. In the app settings (gear button), choose combined summary, a fixed tool, or the quota/budget closest to its limit. The urgent mode compares subscription windows, per-tool budgets and the optional global budget; without a limit it falls back to the summary. Data refreshes every five minutes or with the refresh button.
The chart only combines tools with cost data. Subscription percentages are never converted into dollars or added to that chart.

## Per-tool preferences

Use the settings menu beside each tool. Cost tools offer an optional budget editor; all tools offer an alert toggle.
Preferences live in `~/.config/ai-usage/config.json` (or `$XDG_CONFIG_HOME/ai-usage/config.json`).
Existing `dailyBudget` values and `AI_USAGE_DAILY_BUDGET` retain their original global daily meaning. They are never split into tool budgets. The optional global budget is shown separately and excludes subscription quotas. It coexists with individual tool budgets and has its own 80%/100% alerts; incomplete cost collection suppresses global budget alerts.
New installations have no global budget unless configured. On this Mac, `globalBudget: null` explicitly disables it while preserving the legacy key. The environment override has precedence.
The collector retains the old numeric `budget` JSON field so existing binaries keep decoding after `git pull`; the updated app distinguishes that compatibility field from the optional `globalBudget`. Old binaries continue their original budget behavior until rebuilt. The new app can also read old collector payloads.
Update another Mac with `git pull` and `./install.sh`. Its own configuration is preserved; this Mac's preferences are not copied.

```bash
ai-usage --set-budget 80  # global daily budget; original command preserved
ai-usage --set-budget 0   # disable global budget in the new app
ai-usage --set-indicator summary
ai-usage --set-indicator urgent
ai-usage --set-indicator fixed opencode
ai-usage --set-tool-budget opencode daily 10
ai-usage --set-tool-budget opencode monthly 100
ai-usage --set-tool-budget opencode monthly 0  # remove budget
ai-usage --set-alerts codex off
```

Budget settings are advisory and never block tools. Alerts fire at 80% and 100%, deduplicated by tool and quota reset or calendar period. Notifications require macOS permission.
OpenCode and Claude top sessions show lifetime session cost and may span multiple days; the UI labels this separately from today's models.
Enable automatic startup with **Iniciar com o Mac**.

## Validation

```bash
python3 -m unittest discover -s tests -v
python3 tests/check_swift.py  # compiles actual old and new Swift models
./build.sh
```

Render the current cached view without changing preferences:

```bash
~/Applications/AI\ Usage.app/Contents/MacOS/AIUsage --snapshot /tmp/ai-usage.png Today
```

## Pace and forecasts

- **Cost:** with a global budget set, the Hoje/Semana/Mês picker scales it by the days elapsed (daily budget × days, weeks start Monday) and shows the % used. On Hoje it also shows the combined $/h (Cursor last hour, Claude active 5h block) and how long until the limit at that pace.
- **Quota:** each Codex window projects linearly from usage so far, either "esgota em ~Xh, antes de renovar" or the expected % at renewal. Needs a used window of at least 10 minutes.
- The 80% notifications (global budget and quotas) include the same ETA.

## Panel layout

Compact by default (about 420pt tall): hero, one row per tool, collapsed 14-day chart. Tap a tool row to expand models, sessions, budget and plan details; per-tool options live in its **Opções** menu. App settings (bar indicator, global budget, launch at login, quit) are in the gear menu, a native menu, so they open instantly.
Preference changes apply immediately in the UI and are persisted in the background. Cursor events are cached in `~/Library/Caches/ai-usage-cursor-events.json`, so only the last day is refetched (refresh about 2s instead of 9s).

