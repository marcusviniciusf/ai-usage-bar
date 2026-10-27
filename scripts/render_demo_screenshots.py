#!/usr/bin/env python3
"""Render public demo screenshots from fictional data in an isolated cache."""

from datetime import datetime, timedelta
import json
import os
from pathlib import Path
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[1]
APP = Path.home() / "Applications/AI Usage.app/Contents/MacOS/AIUsage"
IMAGES = ROOT / "docs/images"


def cost_tool(tool_id, name, today, week, month, costs, models, chats, rate=None, limit=None):
    now = datetime.now().astimezone()
    return {
        "id": tool_id, "name": name, "error": None,
        "today": today, "week": week, "month": month, "monthLabel": now.strftime("%b"),
        "daily": [{"date": (now.date() - timedelta(days=len(costs) - 1 - index)).isoformat(), "cost": cost}
                  for index, cost in enumerate(costs)],
        "models": [{"name": model, "cost": cost} for model, cost in models],
        "chats": [{"name": title, "cost": cost, "model": model} for title, cost, model in chats],
        "limit": limit, "periodEnd": None, "rate": rate,
        "alertsEnabled": True, "mode": "cost", "budget": None, "quotas": None,
    }


def demo_payload(now: datetime) -> dict:
    cursor = cost_tool(
        "cursor", "Cursor", 6.40, 21.80, 64.20,
        [3.1, 4.8, 2.2, 5.5, 7.9, 1.0, 0.6, 4.4, 6.8, 5.2, 3.9, 8.3, 4.1, 6.4],
        [("demo/model-a", 3.90), ("demo/model-b", 2.50)],
        [("Demo: refactor settings", 3.10, "demo/model-a"), ("Demo: fix flaky test", 1.80, "demo/model-b")],
        rate=2.1)
    claude = cost_tool(
        "claude", "Claude Code", 9.10, 38.40, 112.50,
        [6.2, 8.4, 5.1, 9.9, 12.3, 2.0, 1.1, 7.7, 10.5, 8.2, 6.6, 11.8, 7.4, 9.1],
        [("demo/model-c", 6.20), ("demo/model-d", 2.90)],
        [("Demo: migrate API client", 4.30, "demo/model-c"), ("Demo: write release notes", 2.10, "demo/model-d")],
        rate=3.4)
    open_code = cost_tool(
        "opencode", "OpenCode", 3.10, 11.90, 38.60,
        [0.25, 0.85, 1.20, 0.40, 1.55, 0.75, 0.90, 1.80, 2.10, 0.65, 1.20, 1.95, 1.10, 3.10],
        [("demo/model-a", 1.82), ("demo/model-b", 1.28)],
        [("Demo: implement settings", 1.82, "demo/model-a"), ("Demo: polish panel", 1.28, "demo/model-b")])
    codex = {
        "id": "codex", "name": "Codex", "error": None,
        "today": 0, "week": 0, "month": 0, "monthLabel": now.strftime("%b"),
        "daily": [], "models": [], "limit": None, "periodEnd": None,
        "rate": None, "chats": None, "alertsEnabled": True, "mode": "quota",
        "budget": None,
        "quotas": [
            {"id": "primary", "label": "5 hours", "usedPercent": 72,
             "resetsAt": (now + timedelta(minutes=90)).timestamp(), "windowMins": 300},
            {"id": "weekly", "label": "Weekly", "usedPercent": 54,
             "resetsAt": (now + timedelta(days=3)).timestamp(), "windowMins": 10080},
        ],
    }
    return {
        "updatedAt": now.isoformat(timespec="seconds"),
        "budget": 20, "globalBudget": {"amount": 20, "period": "daily"},
        "indicator": {"mode": "pinned", "toolIds": ["codex", "claude"]},
        "availableTools": [{"id": t["id"], "name": t["name"], "enabled": True}
                           for t in (codex, cursor, claude, open_code)],
        "tools": [codex, cursor, claude, open_code],
    }


def main() -> None:
    if not APP.is_file():
        raise SystemExit(f"Build the app first; executable not found: {APP}")

    IMAGES.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="ai-usage-demo-") as temporary_home:
        home = Path(temporary_home)
        cache = home / "Library/Caches/ai-usage.json"
        cache.parent.mkdir(parents=True)
        cache.write_text(json.dumps(demo_payload(datetime.now().astimezone())))
        environment = {**os.environ, "CFFIXED_USER_HOME": str(home)}
        captures = [
            ("--snapshot-bar", "ai-usage-menu-bar.png", []),
            ("--snapshot", "ai-usage-panel.png", ["Today"]),
            ("--snapshot", "ai-usage-codex-quota.png", ["Today", "codex"]),
            ("--snapshot", "ai-usage-claude-costs.png", ["Today", "claude"]),
            ("--snapshot", "ai-usage-opencode-costs.png", ["Today", "opencode"]),
        ]
        for flag, filename, view_args in captures:
            subprocess.run(
                [str(APP), flag, str(IMAGES / filename), *view_args, "--lang", "en"],
                check=True,
                env=environment,
            )
            print(f"Rendered {IMAGES / filename}")


if __name__ == "__main__":
    main()
