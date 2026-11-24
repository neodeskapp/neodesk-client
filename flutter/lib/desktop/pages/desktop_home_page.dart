import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/widgets/nd/nd.dart';
import 'package:flutter_hbb/common/widgets/custom_password.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/desktop/pages/connection_page.dart';
import 'package:flutter_hbb/desktop/pages/home/home_widgets.dart';
import 'package:flutter_hbb/models/branding_model.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/models/server_model.dart';
import 'package:flutter_hbb/models/state_model.dart';
import 'package:flutter_hbb/onboarding/onboarding_flow.dart';
import 'package:flutter_hbb/onboarding/onboarding_service.dart';
import 'package:flutter_hbb/utils/multi_window_manager.dart';
import 'package:flutter_hbb/utils/platform_channel.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';
import 'package:window_size/window_size.dart' as window_size;

/// Home: this computer on the left, connect to another computer on the
/// right (DESIGN.md, Home). Without a server, first start and joining take
/// its place.
class DesktopHomePage extends StatefulWidget {
  const DesktopHomePage({Key? key}) : super(key: key);

  @override
  State<DesktopHomePage> createState() => _DesktopHomePageState();
}

class _DesktopHomePageState extends State<DesktopHomePage>
    with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  @override
  bool get wantKeepAlive => true;

  var systemError = '';
  StreamSubscription? _uniLinksSubscription;
  StreamSubscription<OnboardingState>? _onboardingSub;
  var svcStopped = false.obs;
  var watchIsCanScreenRecording = false;
  var watchIsProcessTrust = false;
  var watchIsInputMonitoring = false;
  var watchIsCanRecordAudio = false;
  Timer? _updateTimer;
  bool isCardClosed = false;
  final _genericServerController = TextEditingController();
  var _genericSetupBusy = false;
  var _genericSetupMessage = '';
  bool _joinFlowOpen = false;

  final RxBool _block = false.obs;

  final GlobalKey _childKey = GlobalKey();

  OnboardingService get _onboarding => OnboardingService.instance;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final state = _onboarding.current;
    if (!bind.isIncomingOnly() &&
        !bind.isOutgoingOnly() &&
        onboardingShowsInPlaceOfHome(state, _joinFlowOpen)) {
      return OnboardingFlow(
        service: _onboarding,
        onFinished: () => setState(() => _joinFlowOpen = false),
      );
    }
    final isIncomingOnly = bind.isIncomingOnly();
    final isOutgoingOnly = bind.isOutgoingOnly();
    return _buildBlock(
      child: ChangeNotifierProvider.value(
        value: gFFI.serverModel,
        child: HomeLayout(
          left: isOutgoingOnly ? null : buildLeftPane(context),
          right: isIncomingOnly ? null : const ConnectionPage(),
        ),
      ),
    );
  }

  Widget _buildBlock({required Widget child}) {
    return buildRemoteBlock(
        block: _block, mask: true, use: canBeBlocked, child: child);
  }

  Widget buildLeftPane(BuildContext context) {
    final isIncomingOnly = bind.isIncomingOnly();
    final isGenericSupport = isIncomingOnly &&
        bind.mainGetOptionSync(key: 'api-server').trim().isEmpty;
    return Consumer<ServerModel>(builder: (context, model, _) {
      return Obx(() {
        // Rebuild when help cards change (update url, branding).
        stateGlobal.updateUrl.value;
        final branding = BrandingModel.current;
        final company = branding.companyName.value.trim();
        final notices = <Widget>[
          buildPresetPasswordWarning(),
          ...buildHelpNotices(),
          if (isGenericSupport) buildGenericSupportSetup(context),
          if (isIncomingOnly && !isGenericSupport)
            buildGenericPairingQr(context),
        ];
        final onlyClick = model.approveMode == 'click';
        final permanentOnly =
            !onlyClick && model.verificationMethod == kUsePermanentPassword;
        final phone = branding.phone.value.trim();
        final email = branding.email.value.trim();
        final website = branding.website.value.trim();
        Widget column = ThisComputerColumn(
          key: _childKey,
          id: model.serverId.text,
          password: onlyClick ? null : model.serverPasswd.text,
          permanentOnly: permanentOnly,
          onlyClick: onlyClick,
          status: const HomeStatus(NdStatusKind.wait, ''),
          statusWidget: OnlineStatusWidget(
            onSvcStatusChanged: () {
              if (isIncomingOnly && isInHomePage()) {
                Future.delayed(const Duration(milliseconds: 300), () {
                  _updateWindowSize();
                });
              }
            },
          ),
          notices: notices,
          onNewPassword: permanentOnly
              ? null
              : () async => bind.mainUpdateTemporaryPassword(),
          support: branding.hasContactOrLogo || company.isNotEmpty
              ? HomeSupportContact(
                  company: company.isNotEmpty ? company : translate('Support'),
                  phone: phone,
                  email: email,
                  website: website,
                  onPhone: phone.isEmpty
                      ? null
                      : () => launchUrl(Uri(scheme: 'tel', path: phone)),
                  onEmail: email.isEmpty
                      ? null
                      : () => launchUrl(Uri(scheme: 'mailto', path: email)),
                  onWebsite: website.isEmpty
                      ? null
                      : () => launchUrl(Uri.parse(
                          BrandingModel.normalizeWebsiteUrl(website))),
                )
              : null,
          footer: isIncomingOnly
              ? Align(
                  alignment: Alignment.centerRight,
                  child: NdButton(
                    label: translate('Quit'),
                    onPressed: () {
                      SystemNavigator.pop(); // Close the application
                      // https://github.com/flutter/flutter/issues/66631
                      if (isWindows) {
                        exit(0);
                      }
                    },
                  ),
                )
              : null,
        );
        return column;
      });
    });
  }

  /// The old help cards as notices above the ID panel: not installed,
  /// macOS permissions, the background service, SELinux and Wayland.
  List<Widget> buildHelpNotices() {
    final hideCards =
        bind.mainGetBuildinOption(key: kOptionHideHelpCards) == 'Y';
    Widget notice(String text,
        {NdTone tone = NdTone.warning,
        String? action,
        VoidCallback? onAction,
        String? help,
        String? link,
        String? closeOption,
        bool always = false}) {
      if (hideCards && !always) return const SizedBox.shrink();
      return NdNotice(
        tone: tone,
        text: text,
        action: Row(mainAxisSize: MainAxisSize.min, children: [
          if (help != null && link != null)
            NdButton.link(
                label: help, onPressed: () => launchUrl(Uri.parse(link))),
          if (action != null) ...[
            const SizedBox(width: 12),
            NdButton(
                label: action, size: NdButtonSize.sm, onPressed: onAction),
          ],
          if (closeOption != null) ...[
            const SizedBox(width: 4),
            NdIconButton(
              icon: NdIcons.close,
              tooltip: translate('Close'),
              onPressed: () async {
                await bind.mainSetLocalOption(key: closeOption, value: 'N');
                if (mounted) setState(() => isCardClosed = true);
              },
            ),
          ],
        ]),
      );
    }

    if (systemError.isNotEmpty) {
      return [notice(translate(systemError), tone: NdTone.danger, always: true)];
    }
    if (isWindows && !bind.isDisableInstallation()) {
      if (!bind.mainIsInstalled()) {
        return [
          notice(tr('nd-home-not-installed'),
              action: translate('Install'), onAction: () async {
            await rustDeskWinManager.closeAllSubWindows();
            bind.mainGotoInstall();
          })
        ];
      }
    } else if (isMacOS) {
      final isOutgoingOnly = bind.isOutgoingOnly();
      final help = tr('nd-help');
      final link = translate('doc_mac_permission');
      if (!(isOutgoingOnly || bind.mainIsCanScreenRecording(prompt: false))) {
        return [
          notice(tr('nd-home-perm-screen'),
              action: tr('nd-home-open-system-settings'),
              help: help,
              link: link, onAction: () {
            bind.mainIsCanScreenRecording(prompt: true);
            watchIsCanScreenRecording = true;
          })
        ];
      } else if (!isOutgoingOnly && !bind.mainIsProcessTrusted(prompt: false)) {
        return [
          notice(tr('nd-home-perm-accessibility'),
              action: tr('nd-home-open-system-settings'),
              help: help,
              link: link, onAction: () {
            bind.mainIsProcessTrusted(prompt: true);
            watchIsProcessTrust = true;
          })
        ];
      } else if (!bind.mainIsCanInputMonitoring(prompt: false)) {
        return [
          notice(tr('nd-home-perm-input'),
              action: tr('nd-home-open-system-settings'),
              help: help,
              link: link, onAction: () {
            bind.mainIsCanInputMonitoring(prompt: true);
            watchIsInputMonitoring = true;
          })
        ];
      } else if (!isOutgoingOnly &&
          !svcStopped.value &&
          bind.mainIsInstalled() &&
          !bind.mainIsInstalledDaemon(prompt: false)) {
        return [
          notice(tr('nd-home-daemon'),
              action: translate('Install'),
              always: true,
              onAction: () => bind.mainIsInstalledDaemon(prompt: true))
        ];
      }
    } else if (isLinux) {
      if (bind.isOutgoingOnly()) return [];
      final cards = <Widget>[];
      if (bind.isSelinuxEnforcing()) {
        const keyShowSelinuxHelpTip = 'show-selinux-help-tip';
        if (bind.mainGetLocalOption(key: keyShowSelinuxHelpTip) != 'N') {
          cards.add(notice(translate('selinux_tip'),
              tone: NdTone.info,
              help: tr('nd-help'),
              link:
                  'https://rustdesk.com/docs/en/client/linux/#permissions-issue',
              closeOption: keyShowSelinuxHelpTip));
        }
      }
      if (bind.mainCurrentIsWayland()) {
        cards.add(notice(translate('wayland_experiment_tip'),
            tone: NdTone.info,
            help: tr('nd-help'),
            link: 'https://rustdesk.com/docs/en/client/linux/#x11-required'));
      } else if (bind.mainIsLoginWayland()) {
        cards.add(notice(
            translate('Login screen using Wayland is not supported'),
            tone: NdTone.info,
            help: tr('nd-help'),
            link: 'https://rustdesk.com/docs/en/client/linux/#login-screen'));
      }
      return cards;
    }
    return [];
  }

  Widget buildGenericSupportSetup(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.nd.rule),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Connect NeoDesk Support',
              style: theme.textTheme.titleSmall),
          const SizedBox(height: 6),
          const Text(
            'Enter the public NeoDesk address. The server will provide the remaining configuration after activation.',
            style: TextStyle(fontSize: 11),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _genericServerController,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'NeoDesk server',
              hintText: 'https://support.example.com',
              isDense: true,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _genericSetupBusy ? null : _configureGenericSupport,
              child: _genericSetupBusy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Connect'),
            ),
          ),
          if (_genericSetupMessage.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(_genericSetupMessage,
                style: TextStyle(
                  fontSize: 11,
                  color: theme.colorScheme.error,
                )),
          ],
        ],
      ),
    );
  }

  Widget buildGenericPairingQr(BuildContext context) {
    final server = bind.mainGetOptionSync(key: 'api-server').trim();
    final deviceId = gFFI.serverModel.serverId.text.trim();
    if (server.isEmpty || deviceId.isEmpty || deviceId == 'Generating ...') {
      return const SizedBox.shrink();
    }
    final payload = jsonEncode({
      'type': 'neodesk-agent-pairing',
      'version': 1,
      'server': server,
      'device_id': deviceId,
    });
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          const Text('Activate this agent from the NeoDesk panel',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          QrImageView(data: payload, size: 170, backgroundColor: context.nd.white),
          const SizedBox(height: 4),
          Text(deviceId, textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 10)),
        ],
      ),
    );
  }

  Future<void> _configureGenericSupport() async {
    final input = _genericServerController.text.trim();
    Uri? parsed;
    try {
      parsed = Uri.parse(input);
    } catch (_) {}
    if (parsed == null ||
        !parsed.hasAuthority ||
        !{'http', 'https'}.contains(parsed.scheme.toLowerCase())) {
      setState(() => _genericSetupMessage = 'Use a valid http(s) server address.');
      return;
    }
    final origin = Uri(
      scheme: parsed.scheme.toLowerCase(),
      host: parsed.host,
      port: parsed.hasPort ? parsed.port : null,
    ).toString().replaceFirst(RegExp(r'/$'), '');
    setState(() {
      _genericSetupBusy = true;
      _genericSetupMessage = '';
    });
    try {
      final response = await http.get(Uri.parse('$origin/api/server-key'));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('Server key request failed (${response.statusCode}).');
      }
      final decoded = jsonDecode(response.body);
      final serverKey = decoded is Map ? (decoded['key'] ?? '') : '';
      if (serverKey is! String || serverKey.trim().isEmpty) {
        throw Exception('The server did not return its public key.');
      }
      final authority = parsed.host +
          (parsed.hasPort ? ':${parsed.port}' : '');
      await bind.mainSetOption(key: 'custom-rendezvous-server', value: authority);
      await bind.mainSetOption(key: 'relay-server', value: authority);
      await bind.mainSetOption(key: 'api-server', value: origin);
      await bind.mainSetOption(key: 'key', value: serverKey.trim());
      if (mounted) setState(() => _genericSetupMessage = '');
    } catch (error) {
      if (mounted) {
        setState(() => _genericSetupMessage = error.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _genericSetupBusy = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _updateTimer = periodic_immediate(const Duration(seconds: 1), () async {
      await gFFI.serverModel.fetchID();
      final error = await bind.mainGetError();
      if (systemError != error) {
        systemError = error;
        setState(() {});
      }
      final v = await mainGetBoolOption(kOptionStopService);
      if (v != svcStopped.value) {
        svcStopped.value = v;
        setState(() {});
      }
      if (watchIsCanScreenRecording) {
        if (bind.mainIsCanScreenRecording(prompt: false)) {
          watchIsCanScreenRecording = false;
          setState(() {});
        }
      }
      if (watchIsProcessTrust) {
        if (bind.mainIsProcessTrusted(prompt: false)) {
          watchIsProcessTrust = false;
          setState(() {});
        }
      }
      if (watchIsInputMonitoring) {
        if (bind.mainIsCanInputMonitoring(prompt: false)) {
          watchIsInputMonitoring = false;
          // Do not notify for now.
          // Monitoring may not take effect until the process is restarted.
          // rustDeskWinManager.call(
          //     WindowType.RemoteDesktop, kWindowDisableGrabKeyboard, '');
          setState(() {});
        }
      }
      if (watchIsCanRecordAudio) {
        if (isMacOS) {
          Future.microtask(() async {
            if ((await osxCanRecordAudio() ==
                PermissionAuthorizeType.authorized)) {
              watchIsCanRecordAudio = false;
              setState(() {});
            }
          });
        } else {
          watchIsCanRecordAudio = false;
          setState(() {});
        }
      }
    });
    Get.put<RxBool>(svcStopped, tag: 'stop-service');
    rustDeskWinManager.registerActiveWindowListener(onActiveWindowChanged);

    screenToMap(window_size.Screen screen) => {
          'frame': {
            'l': screen.frame.left,
            't': screen.frame.top,
            'r': screen.frame.right,
            'b': screen.frame.bottom,
          },
          'visibleFrame': {
            'l': screen.visibleFrame.left,
            't': screen.visibleFrame.top,
            'r': screen.visibleFrame.right,
            'b': screen.visibleFrame.bottom,
          },
          'scaleFactor': screen.scaleFactor,
        };

    bool isChattyMethod(String methodName) {
      switch (methodName) {
        case kWindowBumpMouse: return true;
      }

      return false;
    }

    rustDeskWinManager.setMethodHandler((call, fromWindowId) async {
      if (!isChattyMethod(call.method)) {
        debugPrint(
          "[Main] call ${call.method} with args ${call.arguments} from window $fromWindowId");
      }
      if (call.method == kWindowMainWindowOnTop) {
        windowOnTop(null);
      } else if (call.method == kWindowRefreshCurrentUser) {
        gFFI.userModel.refreshCurrentUser();
      } else if (call.method == kWindowGetScreenList) {
        return jsonEncode(
            (await window_size.getScreenList()).map(screenToMap).toList());
      } else if (call.method == kWindowActionRebuild) {
        reloadCurrentWindow();
      } else if (call.method == kWindowEventShow) {
        await rustDeskWinManager.registerActiveWindow(call.arguments["id"]);
      } else if (call.method == kWindowEventHide) {
        await rustDeskWinManager.unregisterActiveWindow(call.arguments['id']);
      } else if (call.method == kWindowConnect) {
        await connectMainDesktop(
          call.arguments['id'],
          isFileTransfer: call.arguments['isFileTransfer'],
          isViewCamera: call.arguments['isViewCamera'],
          isTerminal: call.arguments['isTerminal'],
          isTcpTunneling: call.arguments['isTcpTunneling'],
          isRDP: call.arguments['isRDP'],
          password: call.arguments['password'],
          forceRelay: call.arguments['forceRelay'],
          connToken: call.arguments['connToken'],
        );
      } else if (call.method == kWindowBumpMouse) {
        return RdPlatformChannel.instance.bumpMouse(
          dx: call.arguments['dx'],
          dy: call.arguments['dy']);
      } else if (call.method == kWindowEventMoveTabToNewWindow) {
        final args = call.arguments.split(',');
        int? windowId;
        try {
          windowId = int.parse(args[0]);
        } catch (e) {
          debugPrint("Failed to parse window id '${call.arguments}': $e");
        }
        WindowType? windowType;
        try {
          windowType = WindowType.values.byName(args[3]);
        } catch (e) {
          debugPrint("Failed to parse window type '${call.arguments}': $e");
        }
        if (windowId != null && windowType != null) {
          await rustDeskWinManager.moveTabToNewWindow(
              windowId, args[1], args[2], windowType);
        }
      } else if (call.method == kWindowEventOpenMonitorSession) {
        final args = jsonDecode(call.arguments);
        final windowId = args['window_id'] as int;
        final peerId = args['peer_id'] as String;
        final display = args['display'] as int;
        final displayCount = args['display_count'] as int;
        final windowType = args['window_type'] as int;
        final screenRect = parseParamScreenRect(args);
        await rustDeskWinManager.openMonitorSession(
            windowId, peerId, display, displayCount, screenRect, windowType);
      } else if (call.method == kWindowEventRemoteWindowCoords) {
        final windowId = int.tryParse(call.arguments);
        if (windowId != null) {
          return jsonEncode(
              await rustDeskWinManager.getOtherRemoteWindowCoords(windowId));
        }
      }
    });
    _uniLinksSubscription = listenUniLinks();
    _onboardingSub = _onboarding.states.listen((s) {
      if (!mounted) return;
      setState(() {
        if (s.phase == OnboardingPhase.joining) _joinFlowOpen = true;
      });
    });

    if (bind.isIncomingOnly()) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _updateWindowSize();
      });
    }
    WidgetsBinding.instance.addObserver(this);
  }

  _updateWindowSize() {
    RenderObject? renderObject = _childKey.currentContext?.findRenderObject();
    if (renderObject == null) {
      return;
    }
    if (renderObject is RenderBox) {
      final size = renderObject.size;
      if (size != imcomingOnlyHomeSize) {
        imcomingOnlyHomeSize = size;
        windowManager.setSize(getIncomingOnlyHomeSize());
      }
    }
  }

  @override
  void dispose() {
    _genericServerController.dispose();
    _uniLinksSubscription?.cancel();
    _onboardingSub?.cancel();
    Get.delete<RxBool>(tag: 'stop-service');
    _updateTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      shouldBeBlocked(_block, canBeBlocked);
    }
  }
}

