import hashlib
import io
import shutil
import subprocess
import tarfile
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
BACKUP = ROOT / "lib" / "backup.sh"
BUILDER = ROOT / "tools" / "build_release.py"


class ReleaseSecurityTests(unittest.TestCase):
    def test_release_builder_is_deterministic_and_manifest_is_complete(self):
        with tempfile.TemporaryDirectory() as temp:
            first = Path(temp) / "first.tar.gz"
            second = Path(temp) / "second.tar.gz"
            subprocess.run(
                ["python", str(BUILDER), "--output", str(first)],
                check=True,
                capture_output=True,
                text=True,
            )
            subprocess.run(
                ["python", str(BUILDER), "--output", str(second)],
                check=True,
                capture_output=True,
                text=True,
            )
            self.assertEqual(first.read_bytes(), second.read_bytes())

            with tarfile.open(first, "r:gz") as archive:
                names = set(archive.getnames())
                manifest = archive.extractfile("RELEASE-MANIFEST.sha256")
                self.assertIsNotNone(manifest)
                entries = manifest.read().decode().splitlines()
                manifest_names = {line.split("  ", 1)[1] for line in entries}
                self.assertEqual(names - {"RELEASE-MANIFEST.sha256"}, manifest_names)
                for line in entries:
                    expected, name = line.split("  ", 1)
                    stream = archive.extractfile(name)
                    self.assertIsNotNone(stream)
                    self.assertEqual(hashlib.sha256(stream.read()).hexdigest(), expected)

    def test_backup_code_uses_private_tempdirs_and_no_password_argv(self):
        source = BACKUP.read_text(encoding="utf-8")
        self.assertIn("mktemp -d /tmp/gotelegram-backup.", source)
        self.assertIn("mktemp -d /tmp/gotelegram-restore.", source)
        self.assertIn("--passphrase-fd 0", source)
        self.assertIn("-pass stdin", source)
        self.assertNotIn('-pass "pass:${password}"', source)
        self.assertIn("backup_verify_checksum", source)
        self.assertIn("backup_archive_paths_are_safe", source)
        self.assertIn("create_backup_from_password_file", source)
        self.assertIn("restore_backup_from_password_file", source)

    def test_common_helpers_do_not_fall_back_to_predictable_root_tempfiles(self):
        source = (ROOT / "lib" / "common.sh").read_text(encoding="utf-8")
        self.assertIn("mktemp /tmp/gotelegram-spinner.XXXXXX", source)
        self.assertIn("mktemp /tmp/gotelegram-apt.XXXXXX", source)
        self.assertNotIn("spinner_err_$$", source)
        self.assertNotIn("apt_err.$$", source)

    @unittest.skipUnless(shutil.which("bash") and shutil.which("tar"), "requires bash and tar")
    def test_backup_rejects_parent_directory_archive_path(self):
        with tempfile.TemporaryDirectory() as temp:
            archive_path = Path(temp) / "unsafe.tar.gz"
            with tarfile.open(archive_path, "w:gz") as archive:
                payload = b"not allowed"
                info = tarfile.TarInfo("../outside")
                info.size = len(payload)
                archive.addfile(info, io.BytesIO(payload))
            script = (
                "log_error(){ :; }; "
                f"source {BACKUP.as_posix()!r}; "
                f"backup_archive_paths_are_safe {archive_path.as_posix()!r}"
            )
            result = subprocess.run(["bash", "-c", script], check=False)
            self.assertNotEqual(result.returncode, 0)


if __name__ == "__main__":
    unittest.main()
