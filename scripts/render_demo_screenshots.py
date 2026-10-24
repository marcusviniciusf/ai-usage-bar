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


def demo_payload(now: datetime) -> dict:
    daily_costs = [0.25, 0.85, 1.20, 0.40, 1.55, 0.75, 0.90,
                   1.80, 2.10, 0.65, 1.20, 1.95, 1.10, 3.10]
    daily = [
        {"date": (now.date() - timedelta(days=13 - index)).isoformat(), "cost": cost}
        for index, cost in enumerate(daily_costs)
    ]
    open_code = {
        "id": "opencode", "name": "OpenCode", "error": None,
        "today": 3.10, "week": 11.90, "month": 38.60, "monthLabel": now.strftime("%b"),
        "daily": daily,
        "models": [
            {"name": "demo/model-a", "cost": 1.82},
            {"name": "demo/model-b", "cost": 1.28},
        ],
        "chats": [
            {"name": "Demo: implement settings", "cost": 1.82, "model": "demo/model-a"},
            {"name": "Demo: polish panel", "cost": 1.28, "model": "demo/model-b"},
        ],
        "limit": None, "periodEnd": None, "rate": 0.84,
        "alertsEnabled": True, "mode": "cost", "budget": None, "quotas": None,
    }
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
        "budget": None, "globalBudget": None,
        "indicator": {"mode": "summary", "toolId": None},
        "availableTools": [
            {"id": "codex", "name": "Codex", "enabled": True},
            {"id": "opencode", "name": "OpenCode", "enabled": True},
        ],
        "tools": [codex, open_code],
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
