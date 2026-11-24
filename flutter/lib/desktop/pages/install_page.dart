import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hbb/common/widgets/bd/bd.dart';
import 'package:flutter_hbb/desktop/pages/install_view.dart';
import 'package:flutter_hbb/onboarding/onboarding_service.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/desktop/widgets/tabbar_widget.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/models/state_model.dart';
import 'package:get/get.dart';
import 'package:path/path.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:window_manager/window_manager.dart';

class InstallPage extends StatefulWidget {
  const InstallPage({Key? key}) : super(key: key);

  @override
  State<InstallPage> createState() => _InstallPageState();
}

class _InstallPageState extends State<InstallPage> {
  final tabController =
      DesktopTabController(tabType: DesktopTabType.install);

  _InstallPageState() {
    Get.put<DesktopTabController>(tabController);
    const label = "install";
    tabController.add(TabInfo(
        key: label,
        label: label,
        closable: false,
        page: _InstallPageBody(
          key: const ValueKey(label),
        )));
  }

  @override
  void dispose() {
    super.dispose();
    Get.delete<DesktopTabController>();
  }

  @override
  Widget build(BuildContext context) {
    return DragToResizeArea(
      resizeEdgeSize: stateGlobal.resizeEdgeSize.value,
      enableResizeEdges: windowManagerEnableResizeEdges,
      child: Container(
        child: Scaffold(
            backgroundColor: context.bd.bg,
            body: DesktopTab(
                controller: tabController,
                showMinimize: false,
                showMaximize: false)),
      ),
    );
  }
}

class _InstallPageBody extends StatefulWidget {
  const _InstallPageBody({Key? key}) : super(key: key);

  @override
  State<_InstallPageBody> createState() => _InstallPageBodyState();
}

class _InstallPageBodyState extends State<_InstallPageBody>
    with WindowListener {
  late final TextEditingController controller;
  final RxBool startmenu = true.obs;
  final RxBool desktopicon = true.obs;
  final RxBool printer = false.obs;
  final RxBool showProgress = false.obs;
  final RxBool btnEnabled = true.obs;
  final Rx<InstallStep> step = InstallStep.permission.obs;
  final RxnInt copyPercent = RxnInt();
  final RxnString error = RxnString();
  Timer? _progressTimer;

  _InstallPageBodyState() {
    controller = TextEditingController(text: bind.installInstallPath());
    final installOptions = jsonDecode(bind.installInstallOptions());
    startmenu.value = installOptions['STARTMENUSHORTCUTS'] != '0';
    desktopicon.value = installOptions['DESKTOPSHORTCUTS'] != '0';
    printer.value = installOptions['PRINTER'] == '1';
  }

  @override
  void initState() {
    windowManager.addListener(this);
    super.initState();
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowClose() {
    gFFI.close();
    super.onWindowClose();
    windowManager.setPreventClose(false);
    windowManager.close();
  }

  final RxBool _optionsOpen = false.obs;

  /// While installing: how long, and the server a join file's computer
  /// joins right after.
  String? _installingLead() {
    final st = OnboardingService.instance.current;
    final company = (st.company ?? '').trim();
    final server = (st.server ?? '').trim();
    if (server.isNotEmpty && st.phase != OnboardingPhase.joined) {
      return tr('bd-install-installing-join',
          [company.isNotEmpty ? company : server]);
    }
    return null;
  }

  /// After installing, a join file's computer joins its server.
  String _lead() {
    final st = OnboardingService.instance.current;
    final company = (st.company ?? '').trim();
    final server = (st.server ?? '').trim();
    if (server.isNotEmpty && st.phase != OnboardingPhase.joined) {
      // Without a company name the server is named once.
      return company.isNotEmpty
          ? tr('bd-install-lead-join', [company, server])
          : tr('bd-install-lead-join-server', [server]);
    }
    return tr('bd-install-lead');
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() => InstallView(
          lead: _lead(),
          pathController: controller,
          startMenu: startmenu.value,
          desktopIcon: desktopicon.value,
          printer: printer.value,
          onStartMenu: (v) => startmenu.value = v,
          onDesktopIcon: (v) => desktopicon.value = v,
          onPrinter: (v) => printer.value = v,
          showPrinter: isWindows,
          optionsOpen: _optionsOpen.value,
          onToggleOptions: () => _optionsOpen.value = !_optionsOpen.value,
          installing: showProgress.value,
          installingLead: _installingLead(),
          step: step.value,
          copyPercent: copyPercent.value,
          error: error.value,
          onInstall: install,
          onChangePath: selectInstallPath,
          onLicence: () => launchUrlString('https://www.gnu.org/licenses/agpl-3.0.html'),
          onRunWithout: bind.installShowRunWithoutInstall()
              ? null
              : () => bind.installRunWithoutInstall(),
        ));
  }

  void install() {
    do_install() {
      btnEnabled.value = false;
      error.value = null;
      step.value = InstallStep.permission;
      copyPercent.value = null;
      showProgress.value = true;
      String args = '';
      if (startmenu.value) args += ' startmenu';
      if (desktopicon.value) args += ' desktopicon';
      if (printer.value) args += ' printer';
      bind.installInstallMe(options: args, path: controller.text);
      _progressTimer?.cancel();
      _progressTimer = Timer.periodic(
          const Duration(milliseconds: 250), (_) => _readProgress());
    }

    do_install();
  }

  /// The step the install is at; the process ends once the installed
  /// client's window is up.
  void _readProgress() {
    Map<String, dynamic> p;
    try {
      p = jsonDecode(bind.installInstallProgress()) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    switch (p['step']) {
      case 'copying':
        step.value = InstallStep.copying;
        copyPercent.value = p['percent'] as int?;
        break;
      case 'service':
        step.value = InstallStep.service;
        break;
      case 'starting':
        step.value = InstallStep.starting;
        break;
      case 'failed':
        _progressTimer?.cancel();
        error.value = p['cancelled'] == true
            ? tr('bd-install-cancelled')
            : tr('bd-install-failed', [p['error'] ?? '']);
        showProgress.value = false;
        btnEnabled.value = true;
        break;
      default:
        step.value = InstallStep.permission;
    }
  }

  void selectInstallPath() async {
    String? install_path = await FilePicker.platform
        .getDirectoryPath(initialDirectory: controller.text);
    if (install_path != null) {
      controller.text = join(install_path, await bind.mainGetAppName());
    }
  }
}
