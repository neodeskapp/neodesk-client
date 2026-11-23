#!/usr/bin/env python3
"""Generate RustDesk-style download tables for NeoDesk GitHub Releases.

Scans a directory of release assets and emits Markdown with clear product
labels (Full Client vs Incoming-only Support Agent) and per-arch download links.
"""

from __future__ import annotations

import argparse
import re
from pathlib import Path


ARCH_ROWS = (
    ("x86_64", "x86-64 (64-bit)"),
    ("aarch64", "AArch64 (ARM64)"),
)

# Ordered platform columns for the main matrix.
PLATFORM_COLS = (
    ("windows", "Windows"),
    ("linux", "Ubuntu / Linux"),
    ("macos", "Mac"),
)


def _url(repo: str, tag: str, name: str) -> str:
    return f"https://github.com/{repo}/releases/download/{tag}/{name}"


def _link(label: str, repo: str, tag: str, name: str | None) -> str:
    if not name:
        return ""
    return f"[{label}]({_url(repo, tag, name)})"


# A package's version: 1.5.0, or a pre-release such as 1.5.0-rc.4 or 1.5.0-dev.42.
# It starts with a digit, so neodesk-template-x86_64.msi is not taken for the MSI.
_VERSION = r"\d+\.\d+\.\d+(?:-[0-9A-Za-z.]+)?"


def _classify_desktop(name: str) -> tuple[str, str, str] | None:
    """Return (platform, arch, kind) for full desktop assets."""
    # neodesk-1.5.0-windows-x86_64.exe / .msi (older releases: neodesk-1.5.0-x86_64.exe).
    m = re.match(rf"^neodesk-{_VERSION}-(?:windows-)?(x86_64|aarch64)\.(exe|msi)$", name)
    if m:
        return "windows", m.group(1), m.group(2)
    # neodesk-1.5.0-windows-x86_64.tar.gz
    m = re.match(rf"^neodesk-{_VERSION}-windows-(x86_64|aarch64)\.tar\.gz$", name)
    if m:
        return "windows", m.group(1), "portable"
    # neodesk-1.5.0-linux-x86_64.deb / .rpm / -suse.rpm / -portable.tar.gz
    m = re.match(
        rf"^neodesk-{_VERSION}-linux-(x86_64|aarch64)(?:-(suse))?(\.deb|\.rpm|-portable\.tar\.gz)$",
        name,
    )
    if m:
        arch = m.group(1)
        suse = m.group(2)
        ext = m.group(3)
        if ext == ".deb":
            return "linux", arch, "deb"
        if ext == ".rpm" and suse:
            return "linux", arch, "suse"
        if ext == ".rpm":
            return "linux", arch, "rpm"
        if ext == "-portable.tar.gz":
            return "linux", arch, "portable"
    # neodesk-1.5.0-macos-x86_64.dmg / -portable.zip (older releases: .tar.gz)
    m = re.match(rf"^neodesk-{_VERSION}-macos-(x86_64|aarch64)(\.dmg|-portable\.zip|\.tar\.gz)$", name)
    if m:
        kind = "dmg" if m.group(2) == ".dmg" else "portable"
        return "macos", m.group(1), kind
    return None


def _classify_support(name: str) -> tuple[str, str, str] | None:
    """Return (platform, arch, kind) for Support Agent assets."""
    m = re.match(
        r"^neodesk-support-generic-(windows|linux|macos)-(x86_64|aarch64)\.(zip|tar\.gz|msi|exe)$",
        name,
    )
    if not m:
        return None
    platform, arch, ext = m.groups()
    kind = {
        "zip": "portable",
        "tar.gz": "portable",
        "msi": "msi",
        "exe": "exe",
    }[ext]
    return platform, arch, kind


def index_assets(asset_dir: Path, product: str) -> dict[tuple[str, str, str], str]:
    classify = _classify_desktop if product == "desktop" else _classify_support
    out: dict[tuple[str, str, str], str] = {}
    for path in sorted(asset_dir.iterdir()):
        if not path.is_file():
            continue
        hit = classify(path.name)
        if not hit:
            continue
        platform, arch, kind = hit
        out[(platform, arch, kind)] = path.name
    return out


def _cell(assets: dict[tuple[str, str, str], str], platform: str, arch: str, repo: str, tag: str) -> str:
    parts: list[str] = []
    if platform == "windows":
        for kind, label in (("exe", "EXE"), ("msi", "MSI"), ("portable", "Portable")):
            name = assets.get((platform, arch, kind))
            if not name:
                continue
            if kind == "portable":
                label = "ZIP" if name.endswith(".zip") else "Portable"
            parts.append(_link(label, repo, tag, name))
    elif platform == "linux":
        for kind, label in (("deb", "DEB"), ("rpm", "RPM"), ("suse", "SUSE"), ("portable", "Portable")):
            name = assets.get((platform, arch, kind))
            if name:
                parts.append(_link(label, repo, tag, name))
    elif platform == "macos":
        for kind, label in (("dmg", "DMG"), ("portable", "Portable")):
            name = assets.get((platform, arch, kind))
            if name:
                parts.append(_link(label, repo, tag, name))
    return " &nbsp; ".join(parts)


