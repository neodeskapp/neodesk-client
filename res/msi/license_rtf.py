#!/usr/bin/env python3
"""Writes Package/License.rtf, the licence page of the MSI, from the
repository's LICENCE (AGPL-3.0).

  python license_rtf.py           writes Package/License.rtf
  python license_rtf.py --check   exits 1 when Package/License.rtf is not
                                  what LICENCE gives
"""

import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
LICENCE = HERE.parent.parent / "LICENCE"
RTF = HERE / "Package" / "License.rtf"

HEADER = (
    "NeoDesk is free software, licensed under the GNU Affero General Public "
    "License, version 3, below. It is based on RustDesk "
    "(https://github.com/rustdesk/rustdesk). The source code of this client is "
    "at https://github.com/neodeskapp/neodesk-client."
)


def escape(text):
    out = []
    for c in text:
        if c in "\\{}":
            out.append("\\" + c)
        elif ord(c) > 127:
            code = ord(c)
            out.append(f"\\u{code - 65536 if code > 32767 else code}?")
        else:
            out.append(c)
    return "".join(out)


def paragraphs(text):
    """Blank lines end a paragraph. Lines inside one are joined, except in
    the centred title and the indented notice sample, which keep their
    line breaks."""
    result = []
    for block in text.replace("\r\n", "\n").split("\n\n"):
        lines = [line for line in block.split("\n") if line.strip()]
        if not lines:
            continue
        if all(line.startswith("    ") for line in lines):
            result.append(("\\line ").join(escape(line.strip()) for line in lines))
        else:
            result.append(escape(" ".join(line.strip() for line in lines)))
    return result


def licence_rtf(licence_text):
    body = [escape(HEADER)] + paragraphs(licence_text)
    return (
        "{\\rtf1\\ansi\\ansicpg1252\\deff0\\uc1"
        "{\\fonttbl{\\f0\\fswiss\\fcharset0 Segoe UI;}}"
        "\\viewkind4\\pard\\sa120\\f0\\fs16\n"
        + "".join(f"{p}\\par\n" for p in body)
        + "}\n"
    )


def main():
    rtf = licence_rtf(LICENCE.read_text(encoding="utf-8"))
    if sys.argv[1:] == ["--check"]:
        if RTF.read_text(encoding="utf-8").replace("\r\n", "\n") != rtf:
            print(f"{RTF} is not the text of {LICENCE}; run python res/msi/license_rtf.py")
            return 1
        print("MSI licence page: OK")
        return 0
    RTF.write_text(rtf, encoding="utf-8", newline="\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