void setPasswordDialog({VoidCallback? notEmptyCallback}) async {
  final p0 = TextEditingController(text: "");
  final p1 = TextEditingController(text: "");
  var errMsg0 = "";
  var errMsg1 = "";
  final localPasswordSet =
      (await bind.mainGetCommon(key: "local-permanent-password-set")) == "true";
  final permanentPasswordSet =
      (await bind.mainGetCommon(key: "permanent-password-set")) == "true";
  final presetPassword = permanentPasswordSet && !localPasswordSet;
  var canSubmit = false;
  final RxString rxPass = "".obs;
  final rules = [
    DigitValidationRule(),
    UppercaseValidationRule(),
    LowercaseValidationRule(),
    // SpecialCharacterValidationRule(),
    MinCharactersValidationRule(8),
  ];
  final maxLength = bind.mainMaxEncryptLen();
  final statusTip = localPasswordSet
      ? translate('password-hidden-tip')
      : (presetPassword ? translate('preset-password-in-use-tip') : '');
  final showStatusTipOnMobile =
      statusTip.isNotEmpty && !isDesktop && !isWebDesktop;

  gFFI.dialogManager.show((setState, close, context) {
    updateCanSubmit() {
      canSubmit = p0.text.trim().isNotEmpty || p1.text.trim().isNotEmpty;
    }

    submit() async {
      if (!canSubmit) {
        return;
      }
      setState(() {
        errMsg0 = "";
        errMsg1 = "";
      });
      final pass = p0.text.trim();
      if (pass.isNotEmpty) {
        final Iterable violations = rules.where((r) => !r.validate(pass));
        if (violations.isNotEmpty) {
          setState(() {
            errMsg0 =
                '${translate('Prompt')}: ${violations.map((r) => r.name).join(', ')}';
          });
          return;
        }
      }
      if (p1.text.trim() != pass) {
        setState(() {
          errMsg1 =
              '${translate('Prompt')}: ${translate("The confirmation is not identical.")}';
        });
        return;
      }
      final ok = await bind.mainSetPermanentPasswordWithResult(password: pass);
      if (!ok) {
        setState(() {
          errMsg0 = '${translate('Prompt')}: ${translate("Failed")}';
        });
        return;
      }
      if (pass.isNotEmpty) {
        notEmptyCallback?.call();
      }
      close();
    }

    return CustomAlertDialog(
      title: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(NdIcons.key, color: context.nd.accent),
          Text(translate("Set Password")).paddingOnly(left: 10),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 500),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: showStatusTipOnMobile ? 0.0 : 6.0,
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    obscureText: true,
                    decoration: InputDecoration(
                        labelText: translate('Password'),
                        errorText: errMsg0.isNotEmpty ? errMsg0 : null),
                    controller: p0,
                    autofocus: true,
                    onChanged: (value) {
                      rxPass.value = value.trim();
                      setState(() {
                        errMsg0 = '';
                        updateCanSubmit();
                      });
                    },
                    maxLength: maxLength,
                  ).workaroundFreezeLinuxMint(),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(child: PasswordStrengthIndicator(password: rxPass)),
              ],
            ).marginOnly(top: 2, bottom: showStatusTipOnMobile ? 2 : 8),
            SizedBox(
              height: showStatusTipOnMobile ? 0.0 : 8.0,
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    obscureText: true,
                    decoration: InputDecoration(
                        labelText: translate('Confirmation'),
                        errorText: errMsg1.isNotEmpty ? errMsg1 : null),
                    controller: p1,
                    onChanged: (value) {
                      setState(() {
                        errMsg1 = '';
                        updateCanSubmit();
                      });
                    },
                    maxLength: maxLength,
                  ).workaroundFreezeLinuxMint(),
                ),
              ],
            ),
            if (statusTip.isNotEmpty)
              Row(
                children: [
                  Icon(NdIcons.info, color: context.nd.warning, size: 18)
                      .marginOnly(right: 6),
                  Expanded(
                      child: Text(
                    statusTip,
                    style: const TextStyle(fontSize: 13, height: 1.1),
                  ))
                ],
              ).marginOnly(top: 6, bottom: 2),
            SizedBox(
              height: showStatusTipOnMobile ? 0.0 : 8.0,
            ),
            Obx(() => Wrap(
                  runSpacing: showStatusTipOnMobile ? 2.0 : 8.0,
                  spacing: 4,
                  children: rules.map((e) {
                    var checked = e.validate(rxPass.value.trim());
                    return Chip(
                        label: Text(
                          e.name,
                          style: TextStyle(
                              color: checked
                                  ? context.nd.success
                                  : context.nd.danger),
                        ),
                        backgroundColor: checked
                            ? context.nd.noticeBg(context.nd.success)
                            : context.nd.noticeBg(context.nd.danger));
                  }).toList(),
                ))
          ],
        ),
      ),
      actions: (() {
        final cancelButton = dialogButton(
          "Cancel",
          icon: Icon(NdIcons.close),
          onPressed: close,
          isOutline: true,
        );
        final removeButton = dialogButton(
          "Remove",
          icon: Icon(NdIcons.delete),
          onPressed: () async {
            setState(() {
              errMsg0 = "";
              errMsg1 = "";
            });
            final ok =
                await bind.mainSetPermanentPasswordWithResult(password: "");
            if (!ok) {
              setState(() {
                errMsg0 = '${translate('Prompt')}: ${translate("Failed")}';
              });
              return;
            }
            close();
          },
          buttonStyle: ButtonStyle(
              backgroundColor: WidgetStatePropertyAll(context.nd.danger)),
        );
        final okButton = dialogButton(
          "OK",
          icon: Icon(NdIcons.check),
          onPressed: canSubmit ? submit : null,
        );
        if (!isDesktop && !isWebDesktop && localPasswordSet) {
          return [
            Align(
              alignment: Alignment.centerRight,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    cancelButton,
                    const SizedBox(width: 4),
                    removeButton,
                    const SizedBox(width: 4),
                    okButton,
                  ],
                ),
              ),
            ),
          ];
        }
        return [
          cancelButton,
          if (localPasswordSet) removeButton,
          okButton,
        ];
      })(),
      onSubmit: canSubmit ? submit : null,
      onCancel: close,
    );
  });
}
