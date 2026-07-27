#!/usr/bin/env python3
"""Build a deterministic goTelegram release archive and its SHA-256 file."""

from __future__ import annotations

import argparse
import gzip
import hashlib
import io
import os
from pathlib import Path, PurePosixPath
import tarfile


ROOT = Path(__file__).resolve().parents[1]
PAYLOAD_PATHS = (
    "install.sh",
    "install_gotelegram_bot.sh",
    "templates_catalog.json",
    "lib",
    "gotelegram-bot",
    "admin-web",
    "site-presets",
    "DEPLOYMENT_PROFILES.md",
)


def payload_files() -> list[tuple[Path, PurePosixPath]]:
    files: list[tuple[Path, PurePosixPath]] = []
    for relative in PAYLOAD_PATHS:
        source = ROOT / relative
        if source.is_file():
            files.append((source, PurePosixPath(relative)))
        elif source.is_dir():
            for child in sorted(source.rglob("*")):
                if child.is_file() and "__pycache__" not in child.parts:
                    files.append((child, PurePosixPath(child.relative_to(ROOT).as_posix())))
        else:
            raise FileNotFoundError(f"required release path is missing: {relative}")
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
