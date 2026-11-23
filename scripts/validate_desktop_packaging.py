#!/usr/bin/env python3
"""Check the source-level launcher and installer contract for desktop builds."""

from pathlib import Path
import re
import sys


ROOT = Path(__file__).resolve().parents[1]


def read(relative: str) -> str:
    return (ROOT / relative).read_text(encoding="utf-8")


def require(relative: str, text: str, needle: str) -> None:
    if needle not in text:
        failures.append(f"{relative}: missing {needle!r}")


def exists(relative: str) -> bool:
    return (ROOT / relative).exists()


failures: list[str] = []

linux_cmake = read("flutter/linux/CMakeLists.txt")
require("flutter/linux/CMakeLists.txt", linux_cmake, 'set(BINARY_NAME "neodesk")')

# The Linux packages install next to a stock RustDesk: their own package
# name, files, service and icons, and no package relation to rustdesk.
LINUX_PACKAGING = (
    "build.py",
    "res/DEBIAN/postinst",
    "res/DEBIAN/postrm",
    "res/DEBIAN/preinst",
    "res/DEBIAN/prerm",
    "res/rpm.spec",
    "res/rpm-suse.spec",
    "res/rpm-flutter.spec",
    "res/rpm-flutter-suse.spec",
    "res/PKGBUILD",
    "res/pacman_install",
    "res/neodesk.service",
    "res/neodesk.desktop",
    "res/neodesk-link.desktop",
    "appimage/AppImageBuilder-x86_64.yml",
    "appimage/AppImageBuilder-aarch64.yml",
    "flatpak/rustdesk.json",
    "flutter/linux/my_application.cc",
)
STOCK_RUSTDESK = (
    (r"(Conflicts|Replaces|Provides|Obsoletes|Breaks):\s*rustdesk\b", "a package relation to rustdesk"),
    (r"^\s*(conflicts|replaces|provides)=.*\brustdesk\b", "a package relation to rustdesk"),
    (r"\brustdesk\.service\b", "the rustdesk.service unit"),
    (r"\b(systemctl|service)\b.*\srustdesk(\s|;|$)", "a command on the rustdesk service"),
    (r"/usr/share/rustdesk\b|/app/share/rustdesk\b", "stock RustDesk's install folder"),
    (r"(?<!tmpdeb)/usr/bin/rustdesk\b|/app/bin/rustdesk\b", "stock RustDesk's command"),
    (r"\.config/rustdesk\b", "stock RustDesk's settings folder"),
    (r"applications/rustdesk(-link)?\.desktop", "stock RustDesk's desktop file"),
    (r"apps/rustdesk\.(png|svg)|Icon=rustdesk|\"rustdesk\", icons|rename-icon\": \"rustdesk", "stock RustDesk's icon"),
)
for relative in LINUX_PACKAGING:
    if not exists(relative):
        failures.append(f"{relative}: missing")
        continue
    for number, line in enumerate(read(relative).splitlines(), 1):
        for pattern, what in STOCK_RUSTDESK:
            if re.search(pattern, line):
                failures.append(f"{relative}:{number}: {what}: {line.strip()}")
for relative in ("res/rustdesk.service", "res/rustdesk-link.desktop", "res/rustdesk.desktop"):
    if exists(relative):
        failures.append(f"{relative}: stock RustDesk's name; NeoDesk ships its own")

service = read("res/neodesk.service") if exists("res/neodesk.service") else ""
require("res/neodesk.service", service, "ExecStart=/usr/bin/neodesk --service")
require("res/neodesk.service", service, 'ExecStop=/usr/bin/pkill -f "neodesk --"')

postinst = read("res/DEBIAN/postinst")
require("res/DEBIAN/postinst", postinst, "ln -f -s /usr/share/neodesk/neodesk /usr/bin/neodesk")
require("res/DEBIAN/postinst", postinst, "/usr/lib/systemd/system/neodesk.service")
require("res/DEBIAN/postinst", postinst, "systemctl enable neodesk")
require("res/DEBIAN/prerm", read("res/DEBIAN/prerm"), "systemctl stop neodesk")
require("res/DEBIAN/postrm", read("res/DEBIAN/postrm"), "/root/.config/neodeskclient")

desktop = read("res/neodesk.desktop")
require("res/neodesk.desktop", desktop, "Exec=neodesk %u")
require("res/neodesk.desktop", desktop, "StartupWMClass=neodesk")
require("res/neodesk.desktop", desktop, "Icon=neodesk")

link = read("res/neodesk-link.desktop")
require("res/neodesk-link.desktop", link, "TryExec=neodesk")
require("res/neodesk-link.desktop", link, "Exec=neodesk %u")
require("res/neodesk-link.desktop", link, "Icon=neodesk")
require(
    "flutter/linux/my_application.cc",
    read("flutter/linux/my_application.cc"),
    'gtk_icon_theme_load_icon(theme, "neodesk"',
)

build = read("build.py")
for needle in (
    "cp ../res/neodesk.desktop tmpdeb/usr/share/applications/neodesk.desktop",
    "cp ../res/neodesk-link.desktop tmpdeb/usr/share/applications/neodesk-link.desktop",
    "cp ../res/neodesk.service tmpdeb/usr/share/neodesk/files/systemd/",
    "tmpdeb/usr/share/icons/hicolor/256x256/apps/neodesk.png",
    "tmpdeb/usr/share/icons/hicolor/scalable/apps/neodesk.svg",
    "dpkg-deb -b tmpdeb neodesk.deb;",
    "Package: neodesk\n",
):
    require("build.py", build, needle)

for relative in ("res/rpm-flutter.spec", "res/rpm-flutter-suse.spec"):
    spec = read(relative)
    require(relative, spec, "Name:       neodesk")
    require(relative, spec, "ln -sf /usr/share/neodesk/neodesk /usr/bin/neodesk")
    require(relative, spec, "/etc/systemd/system/neodesk.service")
    require(relative, spec, "systemctl enable neodesk")

for relative in ("appimage/AppImageBuilder-x86_64.yml", "appimage/AppImageBuilder-aarch64.yml"):
    appimage = read(relative)
    require(relative, appimage, 'bsdtar -xvf "$DEB"')
    require(relative, appimage, "exec: usr/share/neodesk/neodesk")
    require(relative, appimage, "name: NeoDesk")

flatpak = read("flatpak/rustdesk.json")
require("flatpak/rustdesk.json", flatpak, '"command": "neodesk"')
require("flatpak/rustdesk.json", flatpak, "/app/share/neodesk/neodesk")
require("flatpak/rustdesk.json", flatpak, "/app/share/metainfo/sk.neode.neodesk.metainfo.xml")

pkgbuild = read("res/PKGBUILD")
require("res/PKGBUILD", pkgbuild, 'install -Dm 755 "${HBB}/target/release/rustdesk" "${pkgdir}/usr/share/neodesk/neodesk"')

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
