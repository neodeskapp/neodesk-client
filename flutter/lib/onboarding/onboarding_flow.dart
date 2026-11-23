import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/widgets/bd/bd.dart';
import 'package:flutter_hbb/common/widgets/bd/bd_dialog_host.dart';
import 'package:flutter_hbb/common/widgets/branding_logo.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/models/branding_model.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:get/get.dart';
import 'package:window_manager/window_manager.dart';

import 'first_start_view.dart';
import 'joining_view.dart';
import 'onboarding_service.dart';
import 'setup_by_hand.dart';

/// Whether the main window shows the onboarding pages instead of Home.
bool onboardingShowsInPlaceOfHome(OnboardingState s, bool joinFlowOpen) {
  switch (s.phase) {
    case OnboardingPhase.notSetUp:
    case OnboardingPhase.joining:
    case OnboardingPhase.joinFailed:
      return true;
    case OnboardingPhase.joined:
      return joinFlowOpen;
    default:
      return false;
  }
}

/// First start and joining in the main window: follows the service and
/// opens the hand setup.
class OnboardingFlow extends StatefulWidget {
  const OnboardingFlow({super.key, required this.service, required this.onFinished});

  final OnboardingService service;

  /// Done on the joined screen.
  final VoidCallback onFinished;

  @override
  State<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends State<OnboardingFlow> {
  StreamSubscription<OnboardingState>? _sub;
  late OnboardingState _state = widget.service.current;
  bool _retry = false;

  @override
  void initState() {
    super.initState();
    _sub = widget.service.states.listen((s) {
      if (!mounted) return;
      setState(() {
        _state = s;
        if (s.phase == OnboardingPhase.joining) _retry = false;
        if (s.accentHex != null && s.accentHex!.isNotEmpty) {
          BrandingModel.current.accentColor.value = s.accentHex!;
        }
      });
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Widget? _logo() {
    final b = BrandingModel.current;
    if (!b.hasLogo.value || b.logoPath.value.isEmpty) return null;
    return BrandingLogoImage(
      path: b.logoPath.value,
      cacheKey: 'branding-join-${b.logoPath.value}-${b.logoEpoch.value}',
      maxHeight: 34,
      fit: BoxFit.contain,
      alignment: Alignment.center,
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = _state;
    if (_retry ||
        s.phase == OnboardingPhase.notSetUp ||
        !onboardingShowsInPlaceOfHome(s, true)) {
      return FirstStartView(
        service: widget.service,
        onSetUpByHand: () => showSetupByHand(),
      );
    }
    return Obx(() {
      BrandingModel.current.logoEpoch.value;
      return JoiningView(
        state: s,
        logo: _logo(),
        deviceId: gFFI.serverModel.serverId.text,
        onDone: () {
          widget.service.dismissJoined();
          widget.onFinished();
        },
        onTryAnother: () => setState(() => _retry = true),
        onSetUpByHand: () => showSetupByHand(),
      );
    });
  }
}

/// The hand setup dialog with today's server settings, saved through
/// setServerConfig (the same checks as the old ID/Relay Server dialog).
Future<void> showSetupByHand() async {
  final options = jsonDecodeOptions(await bind.mainGetOptions());
  final current = ServerConfig.fromOptions(options);
  final locked = isOptionFixed('custom-rendezvous-server') ||
      bind.mainGetBuildinOption(key: kOptionHideServerSetting) == 'Y';
  await showBdDialog<void>((close, setState) => SetupByHandDialog(
        initial: HandSetup(
          idServer: current.idServer,
          key: current.key,
          relayServer: current.relayServer,
          apiServer: current.apiServer,
        ),
        locked: locked,
        onCancel: close,
        onSave: (h) async {
          final errs = [RxString(''), RxString(''), RxString(''), RxString('')];
          final ok = await setServerConfig(
            null,
            errs,
            ServerConfig(
              idServer: h.idServer,
              relayServer: h.relayServer,
              apiServer: h.apiServer,
              key: h.key,
            ),
          );
          if (ok) {
            close();
            return const HandSetupErrors();
          }
          String? e(RxString r) => r.value.isEmpty ? null : r.value;
          return HandSetupErrors(
            idServer: e(errs[0]),
            relayServer: e(errs[1]),
            apiServer: e(errs[2]),
            key: e(errs[3]),
          );
        },
      ));
}

/// Join a server from Settings: the first-start field in a dialog. When the
/// computer already has a server, it first asks to leave it.
Future<void> showJoinServerDialog(OnboardingService service,
    {required String currentServer}) async {
  final controller = TextEditingController();
  String? error;
  await showBdDialog<void>((close, setState) {
    Future<void> submit() async {
      final input = InviteInput.parse(controller.text);
      if (input.kind == InviteKind.invalid || input.kind == InviteKind.empty) {
        setState(() => error = tr('bd-invite-error-not-invite'));
        return;
      }
      final newHost = input.host ?? '';
      if (currentServer.isNotEmpty &&
          newHost.isNotEmpty &&
          newHost != currentServer) {
        final go = await showBdDialog<bool>((c2, _) => BdDialog(
              title: tr('bd-join-leave-title'),
              width: 480,
              onClose: () => c2(false),
              closeTooltip: translate('Close'),
              children: [
                Text(tr('bd-join-leave', [currentServer, newHost]),
                    style: Get.context!.bdText.body),
              ],
              actions: [
                BdButton(
                    label: translate('Cancel'), onPressed: () => c2(false)),
                BdButton.primary(
                    label: tr('bd-join'), onPressed: () => c2(true)),
              ],
            ));
        if (go != true) return;
      }
      close();
      await service.redeemJoin(controller.text.trim());
    }

    return BdDialog(
      title: tr('bd-join-a-server'),
      width: 520,
      onClose: close,
      closeTooltip: translate('Close'),
      children: [
        BdField(
          label: tr('bd-invite-field'),
          hint: tr('bd-invite-hint'),
          error: error,
          controller: controller,
          large: true,
          mono: true,
          autofocus: true,
          onChanged: (_) => setState(() => error = null),
          onSubmitted: (_) => submit(),
        ),
      ],
      actions: [
        BdButton(label: translate('Cancel'), onPressed: close),
        BdButton.primary(label: translate('Continue'), onPressed: submit),
      ],
    );
  });
  controller.dispose();
}

Map<String, dynamic> jsonDecodeOptions(String raw) {
  try {
    final v = jsonDecode(raw);
    if (v is Map<String, dynamic>) return v;
  } catch (_) {}
  return {};
}

/// Join links whose question is open. A link that starts the app arrives
/// twice, from uni_links and from the start arguments, and is asked once.
final Set<String> _joinLinksAsked = {};

/// A neodesk://join link opens a question naming the server before the
/// computer joins it (plain HTTP links also carry the warning). Support
/// links and anything else go straight to [handle].
Future<void> confirmOnboardingLink(
    String link, void Function(String link) handle) async {
  final input = InviteInput.parse(link);
  if (input.kind != InviteKind.joinLink) {
    handle(link);
    return;
  }
  if (!_joinLinksAsked.add(link)) return;
  try {
    await _askBeforeJoining(input, link, handle);
  } finally {
    _joinLinksAsked.remove(link);
  }
}

Future<void> _askBeforeJoining(
    InviteInput input, String link, void Function(String link) handle) async {
  // Started by the link: wait until the window has its first frame.
  for (var i = 0; i < 50 && globalKey.currentContext == null; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  if (isDesktop) {
    try {
      await windowManager.show();
      await windowManager.focus();
    } catch (_) {}
  }
  final host = input.host ?? '';
  final ok = await showBdDialog<bool>((close, _) {
    final t = globalKey.currentContext!.bdText;
    return BdDialog(
      title: tr('bd-join-link-title', [host]),
      width: 480,
      onClose: () => close(false),
      closeTooltip: translate('Close'),
      children: [
        Text(tr('bd-join-link-text', [host]), style: t.body),
        if (input.isPlainHttp)
          BdNotice(
              tone: BdTone.warning, text: tr('bd-invite-insecure', [host])),
      ],
      actions: [
        BdButton(label: translate('Cancel'), onPressed: () => close(false)),
        BdButton.primary(
            label: input.isPlainHttp ? tr('bd-continue-anyway') : tr('bd-join'),
            onPressed: () => close(true)),
      ],
    );
  });
  if (ok == true) handle(link);
}
