#!/usr/bin/env python3
"""Check that a NeoDesk Linux package carries DRM capture for the Wayland login screen.

    check_drm_package.py PACKAGE.deb|PACKAGE.rpm [--so-sha256 HEX] [--no-glibc-check]

A package passes when it holds, under /usr/lib/neodesk:
  - libdrmtap.so.0, a symlink to the one real libdrmtap.so.0.X.Y next to it;
  - LICENSE.libdrmtap, the library's MIT licence;
and its librustdesk.so is a drm build with the display wake: it names the absolute dlopen path
/usr/lib/neodesk/libdrmtap.so.0 and the enable-drm-display-wake option.

--so-sha256 also requires the packaged library to be byte for byte the one the build made.
For an rpm, the package must not require a glibc newer than 2.27 (the build container's), which
only libdrmtap's own requirements could add: the specs exclude /usr/lib/neodesk from them.

Runs in the ubuntu 18.04 build container, so Python 3.6 and no third-party modules.
"""

import hashlib
import os
import re
import shutil
import subprocess
import sys
import tempfile

LIB_DIR = os.path.join('usr', 'lib', 'neodesk')
BINARY = os.path.join('usr', 'share', 'neodesk', 'lib', 'librustdesk.so')
DLOPEN_MARKER = b'/usr/lib/neodesk/libdrmtap.so.0'
WAKE_MARKER = b'enable-drm-display-wake'
REAL_SO = re.compile(r'^libdrmtap\.so\.0\.\d+\.\d+$')
NEW_GLIBC = re.compile(r'GLIBC_2\.(2[89]|[3-9][0-9])')


def _file_contains(path, needle):
    tail = b''
    with open(path, 'rb') as f:
        while True:
            chunk = f.read(1 << 20)
            if not chunk:
                return False
            if needle in tail + chunk:
                return True
            tail = chunk[-len(needle):]


def sha256_of(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for chunk in iter(lambda: f.read(1 << 20), b''):
            h.update(chunk)
    return h.hexdigest()


def check_tree(root, so_sha256=None):
    """Problems with the unpacked package at `root`, as a list of strings (empty when it passes)."""
    problems = []
    lib_dir = os.path.join(root, LIB_DIR)
    link = os.path.join(lib_dir, 'libdrmtap.so.0')
    if not os.path.islink(link):
        problems.append('no /usr/lib/neodesk/libdrmtap.so.0 symlink')
    real = []
    if os.path.isdir(lib_dir):
        real = sorted(n for n in os.listdir(lib_dir)
                      if REAL_SO.match(n) and os.path.isfile(os.path.join(lib_dir, n))
                      and not os.path.islink(os.path.join(lib_dir, n)))
    if len(real) != 1:
        problems.append('expected one real libdrmtap.so.0.X.Y in /usr/lib/neodesk, found %d: %s'
                        % (len(real), real))
    elif os.path.islink(link) and os.readlink(link) != real[0]:
        problems.append('libdrmtap.so.0 points at %r, not at %r' % (os.readlink(link), real[0]))
    if len(real) == 1 and so_sha256:
        got = sha256_of(os.path.join(lib_dir, real[0]))
        if got != so_sha256.lower():
            problems.append('the packaged %s has SHA-256 %s, the build made %s'
                            % (real[0], got, so_sha256.lower()))
    licence = os.path.join(lib_dir, 'LICENSE.libdrmtap')
    if not os.path.isfile(licence):
        problems.append('no /usr/lib/neodesk/LICENSE.libdrmtap')
    elif not _file_contains(licence, b'MIT License'):
        problems.append('LICENSE.libdrmtap is not the MIT licence')
    binary = os.path.join(root, BINARY)
    if not os.path.isfile(binary):
        problems.append('no /usr/share/neodesk/lib/librustdesk.so')
    else:
        if not _file_contains(binary, DLOPEN_MARKER):
            problems.append('librustdesk.so is not a drm build (no %s)' % DLOPEN_MARKER.decode())
        if not _file_contains(binary, WAKE_MARKER):
            problems.append('librustdesk.so is built without drm-wake (no %s)' % WAKE_MARKER.decode())
    return problems


def rpm_glibc_problems(requires):
    """Problems with an rpm's `rpm -qpR` output."""
    found = sorted(set(m.group(0) for m in NEW_GLIBC.finditer(requires)))
    if found:
        return ['the rpm requires %s, newer than its build container; libdrmtap\'s requirements '
                'leaked in' % ', '.join(found)]
    return []


def _run(cmd, **kwargs):
    return subprocess.check_output(cmd, **kwargs)


def unpack(package, dest):
    if package.endswith('.deb'):
        _run(['dpkg-deb', '-x', package, dest])
    elif package.endswith('.rpm'):
        cpio = subprocess.Popen(['cpio', '-idm', '--quiet'], cwd=dest, stdin=subprocess.PIPE)
        cpio.stdin.write(_run(['rpm2cpio', os.path.abspath(package)]))
        cpio.stdin.close()
        if cpio.wait() != 0:
            raise Exception('cpio failed on %s' % package)
    else:
        raise Exception('not a .deb or .rpm: %s' % package)


def main(argv):
    args = list(argv)
    so_sha256 = None
    glibc_check = True
    if '--so-sha256' in args:
        i = args.index('--so-sha256')
        so_sha256 = args[i + 1]
        del args[i:i + 2]
    if '--no-glibc-check' in args:
        args.remove('--no-glibc-check')
        glibc_check = False
    if len(args) != 1:
        print(__doc__)
        return 2
    package = args[0]
    dest = tempfile.mkdtemp(prefix='drm-package-')
    try:
        unpack(package, dest)
        problems = check_tree(dest, so_sha256)
        if package.endswith('.rpm') and glibc_check:
            problems += rpm_glibc_problems(
                _run(['rpm', '-qpR', package]).decode('utf-8', 'replace'))
    finally:
        shutil.rmtree(dest, ignore_errors=True)
    for p in problems:
        print('::error::%s: %s' % (os.path.basename(package), p))
    if not problems:
        print('%s: carries DRM capture for the login screen' % os.path.basename(package))
    return 1 if problems else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
