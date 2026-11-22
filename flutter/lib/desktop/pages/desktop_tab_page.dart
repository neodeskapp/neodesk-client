import 'package:flutter/material.dart';
import 'package:flutter_hbb/common/widgets/bd/bd.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/desktop/pages/desktop_home_page.dart';
import 'package:flutter_hbb/desktop/pages/desktop_setting_page.dart';
import 'package:flutter_hbb/desktop/widgets/tabbar_widget.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/models/state_model.dart';
import 'package:get/get.dart';
import 'package:window_manager/window_manager.dart';
// import 'package:flutter/services.dart';

import '../../common/shared_state.dart';

class DesktopTabPage extends StatefulWidget {
  const DesktopTabPage({Key? key}) : super(key: key);

  @override
  State<DesktopTabPage> createState() => _DesktopTabPageState();

  static void onAddSetting(
      {SettingsTabKey initialPage = SettingsTabKey.general}) {
    try {
      DesktopTabController tabController = Get.find<DesktopTabController>();
      tabController.add(TabInfo(
          key: kTabLabelSettingPage,
          label: kTabLabelSettingPage,
          selectedIcon: BdIcons.settings,
          unselectedIcon: BdIcons.settings,
          page: DesktopSettingPage(
            key: const ValueKey(kTabLabelSettingPage),
            initialTabkey: initialPage,
          )));
    } catch (e) {
      debugPrintStack(label: '$e');
    }
  }
}

class _DesktopTabPageState extends State<DesktopTabPage> {
  final tabController = DesktopTabController(tabType: DesktopTabType.main);

  _DesktopTabPageState() {
    RemoteCountState.init();
    Get.put<DesktopTabController>(tabController);
    tabController.add(TabInfo(
        key: kTabLabelHomePage,
        label: kTabLabelHomePage,
        selectedIcon: BdIcons.home,
        unselectedIcon: BdIcons.home,
        closable: false,
        page: DesktopHomePage(
          key: const ValueKey(kTabLabelHomePage),
        )));
    if (bind.isIncomingOnly()) {
      tabController.onSelected = (key) {
        if (key == kTabLabelHomePage) {
          windowManager.setSize(getIncomingOnlyHomeSize());
          setResizable(false);
        } else {
          windowManager.setSize(getIncomingOnlySettingsSize());
          setResizable(true);
        }
      };
    }
  }

  @override
  void initState() {
    super.initState();
    // HardwareKeyboard.instance.addHandler(_handleKeyEvent);
  }

  /*
  bool _handleKeyEvent(KeyEvent event) {
    if (!mouseIn && event is KeyDownEvent) {
      print('key down: ${event.logicalKey}');
      shouldBeBlocked(_block, canBeBlocked);
    }
    return false; // allow it to propagate
  }
  */

  @override
  void dispose() {
    // HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    Get.delete<DesktopTabController>();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final isIncomingOnly = bind.isIncomingOnly();
      if (isIncomingOnly) {
        tabController.onSelected = (key) {
          if (key == kTabLabelHomePage) {
            windowManager.setSize(getIncomingOnlyHomeSize());
            setResizable(false);
          } else {
            windowManager.setSize(getIncomingOnlySettingsSize());
            setResizable(true);
          }
        };
      } else {
        tabController.onSelected = null;
      }
      final tabWidget = Container(
          key: ValueKey(stateGlobal.connectionModeRevision.value),
          child: Scaffold(
              backgroundColor: context.bd.bg,
              body: DesktopTab(
                controller: tabController,
                // Settings opens in place of Home; Back closes it again.
                tail: Obx(() {
                  final settingsIndex = tabController.state.value.tabs
                      .indexWhere((t) => t.key == kTabLabelSettingPage);
                  if (settingsIndex >= 0) {
                    return BdTitleBarText(
                      icon: BdIcons.arrowBack,
                      label: translate('Back'),
                      onTap: () => tabController.remove(settingsIndex),
                    );
                  }
                  return Offstage(
                    offstage: isIncomingOnly || bind.isDisableSettings(),
                    child: BdTitleBarText(
                      label: translate('Settings'),
                      onTap: DesktopTabPage.onAddSetting,
                    ),
                  );
                }),
              )));
      return isMacOS || kUseCompatibleUiMode
          ? tabWidget
          : DragToResizeArea(
              resizeEdgeSize: stateGlobal.resizeEdgeSize.value,
              enableResizeEdges: windowManagerEnableResizeEdges,
              child: tabWidget,
            );
    });
  }
}
