#!/usr/bin/env python3
"""Tests for check_drm_package.py and the drm parts of build.py.

    python3 scripts/test_check_drm_package.py

Needs git. Runs on the build container's Python 3.6 too.
"""

import contextlib
import hashlib
import importlib.util
import io
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)

import check_drm_package as cdp  # noqa: E402


def load_build_py():
    spec = importlib.util.spec_from_file_location('neodesk_build', os.path.join(ROOT, 'build.py'))
    mod = importlib.util.module_from_spec(spec)
    argv = sys.argv
    sys.argv = ['build.py']
    try:
        spec.loader.exec_module(mod)
    finally:
        sys.argv = argv
    return mod


def write(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'wb') as f:
        f.write(data)


SO = b'\x7fELF fake libdrmtap'


def good_tree(root, binary=b'xx/usr/lib/neodesk/libdrmtap.so.0\0enable-drm-display-wake\0'):
    lib = os.path.join(root, 'usr', 'lib', 'neodesk')
    write(os.path.join(lib, 'libdrmtap.so.0.5.12'), SO)
    os.symlink('libdrmtap.so.0.5.12', os.path.join(lib, 'libdrmtap.so.0'))
    write(os.path.join(lib, 'LICENSE.libdrmtap'), b'MIT License\n\nCopyright (c) 2026 libdrmtap\n')
    write(os.path.join(root, 'usr', 'share', 'neodesk', 'lib', 'librustdesk.so'), binary)


class PackageContents(unittest.TestCase):
    def setUp(self):
        self.root = tempfile.mkdtemp()

    def tearDown(self):
        shutil.rmtree(self.root, ignore_errors=True)

    def test_a_complete_package_passes(self):
        good_tree(self.root)
        self.assertEqual(cdp.check_tree(self.root, hashlib.sha256(SO).hexdigest()), [])

    def test_a_package_without_libdrmtap_fails(self):
        write(os.path.join(self.root, 'usr', 'share', 'neodesk', 'lib', 'librustdesk.so'),
              b'/usr/lib/neodesk/libdrmtap.so.0 enable-drm-display-wake')
        problems = cdp.check_tree(self.root)
        self.assertTrue(any('symlink' in p for p in problems), problems)
        self.assertTrue(any('found 0' in p for p in problems), problems)
        self.assertTrue(any('LICENSE' in p for p in problems), problems)

    def test_a_stock_binary_fails(self):
        good_tree(self.root, binary=b'a stock build of librustdesk.so')
        problems = cdp.check_tree(self.root)
        self.assertTrue(any('not a drm build' in p for p in problems), problems)
        self.assertTrue(any('without drm-wake' in p for p in problems), problems)

    def test_a_binary_from_upstreams_layout_fails(self):
        # Stock RustDesk's path: a NeoDesk package would never load the library it carries.
        good_tree(self.root, binary=b'/usr/lib/rustdesk/libdrmtap.so.0 enable-drm-display-wake')
        problems = cdp.check_tree(self.root)
        self.assertTrue(any('not a drm build' in p for p in problems), problems)

    def test_a_library_other_than_the_built_one_fails(self):
        good_tree(self.root)
        problems = cdp.check_tree(self.root, hashlib.sha256(b'another build').hexdigest())
        self.assertTrue(any('SHA-256' in p for p in problems), problems)

    def test_two_libraries_fail(self):
        good_tree(self.root)
        write(os.path.join(self.root, 'usr', 'lib', 'neodesk', 'libdrmtap.so.0.5.4'), SO)
        problems = cdp.check_tree(self.root)
        self.assertTrue(any('found 2' in p for p in problems), problems)

    def test_rpm_glibc_floor(self):
        self.assertEqual(cdp.rpm_glibc_problems('libc.so.6(GLIBC_2.27)(64bit)\nlibgtk-3.so.0()(64bit)\n'), [])
        self.assertTrue(cdp.rpm_glibc_problems('libc.so.6(GLIBC_2.34)(64bit)\n'))
        self.assertTrue(cdp.rpm_glibc_problems('libc.so.6(GLIBC_2.28)(64bit)\n'))


