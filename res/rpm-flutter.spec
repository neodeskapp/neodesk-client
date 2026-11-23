Name:       neodesk
Version:    1.5.0
Release:    0
Summary:    NeoDesk remote desktop client
License:    AGPL-3.0-only
URL:        https://neode.sk
Vendor:     NeoDesk <security@neode.sk>
Requires:   gtk3 libxcb libXfixes alsa-lib libva gstreamer1-plugins-base
Recommends: libayatana-appindicator-gtk3 libxdo libdrm.so.2()(64bit) libEGL.so.1()(64bit) libGLESv2.so.2()(64bit)
Provides:   libdesktop_drop_plugin.so()(64bit), libdesktop_multi_window_plugin.so()(64bit), libfile_selector_linux_plugin.so()(64bit), libflutter_custom_cursor_plugin.so()(64bit), libflutter_linux_gtk.so()(64bit), libscreen_retriever_plugin.so()(64bit), libtray_manager_plugin.so()(64bit), liburl_launcher_linux_plugin.so()(64bit), libwindow_manager_plugin.so()(64bit), libwindow_size_plugin.so()(64bit), libtexture_rgba_renderer_plugin.so()(64bit)
# libdrmtap is dlopen-ed by the root service only at a Wayland login screen, and falls back if it cannot
# load, so its own dependencies (newer glibc, EGL, libdrm) must not become requirements of the package.
%global __requires_exclude_from ^/usr/lib/neodesk/.*$
%global __provides_exclude_from ^/usr/lib/neodesk/.*$

# https://docs.fedoraproject.org/en-US/packaging-guidelines/Scriptlets/

%description
The best open-source remote desktop client software, written in Rust.

%prep
# we have no source, so nothing here

%build
# we have no source, so nothing here

# %global __python %{__python3}

%install

mkdir -p "%{buildroot}/usr/share/neodesk" && cp -r ${HBB}/flutter/build/linux/x64/release/bundle/* -t "%{buildroot}/usr/share/neodesk"
mkdir -p "%{buildroot}/usr/bin"
install -Dm 644 $HBB/res/neodesk.service -t "%{buildroot}/usr/share/neodesk/files"
install -Dm 644 $HBB/res/neodesk.desktop -t "%{buildroot}/usr/share/neodesk/files"
install -Dm 644 $HBB/res/neodesk-link.desktop -t "%{buildroot}/usr/share/neodesk/files"
install -Dm 644 $HBB/res/128x128@2x.png "%{buildroot}/usr/share/icons/hicolor/256x256/apps/neodesk.png"
install -Dm 644 $HBB/res/scalable.svg "%{buildroot}/usr/share/icons/hicolor/scalable/apps/neodesk.svg"
mkdir -p "%{buildroot}/usr/lib/neodesk"
so=$(find "${DRMTAP_PREBUILT_DIR:-${HBB}/third_party/libdrmtap/build-pkg}" -maxdepth 1 -type f -name 'libdrmtap.so.0.*' 2>/dev/null || true)
if [ -n "$so" ]; then install -Dm 755 "$so" -t "%{buildroot}/usr/lib/neodesk"; ln -s "$(basename "$so")" "%{buildroot}/usr/lib/neodesk/libdrmtap.so.0"; fi

%files
/usr/share/neodesk/*
/usr/lib/neodesk
/usr/share/neodesk/files/neodesk.service
/usr/share/icons/hicolor/256x256/apps/neodesk.png
/usr/share/icons/hicolor/scalable/apps/neodesk.svg
/usr/share/neodesk/files/neodesk.desktop
/usr/share/neodesk/files/neodesk-link.desktop

%changelog
# let's skip this for now

%pre
# can do something for centos7
case "$1" in
  1)
    # for install
  ;;
  2)
    # for upgrade
    systemctl stop neodesk >/dev/null 2>&1 || :
  ;;
esac

%post
cp /usr/share/neodesk/files/neodesk.service /etc/systemd/system/neodesk.service
cp /usr/share/neodesk/files/neodesk.desktop /usr/share/applications/
cp /usr/share/neodesk/files/neodesk-link.desktop /usr/share/applications/
ln -sf /usr/share/neodesk/neodesk /usr/bin/neodesk
systemctl daemon-reload >/dev/null 2>&1 || :
systemctl enable neodesk >/dev/null 2>&1 || :
systemctl start neodesk >/dev/null 2>&1 || :
update-desktop-database >/dev/null 2>&1 || :

%preun
case "$1" in
  0)
    # for uninstall
    systemctl stop neodesk >/dev/null 2>&1 || :
    systemctl disable neodesk >/dev/null 2>&1 || :
    rm /etc/systemd/system/neodesk.service || true
  ;;
  1)
    # for upgrade
  ;;
esac

%postun
case "$1" in
  0)
    # for uninstall
    rm /usr/bin/neodesk || true
            rmdir /usr/share/neodesk || true
    rm /usr/share/applications/neodesk.desktop || true
    rm /usr/share/applications/neodesk-link.desktop || true
    update-desktop-database >/dev/null 2>&1 || :
  ;;
  1)
    # for upgrade
          ;;
esac
