#!/usr/bin/env python3
"""Generate the download table of a NeoDesk GitHub Release.

Scans a directory of release assets and writes the release notes: the
release's own notes, the download table right after their first paragraphs,
then the rest of the notes, and the checksums and change list folded away.

The table is HTML, one row per package and one column per architecture, with
the icons and the download button from res/release-icons, loaded from
raw.githubusercontent.com at --image-ref (the release's commit by default).
"""

from __future__ import annotations

import argparse
import html
import re
from pathlib import Path


# Columns of the table: (arch, heading, what it runs on)
ARCHES = (
    ("x86_64", "x64", "Intel, AMD"),
    ("aarch64", "ARM64", "Snapdragon, Apple silicon"),
)

# Systems, top to bottom: (platform, name, icon)
SYSTEMS = (
    ("windows", "Windows", "os-windows"),
    ("macos", "macOS", "os-macos"),
    ("linux", "Linux", "os-linux"),
)

# Rows of each system, top to bottom: (kind, icon, label, what it does)
DESKTOP_ROWS = {
    "windows": (
        ("msi", "pkg-windows-msi", "Installer", "Installs NeoDesk for all users, with its service. Pick this one."),
        ("exe", "pkg-windows-exe", "Program", "Starts NeoDesk right away, Install in it installs it."),
        ("portable", "pkg-windows-portable", "Portable", "Runs without installing."),
    ),
    "macos": (
        ("dmg", "pkg-macos-dmg", "Disk image", "Open it and drag NeoDesk Client to Applications."),
        ("portable", "pkg-macos-portable", "Portable", "The app in a zip, without the disk image."),
    ),
    "linux": (
        ("deb", "pkg-debian", "Debian package", "Debian, Ubuntu and Linux Mint."),
        ("rpm", "pkg-fedora", "RPM package", "Fedora, RHEL, Rocky Linux and AlmaLinux."),
        ("suse", "pkg-opensuse", "RPM for SUSE", "openSUSE and SLES."),
        ("portable", "pkg-linux-portable", "Portable", "Runs without installing."),
    ),
}

SUPPORT_ROWS = {
    "windows": (
        ("msi", "pkg-windows-msi", "Installer", "Installs the Support Agent with its service."),
        ("exe", "pkg-windows-exe", "Program", "Unpacks itself and starts the Support Agent."),
        ("portable", "pkg-windows-portable", "Portable", "Runs without installing."),
    ),
    "macos": (("portable", "pkg-macos-portable", "Portable", "Runs without installing."),),
    "linux": (("portable", "pkg-linux-portable", "Portable", "Runs without installing."),),
}

# Under the table of each product
DESKTOP_FOOTER = (
    "On Linux, the package repository at [pkg.neode.sk]"
    "(https://docs.neode.sk/getting-started/connect-a-client/#install-from-the-package-repository) "
    "keeps NeoDesk up to date with the system's own updates. "
    "Looking for the incoming-only Support Agent? It has its own "
    "[`support-v*` releases](https://github.com/{repo}/releases)."
)
SUPPORT_FOOTER = (
    "The Support Agent only accepts remote support and starts no sessions of its own. "
    "On first start it asks for your NeoDesk server and pairs with a QR code. "
    "The full client is in the [`desktop-v*` releases](https://github.com/{repo}/releases)."
)


# Above the downloads of every release. Remote support scams talk people into
# installing a remote desktop app, so the warning stands before the buttons.
SCAM_WARNING = (
    "> [!WARNING]\n"
    "> **Beware of support scams.** Only install NeoDesk if you asked for help yourself, "
    "from your own IT team or a company you already work with. "
    "If someone calls or messages you out of the blue and asks you to install it, "
    "for example claiming to be from Microsoft, your bank or the police, hang up "
    "and don't give them your ID or password."
)


def _url(repo: str, tag: str, name: str) -> str:
    return f"https://github.com/{repo}/releases/download/{tag}/{name}"


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


_SUPPORT_PLATFORMS = {None: "windows", "macOS-": "macos", "Linux-": "linux"}
_SUPPORT_ARCHES = {"x64": "x86_64", "arm64": "aarch64"}
_SUPPORT_KINDS = {"zip": "portable", "tar.gz": "portable", "msi": "msi", "exe": "exe"}


