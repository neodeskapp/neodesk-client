#!/usr/bin/env python3
"""Fails when a colour value is written into Dart code outside the theme file.

Every colour of the client comes from the tokens in
lib/common/theme/bd_theme.dart (BdColors): context.bd.<token> in widgets,
bdColors.<token> where no BuildContext is at hand. This keeps light, dark and
a server's accent working on every screen.

Flagged in lib/**/*.dart, except the theme file and generated code:
  Color(0x...), Color.fromARGB(...), Color.fromRGBO(...),
  Colors.<name> (Colors.transparent is allowed), CupertinoColors.<name>.

Run from the repository root or from flutter/:
  python3 flutter/tool/check_colours.py
Exit code 1 lists each finding as path:line: text.
"""

import os
import re
import sys

ALLOWED_FILES = {
    "lib/common/theme/bd_theme.dart",
}
GENERATED = re.compile(r"(generated_bridge.*|.*\.g|.*\.freezed|generated_plugin_registrant)\.dart$")
PATTERN = re.compile(
    r"\bColor\(\s*0x|\bColor\.from(ARGB|RGBO)\s*\(|\bCupertinoColors\.[a-zA-Z]"
    r"|\bColors\.(?!transparent\b)[a-zA-Z]"
)


def flutter_root():
    here = os.path.dirname(os.path.abspath(__file__))
    return os.path.dirname(here)


def strip_comment(line):
    # Drop // comments that are not inside a string (good enough for Dart code).
    in_str = None
    i = 0
    while i < len(line):
        ch = line[i]
        if in_str:
            if ch == "\\":
                i += 2
                continue
            if ch == in_str:
                in_str = None
        elif ch in ("'", '"'):
            in_str = ch
        elif line.startswith("//", i):
            return line[:i]
        i += 1
    return line


def scan(root):
    findings = []
    lib = os.path.join(root, "lib")
    for dirpath, _, files in os.walk(lib):
        for name in sorted(files):
            if not name.endswith(".dart"):
                continue
            path = os.path.join(dirpath, name)
            rel = os.path.relpath(path, root).replace(os.sep, "/")
            if rel in ALLOWED_FILES or GENERATED.search(name):
                continue
            with open(path, encoding="utf-8") as f:
                for no, line in enumerate(f, 1):
                    code = strip_comment(line)
                    if PATTERN.search(code):
                        findings.append(f"{rel}:{no}: {line.strip()}")
    return findings


def main():
    findings = scan(flutter_root())
    if findings:
        print("Colour values outside lib/common/theme/bd_theme.dart.")
        print("Use a BdColors token instead (context.bd.<token> or bdColors.<token>):")
        for f in findings:
            print("  " + f)
        print(f"{len(findings)} finding(s).")
        return 1
    print("No colour values outside the theme file.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
