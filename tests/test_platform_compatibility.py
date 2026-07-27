import os
import subprocess
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
COMMON = ROOT / "lib" / "common.sh"
WIZARD = ROOT / "lib" / "installer_wizard.sh"


def nginx_paths(os_id: str) -> tuple[str, str]:
    env = os.environ.copy()
    env["GOTELEGRAM_OS_ID_OVERRIDE"] = os_id
    result = subprocess.run(
        [
            "bash",
            "-c",
            'source "$1"; printf "%s\\n%s\\n" "$NGINX_SITE_CONF" "$NGINX_SITE_LINK"',
            "bash",
            str(COMMON),
        ],
        check=True,
        capture_output=True,
        text=True,
        env=env,
    )
    return tuple(result.stdout.splitlines())


class PlatformCompatibilityTests(unittest.TestCase):
    def test_debian_nginx_uses_enabled_site_symlink(self):
        self.assertEqual(
            nginx_paths("ubuntu"),
            (
                "/etc/nginx/sites-available/gotelegram",
                "/etc/nginx/sites-enabled/gotelegram",
            ),
        )

    def test_rhel_nginx_uses_conf_d_directly(self):
        expected = "/etc/nginx/conf.d/gotelegram.conf"
        self.assertEqual(nginx_paths("rocky"), (expected, expected))

    def test_nginx_paths_can_be_overridden(self):
        env = os.environ.copy()
        env.update(
            {
                "GOTELEGRAM_OS_ID_OVERRIDE": "rocky",
                "NGINX_SITE_CONF": "/custom/nginx/site.conf",
                "NGINX_SITE_LINK": "/custom/nginx/enabled.conf",
            }
        )
        result = subprocess.run(
            [
                "bash",
                "-c",
                'source "$1"; printf "%s|%s" "$NGINX_SITE_CONF" "$NGINX_SITE_LINK"',
                "bash",
                str(COMMON),
            ],
            check=True,
            capture_output=True,
            text=True,
            env=env,
        )
        self.assertEqual(
            result.stdout,
            "/custom/nginx/site.conf|/custom/nginx/enabled.conf",
        )

    def test_selinux_http_port_parser_supports_ranges_and_single_ports(self):
        script = r'''
source "$1"
semanage() {
    printf '%s\n' \
      "http_port_t tcp 80, 443, 8008-8010, 8443" \
      "other_port_t tcp 9443"
}
installer_selinux_type_allows_port http_port_t 8009
installer_selinux_type_allows_port http_port_t 8443
! installer_selinux_type_allows_port http_port_t 9443
'''
        subprocess.run(
            ["bash", "-c", script, "bash", str(WIZARD)],
            check=True,
            capture_output=True,
            text=True,
        )

    def test_ufw_parser_accepts_numbered_rules_and_nginx_profiles(self):
        script = r'''
source "$1"
ufw() {
    printf '%s\n' \
      "Status: active" \
      "[ 1] 9443/tcp ALLOW IN Anywhere" \
      "[ 2] Nginx Full ALLOW IN Anywhere"
}
installer_ufw_allows_port 9443
installer_ufw_allows_port 80
installer_ufw_allows_port 443
! installer_ufw_allows_port 2053
'''
        subprocess.run(
            ["bash", "-c", script, "bash", str(WIZARD)],
            check=True,
            capture_output=True,
            text=True,
        )


if __name__ == "__main__":
    unittest.main()
