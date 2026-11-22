#!/usr/bin/env python3
"""Check the source-level launcher and installer contract for desktop builds."""

from pathlib import Path
import sys


ROOT = Path(__file__).resolve().parents[1]


def read(relative: str) -> str:
    return (ROOT / relative).read_text(encoding="utf-8")


def require(relative: str, text: str, needle: str) -> None:
    if needle not in text:
        failures.append(f"{relative}: missing {needle!r}")


failures: list[str] = []

linux_cmake = read("flutter/linux/CMakeLists.txt")
require("flutter/linux/CMakeLists.txt", linux_cmake, 'set(BINARY_NAME "neodesk")')

service = read("res/rustdesk.service")
require("res/rustdesk.service", service, "ExecStart=/usr/bin/neodesk --service")
require("res/rustdesk.service", service, 'ExecStop=/usr/bin/pkill -f "neodesk --"')

postinst = read("res/DEBIAN/postinst")
require("res/DEBIAN/postinst", postinst, "ln -f -s /usr/share/rustdesk/neodesk /usr/bin/neodesk")
require("res/DEBIAN/postinst", postinst, "ln -f -s /usr/share/rustdesk/neodesk /usr/bin/rustdesk")

desktop = read("res/neodesk.desktop")
require("res/neodesk.desktop", desktop, "Exec=neodesk %u")
require("res/neodesk.desktop", desktop, "StartupWMClass=neodesk")

for relative in ("res/neodesk-link.desktop", "res/rustdesk-link.desktop"):
    require(relative, read(relative), "TryExec=neodesk")
    require(relative, read(relative), "Exec=neodesk %u")

build = read("build.py")
for needle in (
    "cp ../res/neodesk.desktop tmpdeb/usr/share/applications/neodesk.desktop",
    "cp ../res/neodesk-link.desktop tmpdeb/usr/share/applications/neodesk-link.desktop",
    "dpkg-deb -b tmpdeb neodesk.deb;",
):
    require("build.py", build, needle)

for relative in ("res/rpm-flutter.spec", "res/rpm-flutter-suse.spec"):
    spec = read(relative)
    require(relative, spec, "Name:       neodesk")
    require(relative, spec, "ln -sf /usr/share/rustdesk/neodesk /usr/bin/neodesk")

for relative in ("appimage/AppImageBuilder-x86_64.yml", "appimage/AppImageBuilder-aarch64.yml"):
    appimage = read(relative)
    require(relative, appimage, 'bsdtar -xvf "$DEB"')
    require(relative, appimage, "exec: usr/share/rustdesk/neodesk")
    require(relative, appimage, "name: NeoDesk")

flatpak = read("flatpak/rustdesk.json")
require("flatpak/rustdesk.json", flatpak, '"command": "neodesk"')
require("flatpak/rustdesk.json", flatpak, "/app/share/rustdesk/neodesk")
require("flatpak/rustdesk.json", flatpak, "/app/share/metainfo/sk.neode.neodesk.metainfo.xml")

pkgbuild = read("res/PKGBUILD")
require("res/PKGBUILD", pkgbuild, 'install -Dm 755 "${HBB}/target/release/rustdesk" "${pkgdir}/usr/share/rustdesk/neodesk"')

preprocess = read("res/msi/preprocess.py")
require("res/msi/preprocess.py", preprocess, 'default="NeoDesk Client"')
require("res/msi/preprocess.py", preprocess, '"neodesk.exe"')
require("res/msi/preprocess.py", preprocess, 'UriScheme="neodesk"')
regs = read("res/msi/Package/Components/Regs.wxs")
require("res/msi/Package/Components/Regs.wxs", regs, 'Key="$(var.UriScheme)"')
require("res/msi/Package/Components/Regs.wxs", regs, 'Key="$(var.LegacyUriScheme)"')
require("res/msi/Package/Components/RustDesk.wxs", read("res/msi/Package/Components/RustDesk.wxs"), 'Name="$(var.Executable)"')

mac_xcconfig = read("flutter/macos/Runner/Configs/AppInfo.xcconfig")
require("flutter/macos/Runner/Configs/AppInfo.xcconfig", mac_xcconfig, "PRODUCT_NAME = NeoDesk Client")
require(
    "flutter/macos/Runner/Configs/AppInfo.xcconfig",
    mac_xcconfig,
    "PRODUCT_BUNDLE_IDENTIFIER = sk.neode.neodesk",
)
mac_plist = read("flutter/macos/Runner/Info.plist")
require("flutter/macos/Runner/Info.plist", mac_plist, "<string>neodesk</string>")
require("flutter/macos/Runner/Info.plist", mac_plist, "<string>rustdesk</string>")
macos_runtime = read("src/platform/macos.rs")
require("src/platform/macos.rs", macos_runtime, 'sk.neode.{}_service.plist')
require("src/platform/macos.rs", macos_runtime, 'sk.neode.{}_server.plist')

release = read(".github/workflows/neodesk-desktop-release.yml")
require(".github/workflows/neodesk-desktop-release.yml", release, "pattern: neodesk-unsigned-macos-*")
require(".github/workflows/neodesk-desktop-release.yml", release, "scripts/collect_desktop_dist.sh collect")
collect = read("scripts/collect_desktop_dist.sh")
require("scripts/collect_desktop_dist.sh", collect, 'neodesk-unsigned-macos-${arch}')

if failures:
    print("\n".join(failures), file=sys.stderr)
    sys.exit(1)

print("Desktop packaging contract: OK")
