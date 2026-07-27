import subprocess
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
WIZARD = ROOT / "lib" / "installer_wizard.sh"
INSTALL = ROOT / "install.sh"
BOOTSTRAP = ROOT / "bootstrap.sh"


def run_bash(body: str) -> subprocess.CompletedProcess[str]:
    script = f"""
set -u
GOTELEGRAM_DIR=/opt/gotelegram
GOTELEGRAM_CONFIG=/opt/gotelegram/config.json
TELEMT_CONFIG=/etc/telemt/config.toml
source {WIZARD.as_posix()!r}
{body}
"""
    return subprocess.run(
        ["bash", "-c", script],
        text=True,
        capture_output=True,
        check=False,
    )


class InstallerWizardTests(unittest.TestCase):
    def test_free_443_is_recommended(self):
        result = run_bash(
            """
installer_existing_public_port() { return 0; }
installer_port_is_usable() { [ "$1" = 443 ]; }
installer_pick_recommended_port
"""
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "443")

    def test_busy_443_falls_back_to_first_free_alternate(self):
        result = run_bash(
            """
installer_existing_public_port() { return 0; }
installer_port_is_usable() { [ "$1" = 9443 ]; }
installer_pick_recommended_port
"""
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "9443")

    def test_all_candidate_ports_busy_is_hard_failure(self):
        result = run_bash(
            """
installer_existing_public_port() { return 0; }
installer_port_is_usable() { return 1; }
installer_pick_recommended_port
"""
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout.strip(), "")

    def test_existing_telemt_listener_is_allowed_only_on_its_configured_port(self):
        result = run_bash(
            """
installer_port_listener() { printf 'LISTEN users:(("telemt",pid=42,fd=9))'; }
installer_existing_public_port() { printf '8443\\n'; }
installer_port_is_usable 8443
ok=$?
installer_port_is_usable 443
bad=$?
printf '%s:%s\\n' "$ok" "$bad"
"""
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "0:1")

    def test_internal_site_port_never_reuses_public_port(self):
        result = run_bash(
            """
installer_port_is_usable() { [ "$1" = 8443 ] || [ "$1" = 9443 ]; }
installer_pick_internal_port 8443
"""
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "9443")

    def test_reserved_service_port_must_be_bound_to_loopback(self):
        result = run_bash(
            """
systemctl() { return 0; }
installer_port_listener() { printf 'LISTEN 0 4096 0.0.0.0:%s users:(("telemt",pid=1))' "$1"; }
installer_reserved_port_status 9091 telemt
"""
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("публичная привязка", result.stdout)

    def test_operator_installation_is_russian_only(self):
        install = INSTALL.read_text(encoding="utf-8")
        self.assertIn('load_language "ru"', install)
        self.assertNotIn("    first_run_language_picker\n", install)
        self.assertIn("installer_choose_mode", install)
        self.assertIn("installer_preflight_run", install)

    def test_pro_mode_uses_selected_public_and_internal_ports(self):
        install = INSTALL.read_text(encoding="utf-8")
        telemt = (ROOT / "lib" / "telemt_config.sh").read_text(encoding="utf-8")

        self.assertIn('generate_telemt_toml "$raw_secret" "$public_port" "pro"', install)
        self.assertIn('save_gotelegram_config "telemt" "pro" "$public_port"', install)
        self.assertIn('show_proxy_info_pro "$user_domain" "$faketls_secret" "$public_port" "$nginx_internal_port"', install)
        self.assertIn('format_https_url "$user_domain" "$public_port"', install)
        self.assertIn('port=${public_port}', telemt)

    def test_bootstrap_contains_required_wizard_module(self):
        bootstrap = BOOTSTRAP.read_text(encoding="utf-8")
        self.assertIn("lib/installer_wizard.sh", bootstrap)
        self.assertIn("GOTELEGRAM_RELEASE_SHA256", bootstrap)
        self.assertIn("GOTELEGRAM_BOOTSTRAP_ACTIVATE_ONLY", bootstrap)
        self.assertIn('mv -Tf "$next_link" "$INSTALL_ROOT/current"', bootstrap)
        self.assertNotIn("GOTELEGRAM_PAT", bootstrap)
        self.assertNotIn("raw.githubusercontent.com", bootstrap)

    def test_install_is_wrapped_in_transaction_and_health_check(self):
        install = INSTALL.read_text(encoding="utf-8")
        wizard = WIZARD.read_text(encoding="utf-8")

        self.assertGreaterEqual(install.count("installer_transaction_begin"), 2)
        self.assertGreaterEqual(install.count("installer_transaction_rollback"), 8)
        self.assertGreaterEqual(install.count("installer_verify_install"), 2)
        self.assertGreaterEqual(install.count("installer_transaction_commit"), 2)
        self.assertIn("/run/lock/gotelegram-installer.lock", wizard)
        self.assertIn("chmod -R go-rwx", wizard)
        self.assertIn("Небезопасный путь в rollback-манифесте", wizard)
        self.assertIn("/etc/letsencrypt/live/$INSTALLER_TX_DOMAIN", wizard)
        self.assertIn("gotelegram-certbot-renew.timer", wizard)

    def test_certificate_renewal_does_not_modify_root_crontab(self):
        website = (ROOT / "lib" / "website.sh").read_text(encoding="utf-8")
        self.assertNotIn("crontab -l", website)
        self.assertIn("gotelegram-certbot-renew.timer", website)
        self.assertIn("Шаблон содержит ссылки или специальные файлы", website)
        self.assertIn(".gotelegram-site.XXXXXX", website)

    def test_stats_follow_configured_ports_instead_of_hardcoded_443(self):
        stats = (ROOT / "lib" / "stats.sh").read_text(encoding="utf-8")
        self.assertIn("stats_proxy_port()", stats)
        self.assertIn("stats_site_port()", stats)
        self.assertIn("--dport \"$proxy_port\"", stats)
        self.assertIn("--dport \"$site_port\"", stats)
        self.assertIn("gotelegram-proxy", stats)
        self.assertIn("gotelegram-site", stats)


if __name__ == "__main__":
    unittest.main()
