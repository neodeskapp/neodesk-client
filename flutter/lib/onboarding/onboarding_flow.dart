import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/widgets/nd/nd.dart';
import 'package:flutter_hbb/common/widgets/nd/nd_dialog_host.dart';
import 'package:flutter_hbb/common/widgets/branding_logo.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/desktop/pages/desktop_setting_page.dart';
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
  const OnboardingFlow({
    super.key,
    required this.service,
    required this.onFinished,
    this.onSetUpByHand = openServerSetup,
  });

  final OnboardingService service;

  /// Done on the joined screen, and when the hand setup takes over.
  final VoidCallback onFinished;

  /// Where Set up by hand leads: the Server settings.
  final VoidCallback onSetUpByHand;

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
        // A join from the setup screen of Try another code shows its own
        // progress and result.
        if (s.phase == OnboardingPhase.joining ||
            s.phase == OnboardingPhase.joinFailed) {
          _retry = false;
        }
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

  /// Leaves a failed join behind, so that Back from the settings shows
  /// Home once a server is set, and the first start otherwise.
  void _setUpByHand() {
    widget.service.dismissFailedJoin();
    widget.onFinished();
    widget.onSetUpByHand();
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
        onSetUpByHand: _setUpByHand,
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
        onSetUpByHand: _setUpByHand,
        onTryAgain: (s.link ?? '').isEmpty
            ? null
            : () => widget.service.redeemJoin(s.link!),
      );
    });
  }
}

/// Counts the servers saved by hand, so pages that show the server read it
/// again.
final handSetupSaved = 0.obs;

/// Set up by hand from the first start: Settings opens at Server in place of
/// Home, with the hand setup over it. Back leads to Home once a server is
/// set. Without the Server settings only the hand setup opens.
void openServerSetup() {
  if (!DesktopSettingPage.tabKeys.contains(SettingsTabKey.network)) {
    showSetupByHand();
    return;
  }
  DesktopSettingPage.switch2page(SettingsTabKey.network);
  WidgetsBinding.instance.addPostFrameCallback((_) => showSetupByHand());
}

