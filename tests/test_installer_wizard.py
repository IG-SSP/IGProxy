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

    def test_reserved_local_service_ports_are_not_public_candidates(self):
        result = run_bash(
            """
installer_port_listener() { return 0; }
for port in 1984 9090 9091; do
  installer_port_is_usable "$port" && exit 1
done
true
"""
        )
        self.assertEqual(result.returncode, 0, result.stderr)

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

    def test_preflight_json_is_machine_readable(self):
        result = run_bash(
            """
installer_preflight_collect() {
  INSTALLER_PREFLIGHT_FATAL=0
  INSTALLER_PF_OS='Test "Linux"'
  INSTALLER_PF_ARCH=amd64
  INSTALLER_PF_MEMORY_MB=512
  INSTALLER_PF_DISK_MB=2048
  INSTALLER_PF_INODE_FREE=90
  INSTALLER_PF_IP=203.0.113.1
  INSTALLER_PF_PORT80=свободен
  INSTALLER_PF_PORT443=занят
  INSTALLER_PF_RECOMMENDED_PORT=9443
  INSTALLER_PF_ADMIN=свободен
  INSTALLER_PF_METRICS=свободен
  INSTALLER_PF_API=свободен
  INSTALLER_PF_FIREWALL='не обнаружен'
  INSTALLER_PF_SELINUX='не установлен'
  INSTALLER_PF_EXISTING=нет
}
installer_preflight_json
"""
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        import json
        payload = json.loads(result.stdout)
        self.assertTrue(payload["ready"])
        self.assertEqual(payload["recommended_proxy_port"], "9443")
        self.assertEqual(payload["os"], 'Test "Linux"')

    def test_mode_picker_keeps_prompt_visible_and_stdout_machine_clean(self):
        result = run_bash("printf '2\\n' | installer_choose_mode")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "lite")
        self.assertIn("Что установить?", result.stderr)

    def test_operator_installation_is_russian_only(self):
        install = INSTALL.read_text(encoding="utf-8")
        self.assertIn('load_language "ru"', install)
        self.assertNotIn("    first_run_language_picker\n", install)
        self.assertIn("installer_choose_mode", install)
        self.assertIn("installer_preflight_run", install)
        self.assertIn("--check-json", install)
        self.assertIn("--dry-run", install)
        self.assertIn("Это был предварительный просмотр: система не изменялась.", install)

    def test_pro_mode_uses_selected_public_and_internal_ports(self):
        install = INSTALL.read_text(encoding="utf-8")
        telemt = (ROOT / "lib" / "telemt_config.sh").read_text(encoding="utf-8")

        self.assertIn('generate_telemt_toml "$raw_secret" "$public_port" "pro"', install)
        self.assertIn('save_gotelegram_config "telemt" "pro" "$public_port"', install)
        self.assertIn('show_proxy_info_pro "$user_domain" "$faketls_secret" "$public_port" "$nginx_internal_port"', install)
        self.assertIn('format_https_url "$user_domain" "$public_port"', install)
        self.assertIn('tf install_arch_desc1 "$public_port"', install)
        self.assertIn('tf install_arch_desc3 "$user_domain" "$public_port"', install)
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
        self.assertIn("ssl_certificate_is_usable", website)
        self.assertIn("-checkend 86400", website)
        self.assertIn('-checkhost "$domain"', website)
        self.assertIn("gotelegram-certbot.XXXXXX", website)

    def test_russian_operator_text_does_not_expose_internal_mode_names(self):
        russian = (ROOT / "lib" / "lang" / "ru.sh").read_text(encoding="utf-8")
        website = (ROOT / "lib" / "website.sh").read_text(encoding="utf-8")
        telemt = (ROOT / "lib" / "telemt_config.sh").read_text(encoding="utf-8")
        visible = "\n".join((russian, website, telemt))
        self.assertNotIn("Pro-режим", visible)
        self.assertNotIn("pro-режим", visible)
        self.assertNotIn("Lite-режим", visible)

    def test_stats_follow_configured_ports_instead_of_hardcoded_443(self):
        stats = (ROOT / "lib" / "stats.sh").read_text(encoding="utf-8")
        self.assertIn("stats_proxy_port()", stats)
        self.assertIn("stats_site_port()", stats)
        self.assertIn("--dport \"$proxy_port\"", stats)
        self.assertIn("--dport \"$site_port\"", stats)
        self.assertIn("gotelegram-proxy", stats)
        self.assertIn("gotelegram-site", stats)

    def test_selinux_port_change_is_transactional(self):
        wizard = WIZARD.read_text(encoding="utf-8")
        install = INSTALL.read_text(encoding="utf-8")
        self.assertIn("installer_prepare_selinux_http_port", wizard)
        self.assertIn("semanage port -a -t http_port_t -p tcp", wizard)
        self.assertIn("selinux-http-ports.manifest", wizard)
        self.assertIn("semanage port -d -t http_port_t -p tcp", wizard)
        self.assertIn(
            'installer_prepare_selinux_http_port "$nginx_internal_port"',
            install,
        )

    def test_selected_ports_are_checked_against_firewall(self):
        wizard = WIZARD.read_text(encoding="utf-8")
        install = INSTALL.read_text(encoding="utf-8")
        self.assertIn("installer_firewall_check_ports", wizard)
        self.assertIn('installer_firewall_check_ports "$port"', install)
        self.assertIn('installer_firewall_check_ports "$public_port" 80', install)
        self.assertNotIn("ufw allow ${port}/tcp >/dev/null", wizard)
        self.assertNotIn("firewall-cmd --permanent --add-port=${port}/tcp >/dev/null", wizard)

    def test_telemt_3425_is_pinned_with_verified_download_and_split_mss(self):
        common = (ROOT / "lib" / "common.sh").read_text(encoding="utf-8")
        telemt = (ROOT / "lib" / "telemt.sh").read_text(encoding="utf-8")
        config = (ROOT / "lib" / "telemt_config.sh").read_text(encoding="utf-8")

        self.assertIn('TELEMT_PINNED_VERSION="3.4.25"', common)
        self.assertIn('${TELEMT_PINNED_VERSION:-3.4.25}', telemt)
        self.assertIn('"${url}.sha256"', telemt)
        self.assertIn('sha256sum "$tmp_file"', telemt)
        self.assertIn('local client_mss_bulk="1400"', config)
        self.assertIn('client_mss_bulk = \\"${client_mss_bulk}\\"', config)


if __name__ == "__main__":
    unittest.main()
