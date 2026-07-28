#!/usr/bin/env python3
"""Build a deterministic goTelegram release archive and its SHA-256 file."""

from __future__ import annotations

import argparse
import gzip
import hashlib
import io
import os
from pathlib import Path, PurePosixPath
import re
import subprocess
import tarfile


ROOT = Path(__file__).resolve().parents[1]
PAYLOAD_PATHS = (
    "install.sh",
    "install_gotelegram_bot.sh",
    "templates_catalog.json",
    "lib",
    "cluster",
    "gotelegram-bot",
    "admin-web",
    "site-presets",
    "DEPLOYMENT_PROFILES.md",
    "INSTALLER_GUIDE.md",
)

FORBIDDEN_RELEASE_NAMES = {
    ".env",
    "id_dsa",
    "id_ecdsa",
    "id_ed25519",
    "id_rsa",
}
FORBIDDEN_RELEASE_SUFFIXES = {".key", ".p12", ".pfx"}
FORBIDDEN_RELEASE_CONTENT = (
    ("private key", re.compile(rb"-----BEGIN (?:OPENSSH |RSA |EC |DSA )?PRIVATE KEY-----")),
    ("GitHub token", re.compile(rb"(?:github_pat_|gh[pousr]_[A-Za-z0-9_]{20,})")),
    ("Telegram bot token", re.compile(rb"\b[0-9]{8,12}:[A-Za-z0-9_-]{25,}\b")),
    (
        "configured proxy URL",
        re.compile(rb"(?:tg://proxy|https?://t\.me/proxy)\?[^\s\"']*secret=[A-Za-z0-9_-]{16,}"),
    ),
)


def validate_release_file(path: Path, name: PurePosixPath) -> None:
    lower_name = name.name.lower()
    if lower_name in FORBIDDEN_RELEASE_NAMES or name.suffix.lower() in FORBIDDEN_RELEASE_SUFFIXES:
        raise RuntimeError(f"refusing to package sensitive filename: {name.as_posix()}")
    payload = path.read_bytes()
    for label, pattern in FORBIDDEN_RELEASE_CONTENT:
        if pattern.search(payload):
            raise RuntimeError(f"refusing to package {label} in {name.as_posix()}")


def validate_release_source(
    path: Path, name: PurePosixPath, root: Path = ROOT
) -> None:
    if path.is_symlink():
        raise RuntimeError(f"refusing to package symlink: {name.as_posix()}")
    try:
        path.resolve(strict=True).relative_to(root.resolve(strict=True))
    except (FileNotFoundError, ValueError) as error:
        raise RuntimeError(
            f"release source escapes repository root: {name.as_posix()}"
        ) from error
    if not path.is_file():
        raise FileNotFoundError(f"tracked release file is missing: {name.as_posix()}")
    validate_release_file(path, name)


def tracked_release_file(relative: str) -> Path:
    result = subprocess.run(
        ["git", "-C", str(ROOT), "ls-files", "--error-unmatch", "--", relative],
        check=True,
        capture_output=True,
    )
    tracked_name = result.stdout.decode("utf-8").strip()
    if tracked_name != relative:
        raise RuntimeError(f"unexpected tracked release path: {tracked_name!r}")
    name = PurePosixPath(relative)
    source = ROOT.joinpath(*name.parts)
    validate_release_source(source, name)
    return source


def payload_files() -> list[tuple[Path, PurePosixPath]]:
    for relative in PAYLOAD_PATHS:
        if not (ROOT / relative).exists():
            raise FileNotFoundError(f"required release path is missing: {relative}")

    result = subprocess.run(
        ["git", "-C", str(ROOT), "ls-files", "-z", "--", *PAYLOAD_PATHS],
        check=True,
        capture_output=True,
    )
    tracked = [item for item in result.stdout.split(b"\0") if item]
    if not tracked:
        raise RuntimeError("git returned an empty release manifest")

    files: list[tuple[Path, PurePosixPath]] = []
    for raw_name in tracked:
        relative = PurePosixPath(raw_name.decode("utf-8"))
        source = ROOT.joinpath(*relative.parts)
        validate_release_source(source, relative)
        files.append((source, relative))
    return sorted(files, key=lambda item: item[1].as_posix())


def digest(path: Path) -> str:
    result = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            result.update(chunk)
    return result.hexdigest()


def tar_info(path: Path, archive_name: str) -> tarfile.TarInfo:
    info = tarfile.TarInfo(archive_name)
    stat = path.stat()
    info.size = stat.st_size
    info.mtime = 0
    info.uid = 0
    info.gid = 0
    info.uname = "root"
    info.gname = "root"
    info.mode = 0o755 if os.access(path, os.X_OK) or path.suffix in {".sh", ".py"} else 0o644
    return info


def build(output: Path) -> str:
    files = payload_files()
    manifest = "".join(f"{digest(path)}  {name.as_posix()}\n" for path, name in files)

    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("wb") as raw:
        with gzip.GzipFile(filename="", mode="wb", fileobj=raw, mtime=0) as zipped:
            with tarfile.open(fileobj=zipped, mode="w", format=tarfile.PAX_FORMAT) as archive:
                for path, name in files:
                    with path.open("rb") as stream:
                        archive.addfile(tar_info(path, name.as_posix()), stream)
                manifest_bytes = manifest.encode("utf-8")
                manifest_info = tarfile.TarInfo("RELEASE-MANIFEST.sha256")
                manifest_info.size = len(manifest_bytes)
                manifest_info.mtime = 0
                manifest_info.uid = manifest_info.gid = 0
                manifest_info.uname = manifest_info.gname = "root"
                manifest_info.mode = 0o644
                archive.addfile(manifest_info, io.BytesIO(manifest_bytes))

    archive_sha = digest(output)
    output.with_suffix(output.suffix + ".sha256").write_text(
        f"{archive_sha}  {output.name}\n", encoding="ascii"
    )
    return archive_sha


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--output",
        type=Path,
        default=ROOT.parent / "build" / "gotelegram-release.tar.gz",
    )
    args = parser.parse_args()
    print(build(args.output.resolve()))


if __name__ == "__main__":
    main()
