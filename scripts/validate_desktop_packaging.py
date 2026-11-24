#!/usr/bin/env python3
"""Check the source-level launcher and installer contract for desktop builds."""

from pathlib import Path
import os
import re
import subprocess
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

# Package scripts also run where there is no systemd (containers, chroots) or
# no desktop-file-utils (minimal installs). A command that fails there fails
# the install: dnf5 calls the transaction failed, zypper exits 107. So every
# systemctl and update-desktop-database call is silenced and allowed to fail.
PACKAGE_SCRIPTS = (
    "res/DEBIAN/postinst",
    "res/DEBIAN/postrm",
    "res/DEBIAN/preinst",
    "res/DEBIAN/prerm",
    "res/rpm.spec",
    "res/rpm-suse.spec",
    "res/rpm-flutter.spec",
    "res/rpm-flutter-suse.spec",
    "res/pacman_install",
)
GUARDED = re.compile(r">\s*/dev/null\s+2>&1\s*\|\|\s*(:|true)$")
for relative in PACKAGE_SCRIPTS:
    for number, line in enumerate(read(relative).splitlines(), 1):
        code = line.split("#", 1)[0].strip()
        if re.search(r"(^|[\s;&|(])(systemctl|update-desktop-database)(\s|$)", code) and not GUARDED.search(code):
            failures.append(f"{relative}:{number}: add >/dev/null 2>&1 || : to {code!r}")

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
require("res/neodesk-link.desktop", link, "MimeType=x-scheme-handler/neodesk;")
# rustdesk:// is stock RustDesk's. A package file claiming it would take it
# from a stock RustDesk installed before or after, so no Linux package does.
for relative in LINUX_PACKAGING:
    if exists(relative) and "x-scheme-handler/rustdesk" in read(relative):
        failures.append(f"{relative}: claims rustdesk://, which is stock RustDesk's")
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
# The MSI takes rustdesk:// only by the rule in link_schemes.rs, through the
# client, and never as a component it would remove whatever it points at.
if "$(var.LegacyUriScheme)" in regs:
    failures.append("res/msi/Package/Components/Regs.wxs: registers rustdesk:// unconditionally")
msi_components = read("res/msi/Package/Components/RustDesk.wxs")
for needle in ('ExeCommand="--claim-rustdesk-scheme"', 'ExeCommand="--release-rustdesk-scheme"',
               '<Custom Action="ClaimRustDeskScheme"', '<Custom Action="ReleaseRustDeskScheme"'):
    require("res/msi/Package/Components/RustDesk.wxs", msi_components, needle)
windows_rs = read("src/platform/windows.rs")
require("src/platform/windows.rs", windows_rs, "legacy_uri_scheme = add_rustdesk_scheme_commands(&nested_exe)")
require("src/platform/windows.rs", windows_rs, "link_schemes::may_claim_rustdesk_scheme(")
require("res/msi/Package/Components/RustDesk.wxs", read("res/msi/Package/Components/RustDesk.wxs"), 'Name="$(var.Executable)"')

# The MSI's licence page is the repository's LICENCE (AGPL-3.0), and the
# signature names the product, which is what UAC shows for a signed MSI.
licence = subprocess.run(
    [sys.executable, str(ROOT / "res" / "msi" / "license_rtf.py"), "--check"],
    capture_output=True,
    text=True,
)
if licence.returncode != 0:
    failures.append(f"res/msi/Package/License.rtf: {(licence.stdout + licence.stderr).strip()}")
licence_rtf = read("res/msi/Package/License.rtf")
for needle in ("GNU AFFERO GENERAL PUBLIC LICENSE", "https://github.com/neodeskapp/neodesk-client"):
    require("res/msi/Package/License.rtf", licence_rtf, needle)
if "Privacy" in licence_rtf or "rustdesk.com" in licence_rtf:
    failures.append("res/msi/Package/License.rtf: still RustDesk's privacy policy")
require("res/msi/preprocess.py", preprocess, "license_rtf.licence_rtf(")

