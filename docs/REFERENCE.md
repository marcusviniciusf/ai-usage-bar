# Reference

Details behind the [README](../README.md): detection, modes, budgets, CLI flags, validation, languages.

## Automatic detection

Only detected tools appear. Cursor is detected by its app or local database; Claude Code by its CLI or projects directory; OpenCode by its CLI or data directory; Codex by its CLI, including the CLI bundled with ChatGPT or Codex.
A detected tool with a collection error stays visible. Missing tools are hidden.
Cursor access reads your existing Cursor login: the app asks macOS for the "Cursor Safe Storage" Keychain item (choose **Always Allow**, otherwise macOS prompts on every refresh) and calls the same undocumented dashboard endpoint (`api2.cursor.sh`) the Cursor usage page uses, so it can break if Cursor changes it. The decryption key is briefly passed to `/usr/bin/openssl` on the command line. Nothing is sent anywhere else. Claude Code and OpenCode figures are API list-price estimates from local logs, not what a subscription bills.

## Two monitoring modes

- **Subscription quotas:** Codex shows current account quota windows and reset times from the official local app-server `account/rateLimits/read` method. This is account-wide usage, including other devices, and is separate from ChatGPT browser conversations. No turns, logins, credit resets or purchases are initiated.
- **Cost:** OpenCode, Claude Code and Cursor show local usage costs. Calendar-month totals and per-tool monthly budgets use the calendar month; Cursor's plan limit and spend are shown separately for its billing cycle. Each cost tool can optionally have a daily or monthly USD budget. Without a budget, only consumption is shown. Estimates from logs are not invoices. OpenCode totals, history, models and top sessions exclude model IDs ending in `-free` or `:free` (case-insensitive), plus the exact ID `free`. Mixed sessions include only non-free model costs. Unknown free tiers without those markers cannot be inferred from the name. If per-model costs are unavailable, the tool reports an error rather than using an unfiltered total.

The menu bar defaults to a compact combined summary: the most consumed subscription quota remaining (percent) plus today's combined cost (USD), identified by icons. Fixed and urgent modes also use compact values; percentages always mean remaining capacity. Full tool names and details remain in the tooltip and app window. In the app settings (gear button), choose combined summary, a fixed tool, or the quota/budget closest to its limit. The urgent mode compares subscription windows, per-tool budgets and the optional global budget; without a limit it falls back to the summary. Data refreshes every five minutes or with the refresh button. Sources collect independently; one that takes over 45 seconds reports an error while healthy sources still update.
The chart only combines tools with cost data. Subscription percentages are never converted into dollars or added to that chart.

## Per-tool preferences

Use the settings menu beside each tool. Cost tools offer an optional budget editor; all tools offer an alert toggle.
Preferences live in `~/.config/ai-usage/config.json` (or `$XDG_CONFIG_HOME/ai-usage/config.json`).
Existing `dailyBudget` values and `AI_USAGE_DAILY_BUDGET` retain their original global daily meaning. They are never split into tool budgets. The optional global budget is shown separately and excludes subscription quotas. It coexists with individual tool budgets and has its own 80%/100% alerts; incomplete cost collection suppresses global budget alerts.
New installations have no global budget unless configured. On a given Mac, `globalBudget: null` explicitly disables it while preserving the legacy key. The environment override has precedence.
The collector retains the old numeric `budget` JSON field so existing binaries keep decoding after `git pull`; the updated app distinguishes that compatibility field from the optional `globalBudget`. Old binaries continue their original budget behavior until rebuilt. The new app can also read old collector payloads.
Update another Mac with `git pull` and `./install.sh`. Its own configuration is preserved; preferences are never copied between Macs.

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
Enable automatic startup with **Launch at login** (gear menu).

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

- **Cost:** with a global budget set, the Today/Week/Month picker scales it by the days elapsed (daily budget × days, weeks start Monday) and shows the % used. On Today it also shows the combined $/h (Cursor last hour, Claude active 5h block) and how long until the limit at that pace.
- **Quota:** each Codex window projects linearly from usage so far, either "runs out in ~Xh, before it renews" or the expected % at renewal. Needs a used window of at least 10 minutes.
- The 80% notifications (global budget and quotas) include the same ETA.

## Panel layout

Compact by default (about 420pt tall): hero, one row per tool, collapsed 14-day chart. Tap a tool row to expand models, sessions, budget and plan details; per-tool options live in its **Options** menu. App settings (bar indicator, global budget, launch at login, quit) are in the gear menu, a native menu, so they open instantly.
Preference changes apply immediately in the UI and are persisted in the background. Cursor events are cached in `~/Library/Caches/ai-usage-cursor-events.json`, so only the last day is refetched (refresh about 2s instead of 9s).

## Tool filter

Pick which detected tools are monitored in the gear menu (**Monitored tools**). A hidden tool is not collected, so it drops out of the totals, the budget, alerts and the bar indicator, and refreshes get faster. Per Mac, stored as `tools.<id>.enabled` in the config.

```bash
ai-usage --set-tool-enabled cursor off
ai-usage --set-tool-enabled cursor on
```

## Pinning up to two tools in the menu bar

Gear menu → **Bar indicator** → **Pin up to 2 tools**. Each pinned tool shows its icon plus a compact value (remaining % for quota tools, today's cost for the others). A third pin replaces the oldest; unpinning everything returns to the summary. Tools hidden with the tool filter are skipped.

```bash
ai-usage --set-indicator pinned claude codex   # one or two tools
```

## Language

English, Portuguese (Brasil) and Spanish. The default follows the device's first supported language (anything else falls back to English). Pick another one in the gear menu → **Language**; the choice is per Mac and applies immediately, including notifications and dates.
To add a language, add a case to `AppLanguage` and a table in `L10n.tables` (English strings are the keys; missing keys fall back to English). Quota windows ("5 hours", "Weekly") are named by the app from the window length, not by the collector.
Render a screenshot in another language without changing the saved choice: `AIUsage --snapshot out.png Today --lang es`.
