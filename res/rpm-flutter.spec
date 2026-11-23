Name:       neodesk
Version:    1.5.0
Release:    0
Summary:    NeoDesk remote desktop client
License:    AGPL-3.0-only
URL:        https://neode.sk
Vendor:     NeoDesk <security@neode.sk>
Requires:   gtk3 libxcb libXfixes alsa-lib libva gstreamer1-plugins-base
Recommends: libayatana-appindicator-gtk3 libxdo
Provides:   libdesktop_drop_plugin.so()(64bit), libdesktop_multi_window_plugin.so()(64bit), libfile_selector_linux_plugin.so()(64bit), libflutter_custom_cursor_plugin.so()(64bit), libflutter_linux_gtk.so()(64bit), libscreen_retriever_plugin.so()(64bit), libtray_manager_plugin.so()(64bit), liburl_launcher_linux_plugin.so()(64bit), libwindow_manager_plugin.so()(64bit), libwindow_size_plugin.so()(64bit), libtexture_rgba_renderer_plugin.so()(64bit)

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

%files
/usr/share/neodesk/*
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
    systemctl stop neodesk || true
  ;;
esac

%post
cp /usr/share/neodesk/files/neodesk.service /etc/systemd/system/neodesk.service
cp /usr/share/neodesk/files/neodesk.desktop /usr/share/applications/
cp /usr/share/neodesk/files/neodesk-link.desktop /usr/share/applications/
ln -sf /usr/share/neodesk/neodesk /usr/bin/neodesk
systemctl daemon-reload
systemctl enable neodesk
systemctl start neodesk
update-desktop-database

%preun
case "$1" in
  0)
    # for uninstall
    systemctl stop neodesk || true
    systemctl disable neodesk || true
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
    update-desktop-database
  ;;
  1)
    # for upgrade
          ;;
esac