# The MSI's pages carry NeoDesk's own images, never WiX's red default
# artwork: preprocess.py points WixUIDialogBmp and WixUIBannerBmp at the
# bitmaps in Package/Branding (a customer's own in Package/Resources win).
require("res/msi/preprocess.py", preprocess, 'for folder in ("Resources", "Branding"):')
for name, size in (("WixUIDialogBmp", (493, 312)), ("WixUIBannerBmp", (493, 58))):
    relative = f"res/msi/Package/Branding/{name}.bmp"
    if not exists(relative):
        failures.append(f"{relative}: missing, so the MSI shows WiX's default {name}")
        continue
    head = (ROOT / relative).read_bytes()[:26]
    width, height = int.from_bytes(head[18:22], "little"), abs(int.from_bytes(head[22:26], "little", signed=True))
    if head[:2] != b"BM" or width * size[1] != height * size[0] or width < size[0]:
        failures.append(f"{relative}: not a {size[0]} x {size[1]} bitmap (or a larger one of that shape): {width} x {height}")
msi_ui = read("res/msi/Package/UI/MyInstallDlg.wxs")
require("res/msi/Package/UI/MyInstallDlg.wxs", msi_ui, '<DialogRef Id="MyExitDialog" />')
if 'Dialog="ExitDialog"' in msi_ui:
    failures.append("res/msi/Package/UI/MyInstallDlg.wxs: uses WiX's stock finish page")
exit_dialog = read("res/msi/Package/UI/MyExitDlg.wxs") if exists("res/msi/Package/UI/MyExitDlg.wxs") else ""
# The finish page tells a removal by the mode the Remove button set: REMOVE
# lives in the execute sequence and never reaches the UI.
for needle in ('Property="NDOPENAPP"', 'Event="DoAction" Value="LaunchApp"', "!(loc.MyExitDlgRunning)",
               'ShowCondition="Installed AND WixUI_InstallMode=&quot;Remove&quot;"'):
    require("res/msi/Package/UI/MyExitDlg.wxs", exit_dialog, needle)
# The progress page names every custom action's step in words.
named = set(re.findall(r'<ProgressText Action="([^"]+)"', msi_ui))
for relative in ("res/msi/Package/Components/RustDesk.wxs", "res/msi/Package/Package.wxs"):
    for action in re.findall(r'<Custom Action="([^"]+)"', read(relative)):
        if action != "BlockSelfInstalledApp" and action not in named:
            failures.append(f"{relative}: the progress page would show the action name {action}")
msi_strings = read("res/msi/Package/Language/Package.en-us.wxl")
for needle in ('Id="WelcomeDlgTitle"', 'Id="ProgressTextGenerateScript"', 'Id="MyExitDlgOpen"', 'Id="MsiRMFilesInUseTitle"'):
    require("res/msi/Package/Language/Package.en-us.wxl", msi_strings, needle)
sign_action = read(".github/actions/sign-windows/action.yml")
require(".github/actions/sign-windows/action.yml", sign_action, "description: ${{ inputs.description }}")
require(".github/actions/sign-windows/action.yml", sign_action, "--name")
flutter_build = read(".github/workflows/flutter-build.yml")
require(".github/workflows/flutter-build.yml", flutter_build, "description: ${{ env.WINDOWS_SIGNING_DESCRIPTION }}")

mac_xcconfig = read("flutter/macos/Runner/Configs/AppInfo.xcconfig")
require("flutter/macos/Runner/Configs/AppInfo.xcconfig", mac_xcconfig, "PRODUCT_NAME = NeoDesk Client")
require(
    "flutter/macos/Runner/Configs/AppInfo.xcconfig",
    mac_xcconfig,
    "PRODUCT_BUNDLE_IDENTIFIER = sk.neode.neodesk",
)
mac_plist = read("flutter/macos/Runner/Info.plist")
require("flutter/macos/Runner/Info.plist", mac_plist, "<string>neodesk</string>")
# Launch Services picks an unspecified app when two claim one scheme, so the
# Mac app declares only its own.
if "<string>rustdesk</string>" in mac_plist:
    failures.append("flutter/macos/Runner/Info.plist: declares rustdesk://, which is stock RustDesk's")