def classify_support(name: str) -> tuple[str, str, str] | None:
    """Return (platform, arch, kind) for Support Agent assets.

    Names are NeoDesk-Support-<version>-x64.msi on Windows and
    NeoDesk-Support-<version>-macOS-arm64.tar.gz or -Linux-x64.tar.gz
    elsewhere; a pre-release version may carry a suffix (0.1.0-rc.1).
    Older releases are named
    neodesk-support-generic-<platform>-<arch>.<ext>.
    """
    m = re.match(
        rf"^NeoDesk-Support-\d+\.\d+\.\d+(?:-(?!macOS-|Linux-)[0-9A-Za-z.]+)?-(macOS-|Linux-)?(x64|arm64)\.(zip|tar\.gz|msi|exe)$",
        name,
    )
    if m:
        return _SUPPORT_PLATFORMS[m.group(1)], _SUPPORT_ARCHES[m.group(2)], _SUPPORT_KINDS[m.group(3)]
    m = re.match(
        r"^neodesk-support-generic-(windows|linux|macos)-(x86_64|aarch64)\.(zip|tar\.gz|msi|exe)$",
        name,
    )
    if not m:
        return None
    platform, arch, ext = m.groups()
    return platform, arch, _SUPPORT_KINDS[ext]


def index_assets(asset_dir: Path, product: str) -> dict[tuple[str, str, str], Path]:
    classify = _classify_desktop if product == "desktop" else classify_support
    out: dict[tuple[str, str, str], Path] = {}
    for path in sorted(asset_dir.iterdir()):
        if not path.is_file():
            continue
        hit = classify(path.name)
        if hit:
            out[hit] = path
    return out


def _size(n: int) -> str:
    """A file size the way GitHub's asset list writes it."""
    if n <= 0:
        return ""
    if n < 1024 * 1024:
        return f"{max(1, round(n / 1024))} KB"
    return f"{n / (1024 * 1024):.1f} MB"


def _button(img, alt: str, size: int) -> str:
    """The download button with the file's size in it, put together from pieces.

    No whitespace between the images, so they meet as one button. make.py
    draws the pieces at whole pixel widths."""
    text = _size(size)
    if not text:
        return img("download", 32, alt)
    number, unit = text.split(" ")
    pieces = [("start", alt + ",")]
    pieces += [("dot" if c == "." else c, c) for c in number]
    pieces.append((unit.lower(), " " + unit))
    return "".join(img(f"btn-{name}", 32, text) for name, text in pieces)


def _extension(name: str) -> str:
    for ext in (".tar.gz", ".zip", ".exe", ".msi", ".deb", ".rpm", ".dmg"):
        if name.endswith(ext):
            return ext
    return Path(name).suffix


def render_table(
    *,
    product: str,
    assets: dict[tuple[str, str, str], Path],
    repo: str,
    tag: str,
    image_base: str,
) -> str:
    rows_of = DESKTOP_ROWS if product == "desktop" else SUPPORT_ROWS
    arches = [a for a in ARCHES if any(arch == a[0] for (_, arch, _) in assets)]
    if not arches:
        return "No packages were built for this release.\n"

    def img(icon: str, height: int, alt: str) -> str:
        # Only the height: the PNGs are drawn at twice the size, so the width
        # follows. GitHub rounds the corners of an image that has both.
        return f'<img src="{image_base}/{icon}.png" height="{height}" alt="{html.escape(alt, quote=True)}">'

    # No widths on the cells: GitHub counts the cell's padding into a width,
    # which left the package icons 2 pixels and broke the buttons onto two
    # lines. Without one a column is as wide as its images, and nowrap keeps
    # a button's pieces on one line on a narrow page too.

    lines = [
        "<table>",
        "<tr>",
        '<th align="left" colspan="3">Package</th>',
        *(f'<th nowrap>{label}<br><sub>{runs_on}</sub></th>' for _, label, runs_on in arches),
        "</tr>",
    ]
    for platform, system, os_icon in SYSTEMS:
        rows = [r for r in rows_of[platform] if any((platform, a, r[0]) in assets for a, _, _ in arches)]
        for i, (kind, icon, label, blurb) in enumerate(rows):
            names = [assets.get((platform, a, kind)) for a, _, _ in arches]
            ext = _extension(next(p for p in names if p).name)
            lines.append("<tr>")
            if i == 0:
                lines.append(
                    f'<td rowspan="{len(rows)}" align="center">'
                    f"{img(os_icon, 40, system)}<br><b>{system}</b></td>"
                )
            lines.append(f"<td>{img(icon, 28, '')}</td>")
            lines.append(f"<td><b>{label}</b> <code>{ext}</code><br><sub>{blurb}</sub></td>")
            for path, (_, arch_label, _) in zip(names, arches):
                if not path:
                    lines.append('<td align="center"><sub>not built</sub></td>')
                    continue
                button = _button(img, f"Download {system} {label} {arch_label}", path.stat().st_size)
                lines.append(f'<td align="center" nowrap><a href="{_url(repo, tag, path.name)}">{button}</a></td>')
            lines.append("</tr>")
    lines.append("</table>")
    footer = DESKTOP_FOOTER if product == "desktop" else SUPPORT_FOOTER
    return "\n".join(lines) + "\n\n" + footer.format(repo=repo) + "\n"


