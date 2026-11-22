#!/usr/bin/env python3
"""Check collect_desktop_dist.sh against fake build artifacts of one CI run.

Needs bash, dpkg-deb, tar, zip and sha256sum (all on the Ubuntu runners).
"""

from __future__ import annotations

import hashlib
import subprocess
import sys
import tarfile
import tempfile
import zipfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
SCRIPT = HERE / "collect_desktop_dist.sh"
VERSION = "1.5.0"
BINARY = b"\0" * 40000  # above the generator's minimum binary size


def write(path: Path, data: bytes = b"x") -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)
    return path


def fake_raw(raw: Path, platforms: set[str]) -> None:
    for arch in ("x86_64", "aarch64"):
        if f"windows-{arch}" in platforms:
            build = raw / f"rustdesk-unsigned-windows-{arch}"
            write(build / "betterdesk.exe", BINARY)
            write(build / "rustdesk.exe", BINARY)
            write(build / "librustdesk.dll")
            write(raw / "windows-installers" / f"betterdesk-{VERSION}-{arch}.exe", b"exe " + arch.encode())
            write(raw / "windows-installers" / f"betterdesk-{VERSION}-{arch}.msi", b"msi " + arch.encode())
            write(raw / "msi-template-arts" / f"betterdesk-template-{arch}.msi")
            write(raw / "msi-template-arts" / f"rustdesk-template-{arch}.msi")
        if f"macos-{arch}" in platforms:
            art = raw / f"betterdesk-unsigned-macos-{arch}"
            write(art / f"betterdesk-{VERSION}-{arch}.dmg", b"dmg " + arch.encode())
            app = art.parent / f"app-{arch}" / "BetterDesk Client.app"
            write(app / "Contents" / "MacOS" / "BetterDesk Client", BINARY)
            with tarfile.open(art / f"betterdesk-{VERSION}-{arch}-app.tar.gz", "w:gz") as tar:
                tar.add(app, arcname=app.name)
            if arch == "aarch64":
                # The x86_64 leg leaves the zip out to cover the fallback.
                with zipfile.ZipFile(art / f"betterdesk-{VERSION}-{arch}-app.zip", "w") as zf:
                    zf.writestr("BetterDesk Client.app/Contents/MacOS/BetterDesk Client", BINARY)
        if f"linux-{arch}" in platforms:
            root = raw.parent / f"deb-{arch}"
            write(root / "usr/share/rustdesk/betterdesk", BINARY)
            write(root / "usr/share/rustdesk/lib/librustdesk.so")
            write(root / "DEBIAN/control", (
                f"Package: betterdesk\nVersion: {VERSION}\nArchitecture: all\n"
                "Maintainer: test\nDescription: test\n"
            ).encode())
            deb = raw / "linux-debs" / f"betterdesk-{VERSION}-{arch}.deb"
            deb.parent.mkdir(parents=True, exist_ok=True)
            subprocess.run(["dpkg-deb", "-b", str(root), str(deb)], check=True, capture_output=True)
            write(raw / "linux-rpms" / f"betterdesk-{VERSION}-0.{arch}.rpm", b"rpm")
            write(raw / "linux-rpms" / f"betterdesk-{VERSION}-0.{arch}-suse.rpm", b"suse")


def run(*args: str) -> subprocess.CompletedProcess:
    return subprocess.run(["bash", str(SCRIPT), *args], capture_output=True, text=True)


def expect(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"FAIL: {message}")


