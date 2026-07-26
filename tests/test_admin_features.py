import importlib.util
import json
import os
import re
import shlex
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SERVER_PATH = ROOT / "admin-web" / "server.py"
INDEX_PATH = ROOT / "admin-web" / "static" / "index.html"


def load_server(tmpdir: Path):
    os.environ["GOTELEGRAM_BACKUP_DIR"] = str(tmpdir / "backups")
    os.environ["GOTELEGRAM_DIR"] = str(tmpdir / "gotelegram")
    os.environ["TELEMT_CONFIG"] = str(tmpdir / "etc" / "telemt" / "config.toml")
    os.environ["GOTELEGRAM_DISABLED_USERS"] = str(tmpdir / "gotelegram" / "disabled_users.json")
    module_name = "gotelegram_admin_server_test"
    sys.modules.pop(module_name, None)
    spec = importlib.util.spec_from_file_location(module_name, SERVER_PATH)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


class AdminFeatureTests(unittest.TestCase):
    def test_system_metrics_are_safe_and_bounded(self):
        with tempfile.TemporaryDirectory() as raw:
            server = load_server(Path(raw))
            metrics = server.system_metrics()

        self.assertGreaterEqual(metrics["cpu_count"], 1)
        self.assertGreaterEqual(metrics["cpu_percent"], 0)
        self.assertLessEqual(metrics["cpu_percent"], 100)
        self.assertIn("percent", metrics["memory"])
        self.assertIn("percent", metrics["disk"])
        self.assertGreaterEqual(metrics["uptime_seconds"], 0)

    def test_dashboard_contains_system_gauges_and_key_search(self):
        html = INDEX_PATH.read_text(encoding="utf-8")

        self.assertIn('id="cpuGauge"', html)
        self.assertIn('id="memoryGauge"', html)
        self.assertIn('id="diskGauge"', html)
        self.assertIn('id="userSearch"', html)

    def test_backup_path_accepts_only_local_archives(self):
        with tempfile.TemporaryDirectory() as raw:
            tmpdir = Path(raw)
            server = load_server(tmpdir)
            server.BACKUP_DIR.mkdir(parents=True)
            good = server.BACKUP_DIR / "gotelegram_backup_20260425_120000.tar.gz"
            good.write_text("backup", encoding="utf-8")
            encrypted = server.BACKUP_DIR / "gotelegram_backup_20260425_120001.tar.gz.enc"
            encrypted.write_text("backup", encoding="utf-8")
            legacy = server.BACKUP_DIR / "backup_20260425_120002.tar.gz"
            legacy.write_text("backup", encoding="utf-8")

            self.assertEqual(server.safe_backup_path(good.name), good.resolve())
            self.assertEqual(server.safe_backup_path(encrypted.name), encrypted.resolve())
            self.assertEqual(server.safe_backup_path(legacy.name), legacy.resolve())

            with self.assertRaises(ValueError):
                server.safe_backup_path("../outside.tar.gz")
            with self.assertRaises(ValueError):
                server.safe_backup_path("gotelegram_backup_20260425_120000.tar.gz.sha256")
            with self.assertRaises(FileNotFoundError):
                server.safe_backup_path("missing.tar.gz")

    def test_backup_schedule_calendar_rejects_unknown_values(self):
        with tempfile.TemporaryDirectory() as raw:
            server = load_server(Path(raw))
            self.assertEqual(server.backup_schedule_calendar("daily"), "*-*-* 03:20:00")
            self.assertEqual(server.backup_schedule_calendar("weekly"), "Sun 03:20:00")
            self.assertEqual(server.backup_schedule_calendar("monthly"), "*-*-01 03:20:00")
            self.assertIsNone(server.backup_schedule_calendar("off"))

            with self.assertRaises(ValueError):
                server.backup_schedule_calendar("hourly")

    def test_user_records_include_active_disabled_and_ip_limits(self):
        with tempfile.TemporaryDirectory() as raw:
            tmpdir = Path(raw)
            server = load_server(tmpdir)
            server.TELEMT_CONFIG.parent.mkdir(parents=True)
            server.TELEMT_CONFIG.write_text(
                "\n".join([
                    "[access.users]",
                    'main = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"',
                    'client = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"',
                    "",
                    "[access.user_max_unique_ips]",
                    "main = 0",
                    "client = 2",
                    "disabled = 1",
                    "",
                ]),
                encoding="utf-8",
            )
            server.DISABLED_USERS_FILE.parent.mkdir(parents=True)
            server.DISABLED_USERS_FILE.write_text(
                json.dumps({"users": {"disabled": "cccccccccccccccccccccccccccccccc"}}),
                encoding="utf-8",
            )

            records = server.read_user_records()

            self.assertTrue(records["client"]["enabled"])
            self.assertEqual(records["client"]["max_unique_ips"], 2)
            self.assertFalse(records["disabled"]["enabled"])
            self.assertEqual(records["disabled"]["max_unique_ips"], 1)
            self.assertEqual(records["main"]["max_unique_ips"], 0)

    def test_write_user_max_unique_ips_preserves_other_toml_sections(self):
        with tempfile.TemporaryDirectory() as raw:
            server = load_server(Path(raw))
            server.TELEMT_CONFIG.parent.mkdir(parents=True)
            server.TELEMT_CONFIG.write_text(
                "\n".join([
                    "[server]",
                    "port = 443",
                    "",
                    "[access.users]",
                    'main = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"',
                    'client = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"',
                    "",
                    "[access.user_max_unique_ips]",
                    "client = 3",
                    "old = 4",
                    "",
                    "[network]",
                    'dns_overrides = ["example.com:8443:127.0.0.1"]',
                    "",
                ]),
                encoding="utf-8",
            )

            server.write_user_max_unique_ips({"main": 1, "client": 0, "new": 5})
            text = server.TELEMT_CONFIG.read_text(encoding="utf-8")

            self.assertIn("[server]\nport = 443", text)
            self.assertIn("[network]\ndns_overrides", text)
            self.assertIn("[access.user_max_unique_ips]", text)
            self.assertIn('"main" = 1', text)
            self.assertIn('"new" = 5', text)
            self.assertNotIn("client = 3", text)
            self.assertNotIn("old = 4", text)

    def test_key_card_traffic_uses_live_ip_counts_not_stale_history(self):
        with tempfile.TemporaryDirectory() as raw:
            server = load_server(Path(raw))
            stale_history = {
                "epoch": 1000,
                "total_octets": 100,
                "current_connections": 16,
                "active_unique_ips": 8,
                "recent_unique_ips": 5,
            }
            original = server.runtime_user_traffic
            server.runtime_user_traffic = lambda name, enabled=True: {
                "ok": True,
                "enabled": True,
                "total_octets": 200,
                "current_connections": 0,
                "active_unique_ips": 0,
                "recent_unique_ips": 0,
            }
            try:
                snapshot = server.current_user_traffic_snapshot("client", True, stale_history, now=2000)
            finally:
                server.runtime_user_traffic = original

            self.assertEqual(snapshot["epoch"], 2000)
            self.assertEqual(snapshot["total_octets"], 200)
            self.assertEqual(snapshot["current_connections"], 0)
            self.assertEqual(snapshot["active_unique_ips"], 0)
            self.assertEqual(snapshot["recent_unique_ips"], 0)

    def test_key_card_traffic_fallback_keeps_only_historical_total(self):
        with tempfile.TemporaryDirectory() as raw:
            server = load_server(Path(raw))
            stale_history = {
                "epoch": 1000,
                "total_octets": 100,
                "current_connections": 16,
                "active_unique_ips": 8,
                "recent_unique_ips": 5,
            }
            original = server.runtime_user_traffic
            server.runtime_user_traffic = lambda name, enabled=True: {"ok": False}
            try:
                snapshot = server.current_user_traffic_snapshot("client", True, stale_history, now=2000)
            finally:
                server.runtime_user_traffic = original

            self.assertEqual(snapshot["epoch"], 1000)
            self.assertEqual(snapshot["total_octets"], 100)
            self.assertEqual(snapshot["current_connections"], 0)
            self.assertEqual(snapshot["active_unique_ips"], 0)
            self.assertEqual(snapshot["recent_unique_ips"], 0)

    def test_keys_view_uses_card_layout_without_horizontal_table(self):
        app_js = (ROOT / "admin-web" / "static" / "app.js").read_text(encoding="utf-8")
        styles = (ROOT / "admin-web" / "static" / "styles.css").read_text(encoding="utf-8")
        index = (ROOT / "admin-web" / "static" / "index.html").read_text(encoding="utf-8")

        self.assertNotIn('class="actions"', app_js)
        self.assertIn('class="key-card', app_js)
        self.assertIn('class="key-card-actions"', app_js)
        self.assertIn('class="action-buttons"', app_js)
        self.assertIn('class="key-name-button"', app_js)
        self.assertIn(".key-card .mini-actions,\n.key-card .action-buttons", styles)
        self.assertIn("grid-template-columns: 1fr", styles)
        self.assertIn("min-height: 44px", styles)
        self.assertNotIn("td.actions", styles)
        self.assertIn('class="keys-list" id="usersTable"', index)
        self.assertNotIn('class="keys-table"', index)

    def test_topbar_has_five_second_auto_refresh_toggle(self):
        app_js = (ROOT / "admin-web" / "static" / "app.js").read_text(encoding="utf-8")
        styles = (ROOT / "admin-web" / "static" / "styles.css").read_text(encoding="utf-8")
        index = (ROOT / "admin-web" / "static" / "index.html").read_text(encoding="utf-8")

        self.assertIn('id="autoRefreshToggle"', index)
        self.assertIn('data-i18n-title="autoRefresh"', index)
        self.assertIn("gotelegram-auto-refresh", app_js)
        self.assertIn("AUTO_REFRESH_MS = 5000", app_js)
        self.assertIn("setInterval", app_js)
        self.assertIn("clearInterval", app_js)
        self.assertIn(".auto-refresh-toggle", styles)

    def test_get_config_value_secret_accepts_quoted_main_user(self):
        with tempfile.TemporaryDirectory() as raw:
            config = Path(raw) / "config.toml"
            config.write_text(
                "\n".join([
                    "[access.users]",
                    '"main" = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"',
                    '"client" = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"',
                    "",
                ]),
                encoding="utf-8",
            )
            script = "\n".join([
                "set -e",
                f"source {shlex.quote(str(ROOT / 'lib' / 'telemt_config.sh'))}",
                f"get_config_value secret {shlex.quote(str(config))}",
            ])

            result = subprocess.run(
                ["bash", "-lc", script],
                cwd=ROOT,
                text=True,
                capture_output=True,
                check=False,
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.strip(), "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")

    def test_telemt_users_block_detects_quoted_main_user(self):
        script = "\n".join([
            "set -e",
            f"source {shlex.quote(str(ROOT / 'lib' / 'telemt_config.sh'))}",
            "block=$'\"main\" = \"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\"\\n\"client\" = \"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\"'",
            "telemt_users_block_has_main \"$block\"",
        ])

        result = subprocess.run(
            ["bash", "-lc", script],
            cwd=ROOT,
            text=True,
            capture_output=True,
            check=False,
        )

        self.assertEqual(result.returncode, 0, result.stderr)

    def test_telemt_restart_requests_are_debounced(self):
        with tempfile.TemporaryDirectory() as raw:
            server = load_server(Path(raw))
            calls = []
            original_run = server.run
            original_status = server.service_status
            try:
                server._LAST_TELEMT_RESTART = 0.0
                server.TELEMT_RESTART_DEBOUNCE_SECONDS = 30.0
                server.service_status = lambda name: "running"

                def fake_run(cmd, timeout=8):
                    calls.append(cmd)
                    return 0, "", ""

                server.run = fake_run
                self.assertTrue(server.request_service_restart("telemt"))
                self.assertTrue(server.request_service_restart("telemt"))
            finally:
                server.run = original_run
                server.service_status = original_status

            restart_calls = [cmd for cmd in calls if cmd[:3] == ["systemctl", "--no-block", "restart"]]
            self.assertEqual(len(restart_calls), 1)


if __name__ == "__main__":
    unittest.main()