class Features(unittest.TestCase):
    """Which Linux builds compile DRM capture in: every Flutter package path that carries libdrmtap."""

    @classmethod
    def setUpClass(cls):
        cls.b = load_build_py()

    def features(self, branch, *flags, windows=False, osx=False):
        b = self.b
        saved = (b.linux_packaging_branch, b.windows, b.osx)
        b.linux_packaging_branch = lambda: branch
        b.windows, b.osx = windows, osx
        try:
            args = b.make_parser().parse_args(list(flags))
            with contextlib.redirect_stdout(io.StringIO()):
                return b.get_features(args)
        finally:
            b.linux_packaging_branch, b.windows, b.osx = saved

    def test_deb_and_pacman_flutter_builds_carry_drm(self):
        for branch in ('deb', 'pacman'):
            feats = self.features(branch, '--flutter', '--hwcodec', '--unix-file-copy-paste')
            self.assertIn('drm', feats, branch)
            self.assertIn('drm-wake', feats, branch)

    def test_paths_that_cannot_carry_libdrmtap_do_not(self):
        # build.py's yum and zypper branches build the Sciter rpms; CI's Flutter rpms reuse the
        # deb build's library and are checked with check_drm_package.py.
        for branch in ('yum', 'zypper'):
            self.assertNotIn('drm', self.features(branch, '--flutter'), branch)
        self.assertNotIn('drm', self.features('deb'))  # Sciter
        self.assertNotIn('drm', self.features('deb', '--flutter', '--no-drm'))
        # The flag is not offered on Windows and macOS (see make_parser); get_features ignores it.
        self.assertNotIn('drm', self.features('deb', '--flutter', windows=True))
        self.assertNotIn('drm', self.features('deb', '--flutter', osx=True))


def git(repo, *args):
    subprocess.check_call(['git', '-C', repo] + list(args), stdout=subprocess.DEVNULL)


class SourcePin(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.b = load_build_py()

    def setUp(self):
        self.repo = tempfile.mkdtemp()
        git(self.repo, 'init', '-q')
        git(self.repo, 'config', 'user.email', 'test@example.invalid')
        git(self.repo, 'config', 'user.name', 'test')
        git(self.repo, 'config', 'core.autocrlf', 'false')
        write(os.path.join(self.repo, 'meson.build'), b"project('libdrmtap', 'c')\n")
        write(os.path.join(self.repo, 'src', 'drmtap.c'), b'int x;\n')
        git(self.repo, 'add', '-A')
        git(self.repo, 'commit', '-qm', 'one')

    def tearDown(self):
        shutil.rmtree(self.repo, ignore_errors=True)

    def test_the_digest_follows_the_committed_tree_only(self):
        d = self.b.libdrmtap_source_digest(self.repo)
        self.assertEqual(d, self.b.libdrmtap_source_digest(self.repo), 'stable')
        # A build directory and an edited, uncommitted file do not change it.
        write(os.path.join(self.repo, 'build-pkg', 'libdrmtap.so.0.5.12'), b'built')
        write(os.path.join(self.repo, 'src', 'drmtap.c'), b'int edited;\n')
        self.assertEqual(d, self.b.libdrmtap_source_digest(self.repo))
        git(self.repo, 'checkout', '-q', '--', 'src/drmtap.c')
        # A committed change does.
        write(os.path.join(self.repo, 'src', 'drmtap.c'), b'int changed;\n')
        git(self.repo, 'commit', '-qam', 'two')
        self.assertNotEqual(d, self.b.libdrmtap_source_digest(self.repo))

    def test_a_tree_that_is_not_the_reviewed_one_fails_the_build(self):
        b = self.b
        saved = (b.LIBDRMTAP_SHA, b.LIBDRMTAP_SOURCE_SHA256_PINNED)
        try:
            b.LIBDRMTAP_SHA = b.LIBDRMTAP_SHA_PINNED
            b.LIBDRMTAP_SOURCE_SHA256_PINNED = b.libdrmtap_source_digest(self.repo)
            with contextlib.redirect_stdout(io.StringIO()):
                b._verify_libdrmtap_source(self.repo)  # passes
            b.LIBDRMTAP_SOURCE_SHA256_PINNED = '0' * 64
            with self.assertRaises(Exception):
                b._verify_libdrmtap_source(self.repo)
            if os.name != 'nt':  # rmtree cannot remove git's read-only objects on Windows
                self.assertFalse(os.path.exists(self.repo), 'the mismatching checkout is removed')
        finally:
            b.LIBDRMTAP_SHA, b.LIBDRMTAP_SOURCE_SHA256_PINNED = saved

    def test_the_pin_is_a_full_commit_and_a_digest(self):
        b = self.b
        self.assertRegex(b.LIBDRMTAP_SHA_PINNED, r'^[0-9a-f]{40}$')
        self.assertRegex(b.LIBDRMTAP_SOURCE_SHA256_PINNED, r'^[0-9a-f]{64}$')

    def test_the_licence_must_ship(self):
        b = self.b
        saved = b.libdrmtap_license_path
        dest = tempfile.mkdtemp()
        try:
            b.libdrmtap_license_path = lambda: os.path.join(self.repo, 'LICENSE')
            with self.assertRaises(Exception):
                b.stage_libdrmtap_license(dest)
            write(os.path.join(self.repo, 'LICENSE'), b'MIT License\n')
            b.stage_libdrmtap_license(dest)
            self.assertTrue(os.path.isfile(os.path.join(dest, 'LICENSE.libdrmtap')))
        finally:
            b.libdrmtap_license_path = saved
            shutil.rmtree(dest, ignore_errors=True)


if __name__ == '__main__':
    unittest.main(verbosity=2)
