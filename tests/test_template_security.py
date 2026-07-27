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
