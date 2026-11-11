import importlib.machinery
import importlib.util
import json
import os
from pathlib import Path
import sqlite3
import subprocess
import sys
import tempfile
import time
import unittest
from concurrent.futures import ThreadPoolExecutor
from unittest.mock import patch


COLLECTOR = Path(__file__).resolve().parents[1] / "bin/ai-usage"
loader = importlib.machinery.SourceFileLoader("collector", str(COLLECTOR))
spec = importlib.util.spec_from_loader(loader.name, loader)
collector = importlib.util.module_from_spec(spec)
loader.exec_module(collector)

try:
    from compression import zstd as _zstd  # noqa: F401
    HAS_STDLIB_ZSTD = True
except ImportError:
    HAS_STDLIB_ZSTD = False


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

    def test_period_totals_use_calendar_month_and_keep_today_separate(self):
        totals = collector.period_totals({collector.month_start - collector.timedelta(days=1): 90,
                                          collector.today: 4})
        self.assertEqual(totals, {"today": 4, "week": 4, "month": 4})

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
            self.assertEqual(run("--set-indicator", "urgent").returncode, 0)
            self.assertEqual(json.loads(path.read_text())["indicator"]["mode"], "urgent")
            self.assertEqual(run("--set-indicator", "summary").returncode, 0)
            self.assertEqual(json.loads(path.read_text())["indicator"]["mode"], "summary")
            self.assertEqual(run("--set-budget", "0").returncode, 0)
            self.assertIsNone(json.loads(path.read_text())["globalBudget"])
            self.assertNotEqual(run("--set-indicator", "fixed", "missing").returncode, 0)

    def test_concurrent_preference_writes_preserve_both_updates(self):
        with tempfile.TemporaryDirectory() as config:
            env = {**os.environ, "XDG_CONFIG_HOME": config}
            def run(args):
                return subprocess.run([sys.executable, str(COLLECTOR), *args], env=env, capture_output=True, text=True)
            with ThreadPoolExecutor(max_workers=2) as pool:
                results = list(pool.map(run, [
                    ("--set-tool-budget", "opencode", "daily", "12"),
                    ("--set-alerts", "codex", "off"),
                ]))
            self.assertEqual([r.returncode for r in results], [0, 0])
            saved = json.loads(Path(config, "ai-usage/config.json").read_text())
            self.assertEqual(saved["tools"]["opencode"]["budget"]["amount"], 12)
            self.assertFalse(saved["tools"]["codex"]["alertsEnabled"])

    def test_invalid_configuration_is_not_overwritten(self):
        with tempfile.TemporaryDirectory() as config:
            env = {**os.environ, "XDG_CONFIG_HOME": config}
            path = Path(config, "ai-usage/config.json")
            path.parent.mkdir()
            original = b"{not valid json"
            path.write_bytes(original)
            result = subprocess.run([sys.executable, str(COLLECTOR), "--set-alerts", "codex", "off"],
                                    env=env, capture_output=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn(b"Fix or restore this file", result.stderr)
            self.assertNotIn(b"Traceback", result.stderr)
            self.assertEqual(path.read_bytes(), original)

    def _opencode_db(self, data_home, legacy=(), current=()):
        path = Path(data_home, "opencode/opencode.db")
        path.parent.mkdir(parents=True)
        db = sqlite3.connect(path)
        db.execute("CREATE TABLE message (id TEXT, session_id TEXT, time_created INTEGER, time_updated INTEGER, data TEXT)")
        db.execute("CREATE TABLE session_message (id TEXT, session_id TEXT, type TEXT, seq INTEGER, time_created INTEGER, time_updated INTEGER, data TEXT)")
        for i, (session, model, cost, created) in enumerate(legacy):
            db.execute("INSERT INTO message VALUES (?,?,?,?,?)", (f"m{i}", session, created, created,
                       json.dumps({"role": "assistant", "modelID": model, "cost": cost, "time": {"created": created}})))
        for i, (session, model, cost, created) in enumerate(current):
            db.execute("INSERT INTO session_message VALUES (?,?,?,?,?,?,?)", (f"s{i}", session, "assistant", i, created, created,
                       json.dumps({"model": {"id": model}, "cost": cost, "time": {"created": created}})))
        db.commit()
        db.close()

    def test_opencode_reads_both_schemas_and_excludes_free_models(self):
        now = int(time.time() * 1000)
        with tempfile.TemporaryDirectory() as data_home:
            self._opencode_db(data_home,
                              legacy=[("a", "nemotron-super-free", 55.39, now), ("a", "deepseek-v4.1-flash", 3.0, now)],
                              current=[("b", "provider/deepseek:FREE", 1.7, now), ("b", "deepseek-v4.1-flash", 4.38, now)])
            with patch.object(collector, "DATA_HOME", data_home):
                result = collector.opencode()
        for period in ("today", "week", "month"):
            self.assertAlmostEqual(result[period], 7.38)
        self.assertEqual(result["models"], [{"name": "deepseek-v4.1-flash", "cost": 7.38}])
        self.assertEqual(result["daily"][-1]["cost"], 7.38)
        self.assertEqual([(c["cost"], c["model"]) for c in result["chats"]], [(4.38, "deepseek-v4.1-flash"), (3.0, "deepseek-v4.1-flash")])
        self.assertEqual(result["rate"], 0)

    def test_missing_opencode_database_reports_an_error(self):
        with tempfile.TemporaryDirectory() as data_home, patch.object(collector, "DATA_HOME", data_home):
            with self.assertRaisesRegex(RuntimeError, "OpenCode database not found"):
                collector.opencode()

    def _claude_home(self, root, rows):
        project = Path(root, ".claude/projects/-Users-me-app")
        project.mkdir(parents=True)
        with open(project / "sess1.jsonl", "w") as f:
            for when, model, usage, mid in rows:
                f.write(json.dumps({"type": "assistant", "timestamp": when.astimezone(collector.timezone.utc).isoformat().replace("+00:00", "Z"),
                                    "requestId": f"req_{mid}", "sessionId": "sess1",
                                    "message": {"id": mid, "model": model, "usage": usage}}) + "\n")
            f.write(json.dumps({"type": "custom-title", "customTitle": "My chat"}) + "\n")

    def test_claude_prices_tokens_dedupes_messages_and_ranks_chats(self):
        now = collector.datetime.now().astimezone()
        usage = {"input_tokens": 1_000_000, "output_tokens": 1_000_000, "cache_read_input_tokens": 1_000_000,
                 "cache_creation_input_tokens": 1_000_000, "cache_creation": {"ephemeral_1h_input_tokens": 400_000}}
        with tempfile.TemporaryDirectory() as root:
            self._claude_home(root, [(now, "claude-opus-5-5", usage, "m1"), (now, "claude-opus-5-5", usage, "m1"),
                                     (now, "<synthetic>", usage, "m2"), (now, "claude-unknown-9", usage, "m3")])
            with patch.object(collector, "HOME", root), patch.dict(os.environ, {"CLAUDE_CONFIG_DIR": ""}), \
                    patch.object(collector, "claude_quotas", return_value=[]):
                result = collector.claude()
        # 4 + 20 + 0.2 + 600k x 5 + 400k x 8 per million, counted once.
        expected = 4 + 20 + 0.2 + 0.6 * 5 + 0.4 * 8
        self.assertAlmostEqual(result["today"], expected, places=4)
        self.assertEqual([m["name"] for m in result["models"]], ["claude-opus-5-5"])
        self.assertEqual(result["chats"][0]["name"], "My chat")
        self.assertEqual(result["chats"][0]["model"], "claude-opus-5-5")

    def test_claude_quotas_parse_windows_and_clamp(self):
        quotas = collector.parse_claude_quotas({
            "five_hour": {"utilization": 42.5, "resets_at": "2026-11-06T18:00:00.000000+00:00"},
            "seven_day": {"utilization": 130, "resets_at": None},
            "seven_day_opus": {"utilization": 5}})
        self.assertEqual([(q["id"], q["usedPercent"], q["windowMins"]) for q in quotas],
                         [("claude-five_hour", 42.5, 300), ("claude-seven_day", 100.0, 10080)])
        self.assertEqual(quotas[0]["resetsAt"], 1793988000.0)
        self.assertIsNone(quotas[1]["resetsAt"])
        self.assertEqual(collector.parse_claude_quotas(None), [])
        self.assertEqual(collector.parse_claude_quotas({"five_hour": {"utilization": "n/a"}}), [])

    def test_claude_quotas_are_hidden_without_a_subscription_token(self):
        def keychain(payload, code=0):
            return patch.object(collector.subprocess, "run", return_value=subprocess.CompletedProcess([], code, json.dumps(payload), ""))
        with keychain({"mcpOAuth": {"other": {"accessToken": "x"}}}):
            self.assertIsNone(collector.claude_oauth_token())
        with keychain({"claudeAiOauth": {"accessToken": "t", "expiresAt": 1}}):
            self.assertIsNone(collector.claude_oauth_token())
        with keychain({"claudeAiOauth": {"accessToken": "t"}}, code=44):
            self.assertIsNone(collector.claude_oauth_token())
        with keychain({"claudeAiOauth": {"accessToken": "t", "expiresAt": (time.time() + 3600) * 1000}}):
            self.assertEqual(collector.claude_oauth_token(), "t")
        with patch.object(collector, "claude_oauth_token", return_value=None):
            self.assertEqual(collector.claude_quotas(), [])

    def _spec_env(self, root, spec, files=None):
        specs = Path(root, "tools")
        specs.mkdir()
        (specs / "mytool.json").write_text(json.dumps(spec))
        return patch.object(collector, "PLUGIN_DIR", str(specs))

    def test_tool_spec_reads_jsonl_with_reported_cost_and_dedupes(self):
        now = collector.datetime.now().astimezone()
        with tempfile.TemporaryDirectory() as root:
            log = Path(root, "logs/a.jsonl")
            log.parent.mkdir()
            rows = [{"kind": "reply", "at": now.isoformat(), "mid": "1", "sid": "s1", "m": "big", "usage": {"usd": 0.5}},
                    {"kind": "reply", "at": now.isoformat(), "mid": "1", "sid": "s1", "m": "big", "usage": {"usd": 0.5}},
                    {"kind": "reply", "at": now.isoformat(), "mid": "2", "sid": "s2", "m": "small", "usage": {"usd": 0.25}},
                    {"kind": "note", "at": now.isoformat(), "mid": "3", "sid": "s2", "m": "small", "usage": {"usd": 9}}]
            log.write_text("\n".join(json.dumps(r) for r in rows) + "\nnot json\n")
            spec = {"id": "mytool", "name": "My Tool", "source": {"type": "jsonl", "glob": str(Path(root, "logs/*.jsonl"))},
                    "where": [{"path": "kind", "equals": "reply"}],
                    "fields": {"timestamp": "at", "model": "m", "session": "sid", "cost": "usage.usd", "id": "mid"}}
            with self._spec_env(root, spec):
                sources = collector.plugin_sources()
                self.assertEqual([(s[0], s[1]) for s in sources], [("mytool", "My Tool")])
                result = sources[0][2]()
        self.assertAlmostEqual(result["today"], 0.75)
        self.assertEqual([(c["name"], c["cost"], c["model"]) for c in result["chats"]], [("s1", 0.5, "big"), ("s2", 0.25, "small")])
        self.assertEqual({m["name"] for m in result["models"]}, {"big", "small"})

    def test_tool_spec_prices_tokens_when_no_cost_is_reported(self):
        now_ms = int(time.time() * 1000)
        with tempfile.TemporaryDirectory() as root:
            db_path = Path(root, "tool.db")
            db = sqlite3.connect(db_path)
            db.execute("CREATE TABLE msg (ts INTEGER, model TEXT, sid TEXT, tin INTEGER, tout INTEGER)")
            db.execute("INSERT INTO msg VALUES (?,?,?,?,?)", (now_ms, "fast-1", "s1", 1_000_000, 500_000))
            db.commit()
            db.close()
            spec = {"id": "mytool", "name": "My Tool", "timeUnit": "ms",
                    "source": {"type": "sqlite", "path": str(db_path),
                               "query": "SELECT ts AS timestamp, model, sid AS session, tin AS input, tout AS output FROM msg"},
                    "pricing": {"models": {"fast": {"input": 1, "output": 4}}, "default": {"input": 10, "output": 10}}}
            with self._spec_env(root, spec):
                result = collector.plugin_sources()[0][2]()
        self.assertAlmostEqual(result["today"], 1 + 2)

    def test_invalid_tool_specs_surface_as_errors_and_cannot_shadow_builtins(self):
        with tempfile.TemporaryDirectory() as root:
            specs = Path(root, "tools")
            specs.mkdir()
            (specs / "claude.json").write_text(json.dumps({"id": "claude", "name": "X", "source": {"type": "jsonl", "glob": "x"},
                                                           "fields": {"timestamp": "t"}}))
            (specs / "broken.json").write_text("{nope")
            with patch.object(collector, "PLUGIN_DIR", str(specs)):
                loaded, problems = collector.load_tool_specs()
                self.assertEqual(loaded, [])
                self.assertIn("built in", problems["claude.json"])
                self.assertIn("not readable JSON", problems["broken.json"])
                results = {s[0]: collector.collect(s) for s in collector.plugin_sources()}
        self.assertEqual(set(results), {"spec-claude", "spec-broken"})
        self.assertIn("Invalid tool spec", results["spec-claude"]["error"])

    def test_dig_walks_dicts_and_lists(self):
        self.assertEqual(collector.dig({"a": {"b": [{"c": 7}]}}, "a.b.0.c"), 7)
        self.assertIsNone(collector.dig({"a": 1}, "a.b"))
        self.assertIsNone(collector.dig({"a": [1]}, "a.5"))

    def test_claude_price_matches_model_families(self):
        self.assertEqual(collector.claude_price("claude-opus-5-5"), (4, 20, 5, 0.2))
        self.assertEqual(collector.claude_price("claude-sonnet-4-5-20250929"), (3, 15, 3.75, 0.3))
        self.assertIsNone(collector.claude_price("gpt-5"))

    def test_opencode_titles_support_each_schema_and_xdg_path(self):
        with tempfile.TemporaryDirectory() as data_home:
            db_path = Path(data_home, "opencode/opencode.db")
            db_path.parent.mkdir(parents=True)
            db = sqlite3.connect(db_path)
            db.execute("CREATE TABLE session_v2 (id TEXT, title TEXT)")
            db.execute("INSERT INTO session_v2 VALUES ('new', 'New schema')")
            db.commit()
            db.close()
            with patch.object(collector, "DATA_HOME", data_home):
                self.assertEqual(collector.opencode_titles(["new"]), {"new": "New schema"})
            db = sqlite3.connect(db_path)
            db.execute("CREATE TABLE session (id TEXT, title TEXT)")
            db.execute("INSERT INTO session VALUES ('old', 'Old schema')")
            db.commit()
            db.close()
            with patch.object(collector, "DATA_HOME", data_home):
                self.assertEqual(collector.opencode_titles(["new", "old"]), {"new": "New schema", "old": "Old schema"})
            db = sqlite3.connect(db_path)
            db.execute("DROP TABLE session_v2")
            db.commit()
            db.close()
            with patch.object(collector, "DATA_HOME", data_home):
                self.assertEqual(collector.opencode_titles(["old"]), {"old": "Old schema"})
            db = sqlite3.connect(db_path)
            db.execute("DROP TABLE session")
            db.commit()
            db.close()
            with patch.object(collector, "DATA_HOME", data_home):
                self.assertEqual(collector.opencode_titles(["old"]), {})

    def test_free_model_names(self):
        self.assertFalse(collector.is_free_model("deepseek-v4.1-flash"))
        self.assertTrue(collector.is_free_model("provider/free"))
        self.assertTrue(collector.is_free_model("nemotron-super-free"))

    def test_absent_tools_hidden_and_data_tools_detected(self):
        real_isdir = os.path.isdir
        # Detection also checks the absolute /Applications path, so hide it for machines that have Cursor installed.
        without_cursor_app = lambda path: False if path == "/Applications/Cursor.app" else real_isdir(path)
        with tempfile.TemporaryDirectory() as home, patch.object(collector, "HOME", home), \
                patch.object(collector, "codex_binary", return_value=None), \
                patch.object(collector.shutil, "which", return_value=None), \
                patch.object(os.path, "isdir", side_effect=without_cursor_app), \
                patch.dict(os.environ, {"XDG_DATA_HOME": home + "/data", "CLAUDE_CONFIG_DIR": home + "/claude"}):
            self.assertEqual(collector.detected_sources(), [])
            Path(home, "data/opencode").mkdir(parents=True)
            self.assertEqual([s[0] for s in collector.detected_sources()], ["opencode"])
            Path(home, "claude/projects").mkdir(parents=True)
            self.assertEqual([s[0] for s in collector.detected_sources()], ["claude", "opencode"])
            Path(home, ".dsh/sessions").mkdir(parents=True)
            self.assertEqual([s[0] for s in collector.detected_sources()], ["claude", "opencode", "deepseek"])

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

    def test_pinned_indicator_accepts_one_or_two_known_tools(self):
        with tempfile.TemporaryDirectory() as config:
            env = {**os.environ, "XDG_CONFIG_HOME": config}
            def run(*args):
                return subprocess.run([sys.executable, str(COLLECTOR), *args], env=env, capture_output=True, text=True)
            self.assertEqual(run("--set-indicator", "pinned", "claude", "codex").returncode, 0)
            saved = json.loads(Path(config, "ai-usage/config.json").read_text())
            self.assertEqual(saved["indicator"], {"mode": "pinned", "toolId": None, "toolIds": ["claude", "codex"]})
            self.assertEqual(run("--set-indicator", "pinned", "cursor").returncode, 0)
            self.assertNotEqual(run("--set-indicator", "pinned", "claude", "codex", "cursor").returncode, 0)
            self.assertNotEqual(run("--set-indicator", "pinned", "claude", "claude").returncode, 0)
            self.assertNotEqual(run("--set-indicator", "pinned", "nope").returncode, 0)
            self.assertNotEqual(run("--set-indicator", "pinned").returncode, 0)

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

    def test_isolated_source_timeout_does_not_block_healthy_source(self):
        slow_source = ("slow", "Slow source", None)
        healthy_source = ("healthy", "Healthy source", None)
        slow_command = [sys.executable, "-c",
                        "import subprocess,time; subprocess.Popen(['/bin/sleep','10']); time.sleep(10)"]
        healthy_command = [sys.executable, "-c",
                           "import json; print(json.dumps({'id':'healthy','today':3}))"]
        started = time.monotonic()
        with ThreadPoolExecutor(max_workers=2) as pool:
            slow = pool.submit(collector.collect_isolated, slow_source, 0.1, slow_command)
            healthy = pool.submit(collector.collect_isolated, healthy_source, 2, healthy_command)
            slow_result, healthy_result = slow.result(), healthy.result()
        self.assertIn("timed out", slow_result["error"].lower())
        self.assertEqual(healthy_result["today"], 3)
        self.assertLess(time.monotonic() - started, 3)

    def test_isolated_source_decodes_success_and_reports_exit_status(self):
        source = ("test", "Test source", None)
        success = collector.collect_isolated(
            source, timeout=2,
            command=[sys.executable, "-c", "import json; print(json.dumps({'id':'test','today':3}))"])
        self.assertEqual(success["today"], 3)
        failed = collector.collect_isolated(
            source, timeout=2,
            command=[sys.executable, "-c", "import sys; print('collector failed',file=sys.stderr); sys.exit(7)"])
        self.assertEqual(failed["error"], "collector failed")

    def test_active_block_rate_uses_cost_over_elapsed_block_time(self):
        now = collector.datetime.now().astimezone()
        started = (now - collector.timedelta(hours=2)).replace(minute=0, second=0, microsecond=0)
        entries = [{"when": started + collector.timedelta(minutes=5), "cost": 10.0}]
        hours = (collector.datetime.now().astimezone() - started).total_seconds() / 3600
        self.assertAlmostEqual(collector.active_block_rate(entries), 10.0 / hours, delta=0.01)
        self.assertEqual(collector.active_block_rate([{"when": now - collector.timedelta(hours=9), "cost": 10.0}]), 0.0)
        self.assertEqual(collector.active_block_rate([]), 0.0)

    def test_deepseek_prices_peak_hours_and_aliases(self):
        usage = {"inputTokens": 1_000_000, "cacheReadTokens": 1_000_000, "outputTokens": 1_000_000}
        monday_peak = collector.datetime(2026, 1, 5, 2, tzinfo=collector.timezone.utc).timestamp() * 1000
        monday_off_peak = collector.datetime(2026, 1, 5, 12, tzinfo=collector.timezone.utc).timestamp() * 1000
        saturday = collector.datetime(2026, 1, 10, 2, tzinfo=collector.timezone.utc).timestamp() * 1000
        self.assertAlmostEqual(collector.deepseek_cost(usage, "deepseek-flash", monday_off_peak), 0.753)
        self.assertAlmostEqual(collector.deepseek_cost(usage, "deepseek-flash", monday_peak), 1.506)
        self.assertAlmostEqual(collector.deepseek_cost(usage, "deepseek-v4-flash", monday_peak), 1.506)
        # Weekends are always off-peak, even inside a peak window.
        self.assertAlmostEqual(collector.deepseek_cost(usage, "deepseek-flash", saturday), 0.753)
        self.assertIsNone(collector.deepseek_cost(usage, "mystery-model", monday_peak))

    def test_deepseek_folds_sessions_into_windows_models_and_chats(self):
        now_ms = int(time.time() * 1000) - 60_000
        with tempfile.TemporaryDirectory() as home, patch.object(collector, "HOME", home):
            def sample(turn, step, model, **usage):
                return {"type": "assistant/message", "seq": 1, "time": now_ms,
                        "data": {"turn": turn, "step": step,
                                 "usage": {"inputTokens": 0, "outputTokens": 0, "cacheReadTokens": 0,
                                           "cacheWriteTokens": 0, **usage},
                                 "message": {"source": {"kind": "model", "model": model}}}}
            first = sample(1, 1, "deepseek-flash", inputTokens=2_000_000, outputTokens=500_000)
            second = sample(1, 1, "deepseek-v4-pro", cacheReadTokens=3_000_000)
            collector_session = {"type": "session", "version": 4, "id": "s", "cwd": "/tmp"}
            for project, session_id, title, records in [
                    ("--alpha--", "session-a", "Alpha", [collector_session,
                                                         {"type": "session/title", "data": {"title": "Alpha"}}, first]),
                    ("--beta--", "session-b", "Beta", [collector_session,
                                                       {"type": "session/title", "data": {"title": "Beta"}}, second])]:
                folder = Path(home, ".dsh/sessions", project, session_id)
                folder.mkdir(parents=True)
                (folder / "session.v4.jsonl").write_text("\n".join(json.dumps(r) for r in records) + "\n")
            result = collector.deepseek()
        expected_first = collector.deepseek_cost(first["data"]["usage"], "deepseek-flash", now_ms)
        expected_second = collector.deepseek_cost(second["data"]["usage"], "deepseek-v4-pro", now_ms)
        self.assertAlmostEqual(result["today"], expected_first + expected_second)
        self.assertAlmostEqual(result["week"], expected_first + expected_second)
        self.assertAlmostEqual(result["month"], expected_first + expected_second)
        self.assertAlmostEqual(result["rate"], expected_first + expected_second)
        self.assertEqual([c["name"] for c in result["chats"]], ["Alpha", "Beta"])
        self.assertEqual([m["name"] for m in result["models"]], ["deepseek-flash", "deepseek-v4-pro"])

    def test_deepseek_skips_fork_prefix_and_keeps_last_sample_per_step(self):
        now_ms = int(time.time() * 1000) - 60_000
        def sample(moment, tokens):
            return {"type": "assistant/message", "seq": 1, "time": moment,
                    "data": {"turn": 1, "step": 1,
                             "usage": {"inputTokens": tokens, "outputTokens": 0, "cacheReadTokens": 0},
                             "message": {"source": {"kind": "model", "model": "deepseek-flash"}}}}
        records = [{"type": "session", "version": 4, "id": "s", "inheritedEventCount": 1},
                   sample(now_ms, 50_000_000),          # inherited from the fork's parent: never billed twice
                   sample(now_ms, 1_000_000),           # own step, superseded below
                   sample(now_ms, 2_000_000)]
        with tempfile.TemporaryDirectory() as home, patch.object(collector, "HOME", home):
            folder = Path(home, ".dsh/sessions/--alpha--/session-a")
            folder.mkdir(parents=True)
            (folder / "session.v4.jsonl").write_text("\n".join(json.dumps(r) for r in records) + "\n")
            result = collector.deepseek()
        self.assertAlmostEqual(result["today"], collector.deepseek_cost(
            {"inputTokens": 2_000_000}, "deepseek-flash", now_ms))

    @unittest.skipUnless(HAS_STDLIB_ZSTD, "needs Python 3.14+ stdlib zstd")
    def test_deepseek_reads_compressed_session_logs(self):
        from compression import zstd
        now_ms = int(time.time() * 1000) - 60_000
        record = {"type": "assistant/message", "seq": 1, "time": now_ms,
                  "data": {"turn": 1, "step": 1, "usage": {"outputTokens": 1_000_000},
                           "message": {"source": {"kind": "model", "model": "deepseek-flash"}}}}
        with tempfile.TemporaryDirectory() as home, patch.object(collector, "HOME", home):
            folder = Path(home, ".dsh/sessions/--alpha--/session-a")
            folder.mkdir(parents=True)
            (folder / "session.v4.jsonl.zstd").write_bytes(zstd.compress(json.dumps(record).encode()))
            result = collector.deepseek()
        self.assertAlmostEqual(result["today"], collector.deepseek_cost(
            {"outputTokens": 1_000_000}, "deepseek-flash", now_ms))

    def test_deepseek_reports_an_unpriced_model(self):
        now_ms = int(time.time() * 1000) - 60_000
        record = {"type": "assistant/message", "seq": 1, "time": now_ms,
                  "data": {"turn": 1, "step": 1, "usage": {"outputTokens": 10},
                           "message": {"source": {"kind": "model", "model": "mystery-model"}}}}
        with tempfile.TemporaryDirectory() as home, patch.object(collector, "HOME", home):
            folder = Path(home, ".dsh/sessions/--alpha--/session-a")
            folder.mkdir(parents=True)
            (folder / "session.v4.jsonl").write_text(json.dumps(record) + "\n")
            with self.assertRaisesRegex(RuntimeError, "No DeepSeek price for mystery-model"):
                collector.deepseek()


if __name__ == "__main__":
    unittest.main()
