#!/usr/bin/env python3
"""Check next_rc_tag.py, which names the release candidate of a main build."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from next_rc_tag import ReleasedError, next_rc_tag  # noqa: E402


class NextRcTag(unittest.TestCase):
    def test_first_candidate(self) -> None:
        self.assertEqual(next_rc_tag("1.6.0", ["desktop-v1.5.0-rc.8", "support-v0.0.10"]), "desktop-v1.6.0-rc.1")

    def test_one_above_the_highest_numerically(self) -> None:
        tags = ["desktop-v1.5.0-rc.4", "desktop-v1.5.0-rc.10\n", "desktop-v1.5.0-rc.9", "desktop-v1.5.0-rc.8"]
        self.assertEqual(next_rc_tag("1.5.0", tags), "desktop-v1.5.0-rc.11")

    def test_ignores_other_versions_and_suffixes(self) -> None:
        tags = ["desktop-v1.5.1-rc.30", "desktop-v1.5.0-rc.2", "desktop-v1.5.0-rc.3-hotfix", "desktop/1.5.0-rc.7"]
        self.assertEqual(next_rc_tag("1.5.0", tags), "desktop-v1.5.0-rc.3")

    def test_released_version_gets_no_candidate(self) -> None:
        with self.assertRaises(ReleasedError):
            next_rc_tag("1.5.0", ["desktop-v1.5.0-rc.8", "desktop-v1.5.0"])


if __name__ == "__main__":
    unittest.main()