def check_full(tmp: Path) -> None:
    every = {f"{os}-{arch}" for os in ("windows", "linux", "macos") for arch in ("x86_64", "aarch64")}
    raw, dist = tmp / "raw", tmp / "dist"
    fake_raw(raw, every)
    result = run("collect", str(raw), str(dist), VERSION)
    expect(result.returncode == 0, f"collect failed: {result.stderr}")

    names = {p.name for p in (dist / "clean").iterdir()}
    expected = set()
    for arch in ("x86_64", "aarch64"):
        expected |= {
            f"betterdesk-{VERSION}-windows-{arch}.exe",
            f"betterdesk-{VERSION}-windows-{arch}.msi",
            f"betterdesk-{VERSION}-windows-{arch}.tar.gz",
            f"betterdesk-{VERSION}-linux-{arch}.deb",
            f"betterdesk-{VERSION}-linux-{arch}.rpm",
            f"betterdesk-{VERSION}-linux-{arch}-suse.rpm",
            f"betterdesk-{VERSION}-linux-{arch}-portable.tar.gz",
            f"betterdesk-{VERSION}-macos-{arch}.dmg",
            f"betterdesk-{VERSION}-macos-{arch}-portable.zip",
        }
    expect(names == expected, f"clean/ has {sorted(names ^ expected)} beyond or missing from the expected set")

    clean = dist / "clean"
    expect((clean / f"betterdesk-{VERSION}-windows-aarch64.exe").read_bytes() == b"exe aarch64",
           "windows aarch64 exe is not the aarch64 build")
    expect((clean / f"betterdesk-{VERSION}-linux-x86_64-suse.rpm").read_bytes() == b"suse",
           "suse rpm mixed up with the plain rpm")
    with tarfile.open(clean / f"betterdesk-{VERSION}-linux-x86_64-portable.tar.gz") as tar:
        members = set(tar.getnames())
    expect("./betterdesk" in members and "./lib/librustdesk.so" in members,
           f"linux portable tarball lacks the app folder: {sorted(members)}")
    for arch in ("x86_64", "aarch64"):
        with zipfile.ZipFile(clean / f"betterdesk-{VERSION}-macos-{arch}-portable.zip") as zf:
            listed = zf.namelist()
        expect(any(n.endswith("BetterDesk Client.app/Contents/MacOS/BetterDesk Client") for n in listed),
               f"macos {arch} zip lacks the app: {listed}")
    expect(sorted(p.name for p in (dist / "msi-template").iterdir())
           == ["betterdesk-template-aarch64.msi", "betterdesk-template-x86_64.msi"],
           "msi templates not renamed")
    for folder in every:
        expect((dist / folder).is_dir(), f"missing unpacked build {folder}")
    expect(not (dist / "macos-x86_64" / f"betterdesk-{VERSION}-x86_64.dmg").exists(),
           "the dmg ended up in the unpacked macOS build")

    result = run("sums", str(clean))
    expect(result.returncode == 0, f"sums failed: {result.stderr}")
    lines = (clean / "SHA256SUMS").read_text().splitlines()
    listed = {line.split("  ", 1)[1]: line.split("  ", 1)[0] for line in lines}
    expect(set(listed) == expected, "SHA256SUMS does not list exactly the packages")
    for name, digest in listed.items():
        expect(hashlib.sha256((clean / name).read_bytes()).hexdigest() == digest, f"wrong hash for {name}")
    check = subprocess.run(["sha256sum", "-c", "SHA256SUMS"], cwd=clean, capture_output=True, text=True)
    expect(check.returncode == 0, f"sha256sum -c failed: {check.stdout}{check.stderr}")

    result = run("sums", str(clean))
    expect(result.returncode == 0 and len((clean / "SHA256SUMS").read_text().splitlines()) == len(expected),
           "a second sums run lists SHA256SUMS itself")

    pack = subprocess.run(
        [sys.executable, str(HERE / "pack_generator_templates.py"), "--dist-root", str(dist),
         "--out", str(tmp / "templates"), "--version", VERSION],
        capture_output=True, text=True,
    )
    expect(pack.returncode == 0, f"generator templates reject the layout: {pack.stdout}{pack.stderr}")

    # A release carries the MSI templates next to the packages; the download
    # table must still link the real installers.
    for msi in (dist / "msi-template").iterdir():
        (clean / msi.name).write_bytes(msi.read_bytes())
    run("sums", str(clean))
    notes_path = tmp / "notes.md"
    table = subprocess.run(
        [sys.executable, str(HERE / "generate_release_download_table.py"), "--product", "desktop",
         "--asset-dir", str(clean), "--repo", "trybetterdesk/betterdesk-client", "--tag", "desktop/1.5.0",
         "--release-name", "BetterDesk Client 1.5.0", "-o", str(notes_path)],
        capture_output=True, text=True,
    )
    expect(table.returncode == 0, f"download table failed: {table.stderr}")
    notes = notes_path.read_text(encoding="utf-8")
    base = "https://github.com/trybetterdesk/betterdesk-client/releases/download/desktop/1.5.0/"
    for name in sorted(expected) + ["SHA256SUMS"]:
        expect(f"({base}{name})" in notes, f"download table does not link {name}")
    expect("betterdesk-template-" not in notes.split("### Other assets")[0],
           "download table links an MSI template as an installer")


def check_partial(tmp: Path) -> None:
    raw, dist = tmp / "raw", tmp / "dist"
    fake_raw(raw, {"linux-x86_64"})
    result = run("collect", str(raw), str(dist), VERSION)
    expect(result.returncode == 0, f"collect of one platform failed: {result.stderr}")
    expect(sorted(p.name for p in dist.iterdir()) == ["clean", "linux-x86_64"],
           f"partial run made folders for platforms it did not build: {sorted(p.name for p in dist.iterdir())}")
    pack = subprocess.run(
        [sys.executable, str(HERE / "pack_generator_templates.py"), "--dist-root", str(dist),
         "--out", str(tmp / "templates"), "--version", VERSION, "--allow-missing"],
        capture_output=True, text=True,
    )
    expect(pack.returncode == 0, f"generator templates reject a partial layout: {pack.stdout}{pack.stderr}")


def check_empty(tmp: Path) -> None:
    (tmp / "raw").mkdir()
    result = run("collect", str(tmp / "raw"), str(tmp / "dist"), VERSION)
    expect(result.returncode != 0, "collect succeeded without any packages")


def main() -> int:
    for check in (check_full, check_partial, check_empty):
        with tempfile.TemporaryDirectory(prefix="betterdesk-collect-") as value:
            check(Path(value))
        print(f"{check.__name__}: OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