/// The hand setup dialog with today's server settings, saved through
/// setServerConfig (the same checks as the old ID/Relay Server dialog).
Future<void> showSetupByHand() async {
  final options = jsonDecodeOptions(await bind.mainGetOptions());
  final current = ServerConfig.fromOptions(options);
  final locked = isOptionFixed('custom-rendezvous-server') ||
      bind.mainGetBuildinOption(key: kOptionHideServerSetting) == 'Y';
  await showNdDialog<void>((close, setState) => SetupByHandDialog(
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
            handSetupSaved.value++;
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

/// Join a server from Settings: the first-start fields in a dialog, the
/// server address once the text is a bare code (filled with the console of
/// an earlier join, [knownConsole]). When the computer already has a
/// server, it first asks to leave it. The dialog stays until the join ends:
/// it closes once the computer joined and shows why when the join failed.
Future<void> showJoinServerDialog(OnboardingService service,
    {required String currentServer, String knownConsole = ''}) async {
  await showNdDialog<void>((close, _) => _JoinServerDialog(
        service: service,
        currentServer: currentServer,
        knownConsole: knownConsole,
        close: close,
      ));
}

/// The end of the join [service] just started: its state once it is no
/// longer joining.
Future<OnboardingState> joinOutcome(OnboardingService service) {
  final now = service.current;
  if (now.phase != OnboardingPhase.joining) return Future.value(now);
  return service.states.firstWhere((s) => s.phase != OnboardingPhase.joining);
}

class _JoinServerDialog extends StatefulWidget {
  const _JoinServerDialog({
    required this.service,
    required this.currentServer,
    required this.knownConsole,
    required this.close,
  });

  final OnboardingService service;
  final String currentServer;
  final String knownConsole;
  final VoidCallback close;

  @override
  State<_JoinServerDialog> createState() => _JoinServerDialogState();
}

class _JoinServerDialogState extends State<_JoinServerDialog> {
  final _invite = TextEditingController();
  late final _server = TextEditingController(text: widget.knownConsole);
  String? _error;
  String? _serverError;

  /// The server of the join that runs, null while none runs.
  String? _joining;
  OnboardingState? _failed;

  @override
  void dispose() {
    _invite.dispose();
    _server.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_joining != null) return;
    final input = InviteInput.parse(_invite.text);
    if (input.kind == InviteKind.invalid || input.kind == InviteKind.empty) {
      setState(() => _error = tr('nd-invite-error-not-invite'));
      return;
    }
    final text = joinTextFor(_invite.text, _server.text);
    if (text == null) {
      setState(() => _serverError = tr('nd-invite-server-missing'));
      return;
    }
    final currentServer = widget.currentServer;
    final newHost = InviteInput.parse(text).host ?? '';
    if (currentServer.isNotEmpty &&
        newHost.isNotEmpty &&
        newHost != currentServer) {
      final go = await showNdDialog<bool>((c2, _) => NdDialog(
            title: tr('nd-join-leave-title'),
            width: 480,
            onClose: () => c2(false),
            closeTooltip: translate('Close'),
            children: [
              Text(tr('nd-join-leave', [currentServer, newHost]),
                  style: Get.context!.ndText.body),
            ],
            actions: [
              NdButton(label: translate('Cancel'), onPressed: () => c2(false)),
              NdButton.primary(label: tr('nd-join'), onPressed: () => c2(true)),
            ],
          ));
      if (go != true || !mounted) return;
    }
    setState(() {
      _joining = newHost;
      _failed = null;
    });
    await widget.service.redeemJoin(text);
    final outcome = await joinOutcome(widget.service);
    if (!mounted) return;
    if (outcome.phase == OnboardingPhase.joined) {
      widget.close();
      return;
    }
    setState(() {
      _joining = null;
      _failed = outcome;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.ndText;
    final joining = _joining;
    final failed = _failed;
    return NdDialog(
      title: tr('nd-join-a-server'),
      width: 520,
      onClose: widget.close,
      closeTooltip: translate('Close'),
      children: [
        NdField(
          label: tr('nd-invite-field'),
          hint: tr('nd-invite-hint'),
          error: _error,
          controller: _invite,
          large: true,
          mono: true,
          autofocus: true,
          enabled: joining == null,
          onChanged: (_) => setState(() => _error = null),
          onSubmitted: (_) => _submit(),
        ),
        if (InviteInput.parse(_invite.text).needsServer)
          NdField(
            label: tr('nd-invite-server-field'),
            hint: tr('nd-invite-server-hint'),
            error: _serverError,
            controller: _server,
            large: true,
            enabled: joining == null,
            onChanged: (_) => setState(() => _serverError = null),
            onSubmitted: (_) => _submit(),
          ),
        if (joining != null)
          Row(children: [
            const NdSpinner(),
            const SizedBox(width: 10),
            Expanded(
                child: Text(tr('nd-join-progress-title', [joining]),
                    style: t.body)),
          ]),
        if (failed != null) ...[
          NdNotice(tone: NdTone.danger, text: joinFailedNotice(failed)),
          Text(joinFailedNext(failed), style: t.body),
        ],
      ],
      actions: [
        NdButton(label: translate('Cancel'), onPressed: widget.close),
        NdButton.primary(
            label: translate('Continue'),
            onPressed: joining == null ? _submit : null),
      ],
    );
  }
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
  final ok = await showNdDialog<bool>((close, _) {
    final t = globalKey.currentContext!.ndText;
    return NdDialog(
      title: tr('nd-join-link-title', [host]),
      width: 480,
      onClose: () => close(false),
      closeTooltip: translate('Close'),
      children: [
        Text(tr('nd-join-link-text', [host]), style: t.body),
        if (input.isPlainHttp)
          NdNotice(
              tone: NdTone.warning, text: tr('nd-invite-insecure', [host])),
      ],
      actions: [
        NdButton(label: translate('Cancel'), onPressed: () => close(false)),
        NdButton.primary(
            label: input.isPlainHttp ? tr('nd-continue-anyway') : tr('nd-join'),
            onPressed: () => close(true)),
      ],
    );
  });
  if (ok == true) handle(link);
}
