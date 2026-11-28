Name:       neodesk
Version:    1.1.9
Release:    0
Summary:    NeoDesk remote desktop client
License:    AGPL-3.0-only
URL:        https://neode.sk
Vendor:     NeoDesk <security@neode.sk>
Requires:   gtk3 libxcb1 libXfixes3 alsa-utils libXtst6 libva2 gstreamer-plugins-base gstreamer-plugin-pipewire
Recommends: libayatana-appindicator3-1 xdotool

# https://docs.fedoraproject.org/en-US/packaging-guidelines/Scriptlets/

%description
The best open-source remote desktop client software, written in Rust.

%prep
# we have no source, so nothing here

%build
# we have no source, so nothing here

%global __python %{__python3}

%install
mkdir -p %{buildroot}/usr/bin/
mkdir -p %{buildroot}/usr/share/neodesk/
mkdir -p %{buildroot}/usr/share/neodesk/files/
mkdir -p %{buildroot}/usr/share/icons/hicolor/256x256/apps/
mkdir -p %{buildroot}/usr/share/icons/hicolor/scalable/apps/
install -m 755 $HBB/target/release/rustdesk %{buildroot}/usr/bin/neodesk
install $HBB/libsciter-gtk.so %{buildroot}/usr/share/neodesk/libsciter-gtk.so
install $HBB/res/neodesk.service %{buildroot}/usr/share/neodesk/files/
install $HBB/res/128x128@2x.png %{buildroot}/usr/share/icons/hicolor/256x256/apps/neodesk.png
install $HBB/res/scalable.svg %{buildroot}/usr/share/icons/hicolor/scalable/apps/neodesk.svg
install -Dm 644 $HBB/res/marker-font/NeoDeskMarker.ttf "%{buildroot}/usr/share/fonts/truetype/neodesk/NeoDeskMarker.ttf"
install $HBB/res/neodesk.desktop %{buildroot}/usr/share/neodesk/files/
install $HBB/res/neodesk-link.desktop %{buildroot}/usr/share/neodesk/files/

%files
/usr/bin/neodesk
/usr/share/neodesk/libsciter-gtk.so
/usr/share/neodesk/files/neodesk.service
/usr/share/icons/hicolor/256x256/apps/neodesk.png
/usr/share/icons/hicolor/scalable/apps/neodesk.svg
%dir /usr/share/fonts/truetype/neodesk
/usr/share/fonts/truetype/neodesk/NeoDeskMarker.ttf
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
systemctl daemon-reload >/dev/null 2>&1 || :
systemctl enable neodesk >/dev/null 2>&1 || :
systemctl start neodesk >/dev/null 2>&1 || :
update-desktop-database >/dev/null 2>&1 || :
fc-cache >/dev/null 2>&1 || :

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
    rm /usr/share/applications/neodesk.desktop || true
    rm /usr/share/applications/neodesk-link.desktop || true
    update-desktop-database >/dev/null 2>&1 || :
    fc-cache >/dev/null 2>&1 || :
  ;;
  1)
    # for upgrade
  ;;
esac
