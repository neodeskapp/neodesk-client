#!/usr/bin/env python3
"""Render the PNG icons of the release download table.

The release notes on GitHub can only show images, so the system logos, the
package icons and the download button are drawn here once and committed.
Run it again after changing a colour or a glyph:

    python res/release-icons/make.py [--chrome <path to chrome>]

It draws every icon as an HTML page and takes a screenshot of it with
headless Chrome at twice the size the notes show it.

Glyphs in src/: the system and distribution logos are from Simple Icons
(CC0), the Windows mark is drawn below, the package glyphs are Material
Symbols Rounded (Apache 2.0, see flutter/assets/fonts). The logos stay the
trademarks of their owners and only say which system a package is for.
"""

from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
FONT = HERE.parent.parent / "flutter" / "assets" / "fonts" / "IBMPlexSans-SemiBold.ttf"

# Four panes, the Windows mark
WINDOWS = (
    '<svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">'
    '<rect x="1" y="1" width="10.6" height="10.6"/><rect x="12.4" y="1" width="10.6" height="10.6"/>'
    '<rect x="1" y="12.4" width="10.6" height="10.6"/><rect x="12.4" y="12.4" width="10.6" height="10.6"/>'
    "</svg>"
)

# name: (glyph, tile colour, glyph colour, size, glyph share of the tile)
# The system tiles are solid so they read on GitHub's light and dark page.
# The package tiles are a light tint of the glyph colour over the page.
ICONS = {
    "os-windows": ("windows", "#0078d4", "#ffffff", 40, 0.5),
    "os-linux": ("linux", "#fcc624", "#1b1e1f", 40, 0.62),
    "os-macos": ("apple", "#1b1e1f", "#ffffff", 40, 0.54),  # with a light edge for dark pages
    "pkg-windows-exe": ("install_desktop", "rgba(0,120,212,.2)", "#3d95e6", 28, 0.68),
    "pkg-windows-msi": ("deployed_code", "rgba(0,120,212,.2)", "#3d95e6", 28, 0.68),
    "pkg-windows-portable": ("folder_zip", "rgba(0,120,212,.2)", "#3d95e6", 28, 0.68),
    "pkg-debian": ("debian", "rgba(224,36,94,.18)", "#e0245e", 28, 0.68),
    "pkg-fedora": ("fedora", "rgba(81,162,218,.2)", "#4a9fd8", 28, 0.64),
    "pkg-opensuse": ("opensuse", "rgba(115,186,37,.2)", "#6aae22", 28, 0.7),
    "pkg-linux-portable": ("folder_zip", "rgba(212,160,10,.2)", "#cf9d0c", 28, 0.68),
    "pkg-macos-dmg": ("deployed_code", "rgba(139,148,158,.22)", "#8b949e", 28, 0.68),
    "pkg-macos-portable": ("folder_zip", "rgba(139,148,158,.22)", "#8b949e", 28, 0.68),
}

BUTTON = {"name": "download", "width": 116, "height": 32, "fill": "#1f6feb", "label": "Download"}

# The button with the file's size is put together from pieces in one link:
# btn-start, one btn-<digit> or btn-dot per character, then btn-mb or btn-kb.
# The pieces are whole pixels wide, so they meet without a seam.
SIZE_START = 122  # "Download" and a divider
SIZE_DIGIT = 9  # tabular figures, every digit equally wide
SIZE_DOT = 4
SIZE_UNIT = 34  # " MB" or " KB" and the rounded end


def glyph(name: str, colour: str) -> str:
    """The glyph's SVG with every shape filled in the colour."""
    svg = WINDOWS if name == "windows" else (HERE / "src" / f"{name}.svg").read_text(encoding="utf-8")
    svg = re.sub(r"<title>.*?</title>", "", svg)
    head, rest = svg.split(">", 1)
    head = re.sub(r'\s(width|height|fill|role)="[^"]*"', "", head)
    return head.replace("<svg", f'<svg fill="{colour}" width="100%" height="100%"', 1) + ">" + rest