def render_table(
    *,
    product: str,
    assets: dict[tuple[str, str, str], str],
    repo: str,
    tag: str,
) -> str:
    if product == "desktop":
        title = "### Full Client (NeoDesk Desktop)"
        blurb = (
            "**Type:** full remote-desktop client (`product_sku=neodesk-desktop`). "
            "Can connect outbound and accept inbound. Configure the server in "
            "**Settings → Network** (or via a deploy string from the NeoDesk panel)."
        )
    else:
        title = "### Incoming-only Support Agent"
        blurb = (
            "**Type:** incoming-only Support Agent (`product_sku=neodesk-support`). "
            "Accepts remote support only — does **not** start outbound sessions to other devices. "
            "On first run enter your NeoDesk server URL and pair with a QR code. "
            "Import into the panel via **NeoDesk Agents → Import latest release**."
        )

    lines = [
        title,
        "",
        blurb,
        "",
        "| Architecture | " + " | ".join(col[1] for col in PLATFORM_COLS) + " |",
        "|--------------|" + "|".join(["---------"] * len(PLATFORM_COLS)) + "|",
    ]
    for arch_key, arch_label in ARCH_ROWS:
        cells = [_cell(assets, plat, arch_key, repo, tag) for plat, _ in PLATFORM_COLS]
        if not any(cells):
            continue
        lines.append("| " + arch_label + " | " + " | ".join(cells) + " |")
    lines.append("")
    return "\n".join(lines)


def render_notes(
    *,
    product: str,
    asset_dir: Path,
    repo: str,
    tag: str,
    release_name: str,
    commit: str = "",
    extra_md: str = "",
    intro_md: str = "",
) -> str:
    assets = index_assets(asset_dir, product)
    if intro_md.strip():
        # The release's own notes take the place of the heading and the line under it
        parts = [intro_md.strip(), "", "## Downloads", ""]
    else:
        parts = [
            f"## {release_name}",
            "",
        ]
        if product == "desktop":
            parts.extend(
                [
                    "Official **NeoDesk Client** build — full desktop remote client.",
                    "",
                ]
            )
        else:
            parts.extend(
                [
                    "Official **NeoDesk Support Agent** build — generic incoming-only agents.",
                    "",
                ]
            )
    if commit:
        parts.append(f"- Commit: `{commit}`")
        parts.append(f"- Tag: `{tag}`")
        parts.append("")

    parts.append(render_table(product=product, assets=assets, repo=repo, tag=tag))

    # Other useful assets (templates, manifests) as a short list
    other = []
    for path in sorted(asset_dir.iterdir()):
        if not path.is_file():
            continue
        name = path.name
        if product == "desktop":
            if name.startswith("generator-templates") or name.endswith("generator-manifest.json"):
                other.append(f"- [{name}]({_url(repo, tag, name)}) — clean Generator templates")
            elif name == "neodesk-desktop-manifest.json":
                other.append(f"- [{name}]({_url(repo, tag, name)}) — desktop release manifest")
            elif name == "SHA256SUMS":
                other.append(f"- [{name}]({_url(repo, tag, name)}) — checksums of every file in this release")
        else:
            if name in ("manifest.json", "manifest.sig", "SHA256SUMS"):
                other.append(f"- [{name}]({_url(repo, tag, name)})")
    if other:
        parts.append("### Other assets")
        parts.append("")
        parts.extend(other)
        parts.append("")

    if product == "desktop":
        parts.extend(
            [
                "### Also available: Support Agent",
                "",
                "Incoming-only Support Agent packages are published as separate "
                "`support-v*` releases on this repository "
                f"(see [Releases](https://github.com/{repo}/releases) tagged `support-v*`).",
                "",
            ]
        )
    else:
        parts.extend(
            [
                "### Also available: Full Client",
                "",
                "Full NeoDesk desktop clients (EXE / MSI / DEB / DMG) are published as "
                f"`desktop/*` releases — see [Releases](https://github.com/{repo}/releases).",
                "",
            ]
        )

    if extra_md.strip():
        parts.append(extra_md.strip())
        parts.append("")

    return "\n".join(parts).rstrip() + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--product", choices=("desktop", "support"), required=True)
    parser.add_argument("--asset-dir", type=Path, required=True)
    parser.add_argument("--repo", default="neodeskapp/neodesk-client")
    parser.add_argument("--tag", required=True)
    parser.add_argument("--release-name", required=True)
    parser.add_argument("--commit", default="")
    parser.add_argument("--extra-md", default="")
    parser.add_argument("--extra-md-file", type=Path, default=None)
    parser.add_argument(
        "--intro-md-file",
        type=Path,
        default=None,
        help="the release's own notes, put first in place of the heading (used when the file exists)",
    )
    parser.add_argument("-o", "--output", type=Path, required=True)
    args = parser.parse_args()

    extra = args.extra_md
    if args.extra_md_file and args.extra_md_file.is_file():
        extra = args.extra_md_file.read_text(encoding="utf-8")

    intro = ""
    if args.intro_md_file and args.intro_md_file.is_file():
        intro = args.intro_md_file.read_text(encoding="utf-8")

    notes = render_notes(
        product=args.product,
        asset_dir=args.asset_dir,
        repo=args.repo,
        tag=args.tag,
        release_name=args.release_name,
        commit=args.commit,
        extra_md=extra,
        intro_md=intro,
    )
    args.output.write_text(notes, encoding="utf-8")
    print(f"Wrote {args.output} ({len(notes)} bytes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
