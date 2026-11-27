#!/usr/bin/env python3
"""Print the tag of the next release candidate of a client version.

Reads the existing tags, one per line, from stdin and prints
desktop-v<version>-rc.<n> with n one above the highest rc of that version
(rc.1 when there is none). Fails when desktop-v<version> itself is already
tagged, because a released version gets no more candidates; bump the
version in Cargo.toml then.

    git tag -l 'desktop-v*' | python3 scripts/next_rc_tag.py 1.5.0
"""

from __future__ import annotations

import re
import sys
from collections.abc import Iterable


class ReleasedError(Exception):
    pass


def next_rc_tag(version: str, tags: Iterable[str]) -> str:
    stable = f"desktop-v{version}"
    rc = re.compile(re.escape(stable) + r"-rc\.(\d+)")
    highest = 0
    for tag in tags:
        tag = tag.strip()
        if tag == stable:
            raise ReleasedError(f"{stable} is already released; bump the version in Cargo.toml")
        m = rc.fullmatch(tag)
        if m:
            highest = max(highest, int(m.group(1)))
    return f"{stable}-rc.{highest + 1}"


def main() -> int:
    if len(sys.argv) != 2 or not re.fullmatch(r"\d+\.\d+\.\d+", sys.argv[1]):
        print("usage: next_rc_tag.py <major>.<minor>.<patch> < tags", file=sys.stderr)
        return 2
    try:
        print(next_rc_tag(sys.argv[1], sys.stdin))
    except ReleasedError as e:
        print(f"::error::{e}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