def _other_assets(product: str, asset_dir: Path, repo: str, tag: str) -> list[str]:
    other = []
    for path in sorted(asset_dir.iterdir()):
        if not path.is_file():
            continue
        name = path.name
        link = f"[{name}]({_url(repo, tag, name)})"
        if product == "desktop":
            if name.startswith("generator-templates") or name.endswith("generator-manifest.json"):
                other.append(f"- {link}: clean Generator templates")
            elif name == "neodesk-desktop-manifest.json":
                other.append(f"- {link}: desktop release manifest")
            elif name == "SHA256SUMS":
                other.append(f"- {link}: checksums of every file in this release")
        elif name in ("manifest.json", "manifest.sig", "SHA256SUMS"):
            other.append(f"- {link}")
    return other


def _split_intro(intro: str) -> tuple[str, str]:
    """The notes' first paragraphs, up to their first heading, and the rest."""
    m = re.search(r"^#{1,6} ", intro, flags=re.M)
    if not m or m.start() == 0:
        return intro.strip(), ""
    return intro[: m.start()].strip(), intro[m.start() :].strip()


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
    image_ref: str = "",
) -> str:
    assets = index_assets(asset_dir, product)
    image_base = f"https://raw.githubusercontent.com/{repo}/{image_ref or commit or tag}/res/release-icons"
    table = render_table(product=product, assets=assets, repo=repo, tag=tag, image_base=image_base)

    # GitHub shows the release's name above the notes, so they start without it
    lead, rest = _split_intro(intro_md)
    if lead:
        parts = [lead, ""]
    else:
        what = "NeoDesk Client" if product == "desktop" else "NeoDesk Support Agent"
        parts = [f"Official **{what}** build.", ""]
    parts += [SCAM_WARNING, "", "## Downloads", "", table]
    if rest:
        parts += [rest, ""]

    # Checksums, manifests and the build's commit stay folded under the notes
    other = _other_assets(product, asset_dir, repo, tag)
    if commit:
        other += [f"- Commit: `{commit}`", f"- Tag: `{tag}`"]
    if other:
        parts += ["<details>", "<summary><b>Checksums and other files</b></summary>", "", *other, "", "</details>", ""]

    if extra_md.strip():
        parts += [extra_md.strip(), ""]

    return "\n".join(parts).rstrip() + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--product", choices=("desktop", "support"), required=True)
    parser.add_argument("--asset-dir", type=Path, required=True)
    parser.add_argument("--repo", default="neodeskapp/neodesk-client")
    parser.add_argument("--tag", required=True)
    parser.add_argument("--release-name", required=True)
    parser.add_argument("--commit", default="")
    parser.add_argument(
        "--image-ref",
        default="",
        help="git ref whose res/release-icons the table shows (default: --commit, else --tag)",
    )
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
        image_ref=args.image_ref,
    )
    args.output.write_text(notes, encoding="utf-8")
    print(f"Wrote {args.output} ({len(notes)} bytes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
