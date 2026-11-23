// neodesk://settings and neodesk://settings/about: Settings and About in
// the tray menu open the main window there (src/tray_menu.rs).

import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/desktop/pages/desktop_setting_page.dart';
import 'package:flutter_hbb/desktop/widgets/tabbar_widget.dart';
import 'package:get/get.dart';

Future<void> openSettingsLink(Uri uri) async {
  // Started by the link: wait until the main window has its tabs.
  for (var i = 0; i < 50 && !Get.isRegistered<DesktopTabController>(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  await windowOnTop(null);
  final keys = DesktopSettingPage.tabKeys;
  if (keys.isEmpty) return;
  final page = uri.path == '/about'
      ? SettingsTabKey.about
      : keys.contains(SettingsTabKey.general)
          ? SettingsTabKey.general
          : keys.first;
  DesktopSettingPage.switch2page(page);
}