def page(body: str, width: int, height: int) -> str:
    font = FONT.as_uri()
    return f"""<!doctype html><html><head><meta charset="utf-8"><style>
@font-face {{ font-family: Plex; src: url("{font}"); font-weight: 600; }}
html, body {{ margin: 0; background: transparent; width: {width}px; height: {height}px; overflow: hidden; }}
.tile {{ box-sizing: border-box; width: {width}px; height: {height}px; border-radius: 4px;
  display: flex; align-items: center; justify-content: center; }}
.tile svg {{ display: block; }}
.button {{ box-sizing: border-box; width: {width}px; height: {height}px; border-radius: 4px;
  display: flex; align-items: center; justify-content: center; gap: 6px;
  font: 600 14px/1 Plex, sans-serif; color: #fff; letter-spacing: .01em; }}
.button svg {{ width: 18px; height: 18px; display: block; }}
.piece {{ box-sizing: border-box; width: {width}px; height: {height}px; display: flex; align-items: center;
  font: 600 14px/1 Plex, sans-serif; color: #fff; font-variant-numeric: tabular-nums; white-space: pre; }}
.piece svg {{ width: 18px; height: 18px; display: block; }}
</style></head><body>{body}</body></html>"""


def tile(name: str, bg: str, fg: str, size: int, share: float) -> str:
    inner = round(size * share, 2)
    edge = "box-shadow:inset 0 0 0 1px rgba(255,255,255,.16);" if bg == "#1b1e1f" else ""
    return (
        f'<div class="tile" style="background:{bg};{edge}">'
        f'<div style="width:{inner}px;height:{inner}px">{glyph(name, fg)}</div></div>'
    )


def button() -> str:
    return (
        f'<div class="button" style="background:{BUTTON["fill"]}">'
        f'{glyph("download", "#ffffff")}<span>{BUTTON["label"]}</span></div>'
    )


def size_pieces() -> dict[str, tuple[int, str]]:
    """name: (width, HTML) of every piece of the button with the size."""
    fill = BUTTON["fill"]
    start = (
        f'<div class="piece" style="background:{fill};border-radius:4px 0 0 4px;padding-left:12px;gap:6px">'
        f'{glyph("download", "#ffffff")}<span>{BUTTON["label"]}</span>'
        f'<span style="margin-left:auto;margin-right:9px;width:1px;height:16px;background:rgba(255,255,255,.45)"></span>'
        "</div>"
    )
    pieces = {"btn-start": (SIZE_START, start)}
    for char, name, width in [(str(d), f"btn-{d}", SIZE_DIGIT) for d in range(10)] + [(".", "btn-dot", SIZE_DOT)]:
        pieces[name] = (
            width,
            f'<div class="piece" style="background:{fill};justify-content:center">{char}</div>',
        )
    for unit in ("MB", "KB"):
        pieces[f"btn-{unit.lower()}"] = (
            SIZE_UNIT,
            f'<div class="piece" style="background:{fill};border-radius:0 4px 4px 0;padding-left:4px">{unit}</div>',
        )
    return pieces


def find_chrome(given: str | None) -> str:
    candidates = [given] if given else []
    candidates += [
        os.environ.get("CHROME", ""),
        r"C:\Program Files\Google\Chrome\Application\chrome.exe",
        r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
        "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
    ]
    candidates += [shutil.which(n) or "" for n in ("google-chrome", "chromium", "chromium-browser", "chrome")]
    for c in candidates:
        if c and Path(c).is_file():
            return c
    sys.exit("No Chrome found, pass --chrome <path>")


def shoot(chrome: str, html: str, width: int, height: int, out: Path, tmp: Path) -> None:
    src = tmp / f"{out.stem}.html"
    src.write_text(html, encoding="utf-8")
    subprocess.run(
        [
            chrome, "--headless=new", "--disable-gpu", "--hide-scrollbars",
            "--default-background-color=00000000", "--force-device-scale-factor=2",
            f"--window-size={width},{height}", f"--screenshot={out}", src.as_uri(),
        ],
        check=True, capture_output=True,
    )
    print(f"{out.name} {width}x{height}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--chrome")
    args = parser.parse_args()
    chrome = find_chrome(args.chrome)
    with tempfile.TemporaryDirectory(prefix="nd-release-icons-") as value:
        tmp = Path(value)
        for name, (g, bg, fg, size, share) in ICONS.items():
            shoot(chrome, page(tile(g, bg, fg, size, share), size, size), size, size, HERE / f"{name}.png", tmp)
        w, h = BUTTON["width"], BUTTON["height"]
        shoot(chrome, page(button(), w, h), w, h, HERE / f"{BUTTON['name']}.png", tmp)
        for name, (width, body) in size_pieces().items():
            shoot(chrome, page(body, width, h), width, h, HERE / f"{name}.png", tmp)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
