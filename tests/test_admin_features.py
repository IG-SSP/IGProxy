import importlib.util
import json
import os
import re
import shlex
import subprocess
import sys
import tempfile
import unittest
from unittest import mock
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SERVER_PATH = ROOT / "admin-web" / "server.py"
INDEX_PATH = ROOT / "admin-web" / "static" / "index.html"
APP_JS_PATH = ROOT / "admin-web" / "static" / "app.js"


def load_server(tmpdir: Path):
    os.environ["GOTELEGRAM_BACKUP_DIR"] = str(tmpdir / "backups")
    os.environ["GOTELEGRAM_DIR"] = str(tmpdir / "gotelegram")
    os.environ["TELEMT_CONFIG"] = str(tmpdir / "etc" / "telemt" / "config.toml")
    os.environ["GOTELEGRAM_DISABLED_USERS"] = str(tmpdir / "gotelegram" / "disabled_users.json")
    os.environ["GOTELEGRAM_WEBSITE_ROOT"] = str(tmpdir / "site")
    os.environ["GOTELEGRAM_SITE_PRESETS"] = str(ROOT / "site-presets")
    module_name = "gotelegram_admin_server_test"
    sys.modules.pop(module_name, None)
    spec = importlib.util.spec_from_file_location(module_name, SERVER_PATH)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


