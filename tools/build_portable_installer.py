#!/usr/bin/env python3
"""Build a deterministic self-contained goTelegram installer."""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MARKER = "__GOTELEGRAM_ARCHIVE_BELOW__"

_RELEASE_SPEC = importlib.util.spec_from_file_location(
    "gotelegram_build_release",
    ROOT / "tools" / "build_release.py",
)
if _RELEASE_SPEC is None or _RELEASE_SPEC.loader is None:
    raise RuntimeError("cannot load release builder")
_RELEASE_MODULE = importlib.util.module_from_spec(_RELEASE_SPEC)
_RELEASE_SPEC.loader.exec_module(_RELEASE_MODULE)
build_release = _RELEASE_MODULE.build


def digest_bytes(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def build(output: Path) -> str:
    output = output.resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    archive = output.with_name(f".{output.name}.payload.tar.gz")
    archive_sha = build_release(archive)
    archive_bytes = archive.read_bytes()
    bootstrap = (ROOT / "bootstrap.sh").read_text(encoding="utf-8")
    archive.unlink()
    archive.with_suffix(archive.suffix + ".sha256").unlink(missing_ok=True)

    header = f"""#!/bin/bash
set -eu

EXPECTED_RELEASE_SHA256="{archive_sha}"
ARCHIVE_MARKER="{MARKER}"
WORK_DIR=$(mktemp -d /tmp/gotelegram-portable.XXXXXX)
chmod 700 "$WORK_DIR"
cleanup() {{
    rm -rf -- "$WORK_DIR"
}}
trap cleanup EXIT INT TERM HUP

ARCHIVE_LINE=$(LC_ALL=C awk -v marker="$ARCHIVE_MARKER" '$0 == marker {{ print NR + 1; exit }}' "$0")
[ -n "$ARCHIVE_LINE" ] || {{
    echo "Ошибка: встроенный архив не найден." >&2
    exit 1
}}
tail -n +"$ARCHIVE_LINE" "$0" > "$WORK_DIR/release.tar.gz"
ACTUAL_SHA256=$(sha256sum "$WORK_DIR/release.tar.gz" | awk '{{print $1}}')
[ "$ACTUAL_SHA256" = "$EXPECTED_RELEASE_SHA256" ] || {{
    echo "Ошибка: контрольная сумма встроенного релиза не совпала." >&2
    exit 1
}}

cat > "$WORK_DIR/bootstrap.sh" <<'__GOTELEGRAM_BOOTSTRAP__'
{bootstrap.rstrip()}
__GOTELEGRAM_BOOTSTRAP__
chmod 700 "$WORK_DIR/bootstrap.sh"

GOTELEGRAM_RELEASE_URL="file://$WORK_DIR/release.tar.gz" \\
GOTELEGRAM_RELEASE_SHA256="$EXPECTED_RELEASE_SHA256" \\
bash "$WORK_DIR/bootstrap.sh" "$@"
exit 0

{MARKER}
""".encode("utf-8")

    output.write_bytes(header + archive_bytes)
    output.chmod(0o755)
    installer_sha = digest_bytes(header + archive_bytes)
    output.with_suffix(output.suffix + ".sha256").write_text(
        f"{installer_sha}  {output.name}\n",
        encoding="ascii",
    )
    return installer_sha


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--output",
        type=Path,
        default=ROOT.parent / "build" / "gotelegram-installer.run",
    )
    args = parser.parse_args()
    print(build(args.output))


if __name__ == "__main__":
    main()
