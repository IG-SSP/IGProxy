import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
WEBSITE = ROOT / "lib" / "website.sh"
TEMPLATES = ROOT / "lib" / "templates_catalog.sh"


class TemplateSecurityTests(unittest.TestCase):
    def test_template_cache_and_clones_use_private_locations(self):
        source = TEMPLATES.read_text(encoding="utf-8")
        self.assertIn("/var/cache/gotelegram/templates", source)
        self.assertIn("mktemp -d /tmp/gotelegram-template.XXXXXX", source)
        self.assertNotIn("_clone_$$", source)
        self.assertNotIn("custom_git_err_$$", source)

    @unittest.skipUnless(shutil.which("bash") and shutil.which("python3"), "requires bash and python3")
    def test_bundled_preset_is_rendered_with_proxy_link_and_layout(self):
        with tempfile.TemporaryDirectory() as raw:
            cache = Path(raw) / "cache"
            proxy_link = "https://t.me/proxy?server=example.com&port=9443&secret=eeabc"
            script = f"""
set -uo pipefail
IGPROXY_SITE_PRESETS_DIR={(ROOT / "site-presets").as_posix()!r}
TEMPLATES_CACHE={cache.as_posix()!r}
log_error() {{ printf '%s\\n' "$*" >&2; }}
log_dim() {{ :; }}
source {TEMPLATES.as_posix()!r}
igproxy_site_preset_rows() {{
    printf '%s\\n' 'story-transit|Test|Test|random-gallery|transit'
    python3 -c 'print("unused|x|x|random-gallery|auto\\n" * 20000, end="")'
}}
prepare_igproxy_site_preset story-transit {proxy_link!r}
"""
            result = subprocess.run(
                ["bash", "-c", script],
                check=False,
                capture_output=True,
                text=True,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            rendered_dir = Path(result.stdout.strip())
            rendered = (rendered_dir / "index.html").read_text(encoding="utf-8")
            self.assertIn(proxy_link, rendered)
            self.assertIn("tg://proxy?server=example.com&port=9443&secret=eeabc", rendered)
            self.assertIn('const requested="transit"', rendered)
            self.assertNotIn("__PROXY_LINK__", rendered)
            self.assertNotIn("__PROXY_TG_LINK__", rendered)
            self.assertNotIn("__LAYOUT__", rendered)

    @unittest.skipUnless(shutil.which("bash"), "requires bash")
    def test_deploy_rejects_symlink_payload(self):
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            template = root / "template"
            template.mkdir()
            (template / "index.html").write_text("safe", encoding="utf-8")
            try:
                (template / "escape").symlink_to("/etc/passwd")
            except OSError:
                self.skipTest("symlinks unavailable")
            target = root / "site"
            script = f"""
WEBSITE_ROOT={target.as_posix()!r}
log_error() {{ :; }}
log_success() {{ :; }}
log_dim() {{ :; }}
source {WEBSITE.as_posix()!r}
deploy_template_to_nginx {template.as_posix()!r}
"""
            result = subprocess.run(["bash", "-c", script], check=False)
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse(target.exists())


if __name__ == "__main__":
    unittest.main()
