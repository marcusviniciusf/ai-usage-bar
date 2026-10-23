import importlib.machinery
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch


COLLECTOR = Path(__file__).resolve().parents[1] / "bin/ai-usage"
loader = importlib.machinery.SourceFileLoader("collector", str(COLLECTOR))
spec = importlib.util.spec_from_loader(loader.name, loader)
collector = importlib.util.module_from_spec(spec)
loader.exec_module(collector)


class CollectorTests(unittest.TestCase):
    def test_legacy_budget_preserved_and_explicit_disable_wins(self):
        with patch.dict(os.environ, {}, clear=True), patch.object(collector, "configuration", return_value={"dailyBudget": 80}):
            data = collector.output_payload([])
            self.assertEqual(data["budget"], 80)
            self.assertEqual(data["globalBudget"], {"amount": 80, "period": "daily"})
            with patch.object(collector, "configuration", return_value={"dailyBudget": 80, "globalBudget": None}):
                self.assertIsNone(collector.global_budget())
                self.assertGreater(collector.output_payload([])["budget"], 0)
            with patch.dict(os.environ, {"AI_USAGE_DAILY_BUDGET": "90"}):
                self.assertEqual(collector.global_budget()["amount"], 90)

    def test_legacy_cli_and_indicator_preferences_preserve_existing_config(self):
        with tempfile.TemporaryDirectory() as config:
            env = {**os.environ, "XDG_CONFIG_HOME": config}
            path = Path(config, "ai-usage/config.json")
            path.parent.mkdir()
            path.write_text(json.dumps({"dailyBudget": 30, "tools": {"opencode": {"budget": {"amount": 20, "period": "daily"}}}}))
            def run(*args):
                return subprocess.run([sys.executable, str(COLLECTOR), *args], env=env, capture_output=True, text=True)
            self.assertEqual(run("--set-budget", "80").returncode, 0)
            self.assertEqual(run("--set-indicator", "fixed", "opencode").returncode, 0)
            data = json.loads(path.read_text())
            self.assertEqual(data["dailyBudget"], 80)
            self.assertEqual(data["globalBudget"]["amount"], 80)
            self.assertEqual(data["tools"]["opencode"]["budget"]["amount"], 20)
            self.assertEqual(data["indicator"], {"mode": "fixed", "toolId": "opencode"})
            self.assertEqual(run("--set-budget", "0").returncode, 0)
            self.assertIsNone(json.loads(path.read_text())["globalBudget"])
            self.assertNotEqual(run("--set-indicator", "fixed", "missing").returncode, 0)

    def test_opencode_excludes_free_costs_from_all_windows_and_history(self):
        days = [
            {"date": collector.today.isoformat(), "totalCost": 64.47, "modelBreakdowns": [
                {"modelName": "nemotron-3.5-super-vl-free", "cost": 55.39},
                {"modelName": "provider/deepseek:FREE", "cost": 1.70},
                {"modelName": "deepseek-v4.1-flash", "cost": 7.38}]},
        ]
        def report(agent, kind, *args):
            return {"daily": days} if kind == "daily" else {"sessions": []}
        with patch.object(collector, "ccusage_json", side_effect=report):
            result = collector.ccusage("opencode")
        for period in ("today", "week", "month"):
            self.assertAlmostEqual(result[period], 7.38)
        self.assertEqual(result["models"], [{"name": "deepseek-v4.1-flash", "cost": 7.38}])
        self.assertEqual(result["daily"][-1]["cost"], 7.38)
        self.assertEqual(result["rate"], 0)

    def test_mixed_sessions_are_ranked_by_non_free_costs(self):
        def session(key, models):
            return {"sessionId": key, "totalCost": sum(m["cost"] for m in models), "modelBreakdowns": models}
        sessions = [
            session("free-only", [{"modelName": "provider/large-free", "cost": 100}]),
            session("mixed", [{"modelName": "large-free", "cost": 80}, {"modelName": "paid-small", "cost": 2}]),
            session("paid", [{"modelName": "paid-model", "cost": 3}]),
        ]
        with patch.object(collector, "ccusage_json", return_value={"sessions": sessions}), \
                patch.object(collector, "opencode_titles", return_value={"mixed": "Mixed", "paid": "Paid"}):
            result = collector.top_chats("opencode")
        self.assertEqual([(s["name"], s["cost"], s["model"]) for s in result],
                         [("Paid", 3, "paid-model"), ("Mixed", 2, "paid-small")])

    def test_free_only_usage_is_zero_and_missing_breakdown_is_an_error(self):
        self.assertEqual(collector.paid_breakdowns({"totalCost": 99, "modelBreakdowns": [
            {"modelName": "provider/model-free", "cost": 99}]}), [])
        self.assertEqual(collector.paid_breakdowns({"totalCost": 0}), [])
        with self.assertRaisesRegex(RuntimeError, "cannot exclude free"):
            collector.paid_breakdowns({"totalCost": 99})
        self.assertFalse(collector.is_free_model("deepseek-v4.1-flash"))
        self.assertTrue(collector.is_free_model("provider/free"))

    def test_absent_tools_hidden_and_data_tools_detected(self):
        with tempfile.TemporaryDirectory() as home, patch.object(collector, "HOME", home), \
                patch.object(collector, "codex_binary", return_value=None), \
                patch.object(collector.shutil, "which", return_value=None), \
                patch.dict(os.environ, {"XDG_DATA_HOME": home + "/data", "CLAUDE_CONFIG_DIR": home + "/claude"}):
            self.assertEqual(collector.detected_sources(), [])
            Path(home, "data/opencode").mkdir(parents=True)
            self.assertEqual([s[0] for s in collector.detected_sources()], ["opencode"])
            Path(home, "claude/projects").mkdir(parents=True)
            self.assertEqual([s[0] for s in collector.detected_sources()], ["claude", "opencode"])

    def test_tool_budgets_are_independent_and_optional(self):
        with tempfile.TemporaryDirectory() as config:
            env = {**os.environ, "XDG_CONFIG_HOME": config}
            def run(*args):
                return subprocess.run([sys.executable, str(COLLECTOR), *args], env=env, capture_output=True, text=True)
            self.assertEqual(run("--set-tool-budget", "opencode", "monthly", "25").returncode, 0)
            path = Path(config, "ai-usage/config.json")
            with patch.object(collector, "CONFIG", str(path)):
                self.assertEqual(collector.tool_budget("opencode"), {"amount": 25, "period": "monthly"})
                self.assertIsNone(collector.tool_budget("claude"))
                for value in ("nan", "inf", "-1"):
                    self.assertNotEqual(run("--set-tool-budget", "opencode", "daily", value).returncode, 0)
                self.assertEqual(run("--set-alerts", "codex", "off").returncode, 0)
                self.assertFalse(collector.configuration()["tools"]["codex"]["alertsEnabled"])
                self.assertEqual(run("--set-tool-budget", "opencode", "monthly", "0").returncode, 0)
                self.assertIsNone(collector.tool_budget("opencode"))

    def test_codex_protocol_preserves_buckets_and_reset_time(self):
        with tempfile.TemporaryDirectory() as folder:
            server = Path(folder, "codex")
            server.write_text('''#!/usr/bin/python3
import json, sys
for line in sys.stdin:
    message = json.loads(line)
    if message.get("method") == "initialize":
        print(json.dumps({"id": message["id"], "result": {}}), flush=True)
    elif message.get("method") == "account/rateLimits/read":
        print(json.dumps({"method": "notification", "params": {}}), flush=True)
        bucket = {"primary": {"usedPercent": 45, "windowDurationMins": 300, "resetsAt": 2000000000}}
        print(json.dumps({"id": message["id"], "result": {"rateLimitsByLimitId": {"codex": bucket, "other": bucket}}}), flush=True)
''')
            server.chmod(0o755)
            with patch.object(collector, "codex_binary", return_value=str(server)):
                data = collector.codex()
                self.assertEqual(data["mode"], "quota")
                self.assertEqual(len(data["quotas"]), 2)
                self.assertEqual(data["quotas"][0]["resetsAt"], 2000000000)
                self.assertEqual(data["quotas"][0]["windowMins"], 300)
                self.assertNotEqual(data["quotas"][0]["id"], data["quotas"][1]["id"])

    def test_tool_filter_hides_tool_but_keeps_it_listed(self):
        with tempfile.TemporaryDirectory() as config:
            env = {**os.environ, "XDG_CONFIG_HOME": config}
            path = Path(config, "ai-usage/config.json")
            path.parent.mkdir()
            path.write_text(json.dumps({"dailyBudget": 30, "tools": {"opencode": {"alertsEnabled": False}}}))
            result = subprocess.run([sys.executable, str(COLLECTOR), "--set-tool-enabled", "opencode", "off"],
                                    env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0)
            saved = json.loads(path.read_text())
            self.assertFalse(saved["tools"]["opencode"]["enabled"])
            self.assertFalse(saved["tools"]["opencode"]["alertsEnabled"])
            self.assertEqual(saved["dailyBudget"], 30)
            bad = subprocess.run([sys.executable, str(COLLECTOR), "--set-tool-enabled", "nope", "off"],
                                 env=env, capture_output=True, text=True)
            self.assertNotEqual(bad.returncode, 0)
        sources = [("opencode", "OpenCode", None), ("claude", "Claude Code", None)]
        with patch.object(collector, "configuration", return_value={"tools": {"opencode": {"enabled": False}}}):
            self.assertFalse(collector.tool_enabled("opencode"))
            self.assertTrue(collector.tool_enabled("claude"))
            listed = collector.output_payload([], sources)["availableTools"]
            self.assertEqual([(t["id"], t["enabled"]) for t in listed], [("opencode", False), ("claude", True)])

    def test_source_failure_stays_visible(self):
        def fail():
            raise RuntimeError("Sign in required")
        result = collector.collect(("codex", "Codex", fail))
        self.assertEqual(result["error"], "Sign in required")
        self.assertEqual(result["mode"], "quota")


if __name__ == "__main__":
    unittest.main()