macos_runtime = read("src/platform/macos.rs")
require("src/platform/macos.rs", macos_runtime, 'sk.neode.{}_service.plist')
require("src/platform/macos.rs", macos_runtime, 'sk.neode.{}_server.plist')

release = read(".github/workflows/neodesk-desktop-release.yml")
require(".github/workflows/neodesk-desktop-release.yml", release, "pattern: neodesk-unsigned-macos-*")
require(".github/workflows/neodesk-desktop-release.yml", release, "scripts/collect_desktop_dist.sh collect")
collect = read("scripts/collect_desktop_dist.sh")
require("scripts/collect_desktop_dist.sh", collect, 'neodesk-unsigned-macos-${arch}')

# Package metadata names NeoDesk, and a pre-release keeps its suffix: in the
# client (hbb_common's release_version) and in each package format.
CONTACT = "NeoDesk <security@neode.sk>"
HOMEPAGE = "https://neode.sk"
require(".github/workflows/neodesk-desktop-release.yml", release, "version: ${{ needs.prepare.outputs.version }}")
require(".github/workflows/flutter-build.yml", flutter_build, "NEODESK_RELEASE_VERSION: ${{ inputs.version }}")
require(".github/workflows/flutter-build.yml", flutter_build, 'export NEODESK_RELEASE_VERSION="${{ inputs.version }}"')
require(".github/workflows/flutter-build.yml", flutter_build, "python3 ./build.py --print-package-version")
import importlib.util

spec = importlib.util.spec_from_file_location("neodesk_build", ROOT / "build.py")
build_module = importlib.util.module_from_spec(spec)
saved_environ = dict(os.environ)
try:
    spec.loader.exec_module(build_module)
    for release, expected in (
        ("1.5.0-rc.4", "1.5.0~rc.4"),
        ("1.5.0-dev.42", "1.5.0~dev.42"),
        ("", "1.5.0"),
        ("1.6.0-rc.1", "1.5.0"),
    ):
        os.environ["NEODESK_RELEASE_VERSION"] = release
        got = build_module.package_version(build_module.release_version("1.5.0"))
        if got != expected:
            failures.append(f"build.py: package version for {release!r} is {got!r}, not {expected!r}")
    os.environ["NEODESK_RELEASE_VERSION"] = "1.5.0-rc.4"
    control = build_module.control_file_content("1.5.0")
    for needle in ("Version: 1.5.0~rc.4\n", f"Maintainer: {CONTACT}\n", f"Homepage: {HOMEPAGE}\n"):
        require("build.py (deb control)", control, needle)
    if "rustdesk" in control.lower():
        failures.append("build.py (deb control): still names rustdesk")
except Exception as err:  # an old build.py has none of these functions
    failures.append(f"build.py: {type(err).__name__}: {err}")
finally:
    os.environ.clear()
    os.environ.update(saved_environ)
for relative in ("res/rpm-flutter.spec", "res/rpm-flutter-suse.spec", "res/rpm.spec", "res/rpm-suse.spec"):
    spec_text = read(relative)
    require(relative, spec_text, f"Vendor:     {CONTACT}")
    require(relative, spec_text, f"URL:        {HOMEPAGE}")
    require(relative, spec_text, "License:    AGPL-3.0-only")
for link in ("https://github.com/rustdesk/rustdesk", "https://github.com/rustdesk/rustdesk/issues/"):
    if f'"v": "{link}"' in preprocess:
        failures.append(f"res/msi/preprocess.py: the MSI's support links still point at {link}")
require("res/msi/preprocess.py", preprocess, 'g_version.split("-", 1)[0]')

if failures:
    print("\n".join(failures), file=sys.stderr)
    sys.exit(1)

print("Desktop packaging contract: OK")
