# Add a tool with a JSON spec

AI Usage can read any coding harness that writes token or cost data to a local JSONL file or SQLite database. Drop a spec in `~/.config/ai-usage/tools/<name>.json`; the tool appears on the next refresh, with spend, models, sessions, budgets and menu bar pinning like the built-in tools. Nothing is executed and nothing leaves your Mac.

A tool is shown only when its source exists. A broken spec appears as a "Spec <file>" tool with the reason.

## JSONL source

```json
{
  "id": "my-harness",
  "name": "My Harness",
  "source": { "type": "jsonl", "glob": "~/.my-harness/sessions/**/*.jsonl" },
  "where": [{ "path": "type", "equals": "assistant" }],
  "fields": {
    "timestamp": "timestamp",
    "model": "message.model",
    "session": "sessionId",
    "id": "message.id",
    "input": "message.usage.input_tokens",
    "output": "message.usage.output_tokens",
    "cacheRead": "message.usage.cache_read_tokens",
    "cacheWrite": "message.usage.cache_write_tokens"
  },
  "pricing": {
    "default": { "input": 3, "output": 15, "cacheRead": 0.3, "cacheWrite": 3.75 },
    "models": { "small-": { "input": 1, "output": 5 } }
  }
}
```

Each field value is a dotted path into the JSON line (`parts.0.id` indexes lists).

## SQLite source

```json
{
  "id": "my-db-harness",
  "name": "My DB Harness",
  "timeUnit": "ms",
  "source": {
    "type": "sqlite",
    "path": "~/.local/share/my-harness/data.db",
    "query": "SELECT created AS timestamp, model, session_id AS session, cost FROM messages WHERE role = 'assistant'"
  }
}
```

The database is opened read-only. The query must return columns named after the fields below.

## Reference

| Key | Meaning |
|---|---|
| `id` | 2-32 chars: lowercase letters, digits, dashes. Cannot reuse `codex`, `cursor`, `claude`, `opencode`, `deepseek`. |
| `name` | Label shown in the app. |
| `detect` | Optional list of paths; the tool is shown if any exists. Defaults to the source glob or path. |
| `timeUnit` | `iso` (default), `ms` or `s` for the timestamp. |
| `where` | Optional list of `{path, equals}` filters, all must match (JSONL only). |
| `fields` | `timestamp` (required), `model`, `session`, `title`, `id` (deduplicates repeated lines), `cost`, `input`, `output`, `cacheRead`, `cacheWrite`. |
| `costScale` | Multiplier for a reported `cost` (for example `0.01` when it is in cents). |
| `pricing` | USD per million tokens, used only when a row has no `cost`. `models` matches by name prefix, longest first; `default` covers the rest. |

Tool-level budgets, alerts, the on/off filter and menu bar pinning work for spec tools by their `id`. Spec tools show cost only: there is no quota or burn-rate support.