class AdminFeatureTests(unittest.TestCase):
    def test_admin_version_comes_from_activated_release(self):
        server = SERVER_PATH.read_text(encoding="utf-8")
        index = INDEX_PATH.read_text(encoding="utf-8")
        self.assertIn("def runtime_version(", server)
        self.assertIn('INSTALL_DIR / "current" / "lib" / "common.sh"', server)
        self.assertIn('"version": runtime_version(config)', server)
        self.assertIn('aria-label="Расписание бекапов"', index)

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

    def test_site_status_uses_configured_alternate_public_port(self):
        with tempfile.TemporaryDirectory() as raw:
            server = load_server(Path(raw))
            with mock.patch.object(server, "run", return_value=(0, "200", "")) as runner:
                result = server.site_status({"domain": "example.com", "port": 9443})
            self.assertEqual(result["url"], "https://example.com:9443/")
            self.assertIn("https://example.com:9443/", runner.call_args.args[0])

    def test_port_map_keeps_site_route_on_alternate_public_port(self):
        with tempfile.TemporaryDirectory() as raw:
            server = load_server(Path(raw))
            with (
                mock.patch.object(server, "load_json", return_value={"mode": "pro", "domain": "example.com", "port": 9443}),
                mock.patch.object(server, "read_telemt_edge_settings", return_value={"mask_port": 8443, "tls_domain": "example.com", "dns_overrides": []}),
                mock.patch.object(server, "load_shared443_config", return_value={"enabled": False}),
                mock.patch.object(server, "collect_port_listeners", return_value=([], [])),
                mock.patch.object(server, "read_telemt_port", return_value=9443),
            ):
                result = server.port_443_status()
            self.assertEqual(result["configured_port"], 9443)
            self.assertEqual(result["routes"][0]["public"], "example.com:9443")

    def test_dashboard_contains_system_gauges_and_key_search(self):
        html = INDEX_PATH.read_text(encoding="utf-8")

        self.assertIn('id="cpuGauge"', html)
        self.assertIn('id="memoryGauge"', html)
        self.assertIn('id="diskGauge"', html)
        self.assertIn('id="userSearch"', html)

    def test_admin_is_russian_only(self):
        html = INDEX_PATH.read_text(encoding="utf-8")
        script = APP_JS_PATH.read_text(encoding="utf-8")

        self.assertIn('<html lang="ru">', html)
        self.assertNotIn('id="languageSelect"', html)
        self.assertNotIn("function setLanguage", script)
        self.assertIn('lang: "ru"', script)

    def test_charts_use_smooth_curves(self):
        script = APP_JS_PATH.read_text(encoding="utf-8")
        html = INDEX_PATH.read_text(encoding="utf-8")

        self.assertIn("smoothSvgPath", script)
        self.assertIn("pathLength=\"1\"", script)
        self.assertIn("linearGradient", script)
        self.assertIn('id="trafficInsights"', html)
        self.assertIn("chartExplanation", script)
        self.assertIn("stableHtml(el, html", script)

    def test_backup_path_accepts_only_local_archives(self):
        with tempfile.TemporaryDirectory() as raw:
            tmpdir = Path(raw)
            server = load_server(tmpdir)
            server.BACKUP_DIR.mkdir(parents=True)
            good = server.BACKUP_DIR / "gotelegram_backup_20260425_120000.tar.gz"
            good.write_text("backup", encoding="utf-8")
            encrypted = server.BACKUP_DIR / "gotelegram_backup_20260425_120001.tar.gz.enc"
            encrypted.write_text("backup", encoding="utf-8")
            protected = server.BACKUP_DIR / "gotelegram_backup_20260425_120002.tar.gz.gpg"
            protected.write_text("backup", encoding="utf-8")
            legacy = server.BACKUP_DIR / "backup_20260425_120002.tar.gz"
            legacy.write_text("backup", encoding="utf-8")

            self.assertEqual(server.safe_backup_path(good.name), good.resolve())
            self.assertEqual(server.safe_backup_path(encrypted.name), encrypted.resolve())
            self.assertEqual(server.safe_backup_path(protected.name), protected.resolve())
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
        self.assertIn('class="key-card-access"', app_js)
        self.assertIn('class="key-live-grid"', app_js)
        self.assertIn('class="key-name-button"', app_js)
        self.assertIn(".key-secret-line", styles)
        self.assertIn('data-user-filter="online"', index)
        self.assertIn('id="keysDashboard"', index)
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
        self.assertIn("refreshAll({ silent: true })", app_js)

    def test_dashboard_layout_and_human_logs_have_new_ui(self):
        html = INDEX_PATH.read_text(encoding="utf-8")
        script = APP_JS_PATH.read_text(encoding="utf-8")
        styles = (ROOT / "admin-web" / "static" / "styles.css").read_text(encoding="utf-8")

        self.assertIn("dashboard-health-grid", html)
        self.assertIn("repeat(auto-fit, minmax(145px, 1fr))", styles)
        self.assertIn("@media (max-width: 1500px)", styles)
        self.assertIn('data-log-view="human"', html)
        self.assertIn('id="humanLogs"', html)
        self.assertIn("function explainLogLine", script)
        self.assertIn("const grouped = []", script)
        self.assertIn('`Порт ${configuredPort}`', script)
        self.assertIn("fmtSystemdTime", script)
        self.assertIn('id="backupDashboard"', html)
        self.assertIn("modePresentation", script)

    def test_igproxy_brand_graph_controls_and_site_settings_exist(self):
        html = INDEX_PATH.read_text(encoding="utf-8")
        script = APP_JS_PATH.read_text(encoding="utf-8")
        styles = (ROOT / "admin-web" / "static" / "styles.css").read_text(encoding="utf-8")
        server = (ROOT / "admin-web" / "server.py").read_text(encoding="utf-8")

        self.assertIn("<strong>IGProxy</strong>", html)
        self.assertNotIn("goTelegram Clean", html)
        self.assertIn('data-traffic-metric="rate"', html)
        self.assertIn('id="trafficSmooth"', html)
        self.assertIn("chart-point", script)
        self.assertIn('id="siteSettingsForm"', html)
        self.assertIn("/api/site/settings", server)
        self.assertIn("apply_site_preset", server)
        self.assertIn('"route-workshop"', server)
        self.assertIn(".site-preset-card", styles)

    def test_dashboard_uses_full_width_and_operational_status_cards(self):
        html = INDEX_PATH.read_text(encoding="utf-8")
        styles = (ROOT / "admin-web" / "static" / "styles.css").read_text(encoding="utf-8")
        script = APP_JS_PATH.read_text(encoding="utf-8")
        self.assertIn(".content {\n  width: 100%;", styles)
        self.assertNotIn("width: min(1480px, 100%)", styles)
        self.assertIn('id="proxyStatus"', html)
        self.assertIn('id="portConnections"', html)
        self.assertIn('id="portActiveIps"', html)
        self.assertNotIn("без скачущих названий", script)
        self.assertIn("Причины сбоев", script)

    def test_traffic_controls_and_charts_support_real_time_axis(self):
        html = INDEX_PATH.read_text(encoding="utf-8")
        script = APP_JS_PATH.read_text(encoding="utf-8")
        self.assertIn('data-traffic-range="6h"', html)
        self.assertIn('data-traffic-range="7d"', html)
        self.assertIn('id="trafficHideIdle"', html)
        self.assertIn('id="trafficTableOrder"', html)
        self.assertIn("new Map()", script)
        self.assertIn("lastEpoch - firstEpoch", script)
        self.assertIn("userTrafficMetric", script)

    def test_random_and_custom_sites_are_available(self):
        server = SERVER_PATH.read_text(encoding="utf-8")
        html = INDEX_PATH.read_text(encoding="utf-8")
        random_site = (ROOT / "site-presets" / "random-gallery" / "index.html").read_text(encoding="utf-8")
        self.assertIn('"random-gallery"', server)
        self.assertIn("apply_custom_site", server)
        self.assertIn("/api/site/custom", server)
        self.assertIn('id="customSiteForm"', html)
        self.assertEqual(
            len(re.findall(r'^\s+\["(?:editorial|transit|cartography|terminal|botanical|postcard|tearoom|beacon|poster|playground)"', random_site, re.M)),
            10,
        )
        self.assertIn("Скопировать ссылку", random_site)
        self.assertIn("__PROXY_LINK__", random_site)
        self.assertIn("__LAYOUT__", random_site)
        self.assertIn("margin-top:-24px", random_site)
        self.assertIn(".tag::before", random_site)
        self.assertEqual(len(re.findall(r"/\* \d{2} —", random_site)), 10)
        for layout in ("editorial", "transit", "cartography", "terminal", "botanical", "postcard", "tearoom", "beacon", "poster", "playground"):
            self.assertIn(f'"layout": "{layout}"', server)

    def test_dashboard_navigation_runtime_and_upload_ux(self):
        html = INDEX_PATH.read_text(encoding="utf-8")
        script = APP_JS_PATH.read_text(encoding="utf-8")
        styles = (ROOT / "admin-web" / "static" / "styles.css").read_text(encoding="utf-8")

        self.assertGreater(html.index('id="trafficInsights"'), html.index('id="trafficChart"'))
        self.assertIn('data-dashboard-jump="traffic"', html)
        self.assertIn('id="portHealthBadge"', html)
        self.assertIn('id="customSiteDrop"', html)
        self.assertIn('id="customSiteFileName"', html)
        self.assertNotIn('{ key: "admin", label: "admin"', script)
        self.assertIn("Что делать", script)
        self.assertIn('data-restart="telemt"', script)
        self.assertIn('eventObj.target.closest("[data-dashboard-jump]")', script)
        self.assertIn(".events-list .event", styles)
        self.assertIn("overflow-wrap: anywhere", styles)

    def test_counter_resets_are_counted_as_new_traffic(self):
        previous = os.environ.get("GOTELEGRAM_STATS_HISTORY")
        try:
            with tempfile.TemporaryDirectory() as raw:
                root = Path(raw)
                history = root / "stats.csv"
                history.write_text(
                    "epoch,proxy_bytes,site_bytes\n100,1000,500\n160,1200,600\n220,40,20\n",
                    encoding="utf-8",
                )
                os.environ["GOTELEGRAM_STATS_HISTORY"] = str(history)
                server = load_server(root)
                rows = server.load_stats_history()
        finally:
            if previous is None:
                os.environ.pop("GOTELEGRAM_STATS_HISTORY", None)
            else:
                os.environ["GOTELEGRAM_STATS_HISTORY"] = previous
        self.assertEqual(rows[-1]["proxy_delta"], 40)
        self.assertEqual(rows[-1]["site_delta"], 20)

    def test_site_preset_is_rendered_for_selected_key_and_is_world_readable(self):
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            config = root / "etc" / "telemt" / "config.toml"
            config.parent.mkdir(parents=True)
            config.write_text(
                '[access.users]\nmain = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"\n',
                encoding="utf-8",
            )
            server = load_server(root)
            with mock.patch.object(server, "proxy_link", return_value="tg://proxy?test=1"):
                payload = server.apply_site_preset("glass-garden", "main")

            index = (server.WEBSITE_ROOT / "index.html").read_text(encoding="utf-8")
            self.assertIn("tg://proxy?test=1", index)
            self.assertNotIn("__PROXY_LINK__", index)
            self.assertEqual(payload["preset"], "glass-garden")
            self.assertTrue(server.WEBSITE_ROOT.stat().st_mode & 0o005)

    def test_fixed_story_preset_selects_its_own_visual_layout(self):
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            config = root / "etc" / "telemt" / "config.toml"
            config.parent.mkdir(parents=True)
            config.write_text(
                '[access.users]\nmain = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"\n',
                encoding="utf-8",
            )
            server = load_server(root)
            with mock.patch.object(server, "proxy_link", return_value="https://t.me/proxy?test=1"):
                payload = server.apply_site_preset("story-transit", "main")

            index = (server.WEBSITE_ROOT / "index.html").read_text(encoding="utf-8")
            self.assertIn('const requested="transit"', index)
            self.assertNotIn("__LAYOUT__", index)
            self.assertIn("https://t.me/proxy?test=1", index)
            self.assertEqual(payload["preset"], "story-transit")

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
