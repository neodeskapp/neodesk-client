import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/widgets/nd/nd.dart';
import 'package:flutter_hbb/common/widgets/nd/nd_dialog_host.dart';
import 'package:flutter_hbb/common/widgets/branding_logo.dart';
import 'package:flutter_hbb/models/branding_model.dart';
import 'package:window_manager/window_manager.dart';

import 'onboarding_service.dart';
import 'quick_support_view.dart';

const kQuickSupportWindowSize = Size(480, 720);

/// The bar window: wide enough for the bar and its shadow, and taller with
/// the chat or the files open under it.
const _kBarWindow = Size(760, 64);
const _kBarWindowPanel = Size(760, 64 + 8 + 400);

/// What shows under the session bar.
enum _Panel { none, chat, files }

/// The quick support app in the main window: the 480 x 720 window with the
/// consent and status screens, and during the session the bar at the top of
/// the screen. The window itself becomes the bar, so it hides while the bar
/// shows (DESIGN.md, Quick support app).
class QuickSupportWindow extends StatefulWidget {
  const QuickSupportWindow({super.key, required this.service});
  final OnboardingService service;

  @override
  State<QuickSupportWindow> createState() => _QuickSupportWindowState();
}

class _QuickSupportWindowState extends State<QuickSupportWindow>
    with WindowListener {
  StreamSubscription<OnboardingState>? _sub;
  late OnboardingState _state = widget.service.current;
  bool _bar = false;
  _Panel _panel = _Panel.none;
  int _seenMessages = 0;
  int _seenFiles = 0;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    windowManager.setPreventClose(true);
    _sub = widget.service.states.listen(_onState);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onState(_state));
  }

  @override
  void dispose() {
    _sub?.cancel();
    windowManager.removeListener(this);
    super.dispose();
  }

  Future<void> _onState(OnboardingState s) async {
    if (!mounted) return;
    final wantBar = s.phase == OnboardingPhase.supportInSession;
    // A new chat message opens the chat, a file that moves the files.
    final fromSupporter = s.messages.where((m) => m.fromSupporter).length;
    final newMessage = fromSupporter > _seenMessages;
    _seenMessages = fromSupporter;
    final newFile = s.files.length > _seenFiles;
    _seenFiles = s.files.length;
    setState(() {
      _state = s;
      if (wantBar && newMessage) _panel = _Panel.chat;
      if (wantBar && newFile) _panel = _Panel.files;
      if (!wantBar) _panel = _Panel.none;
    });
    if ((s.accentHex ?? '').isNotEmpty) {
      BrandingModel.current.accentColor.value = s.accentHex!;
    }
    if (wantBar != _bar) {
      _bar = wantBar;
      await _applyWindow();
    } else if (_bar) {
      await _applyWindow();
    }
  }

  Future<void> _applyWindow() async {
    try {
      if (_bar) {
        await windowManager.setResizable(true);
        await windowManager.setSize(
            _panel == _Panel.none ? _kBarWindow : _kBarWindowPanel);
        await windowManager.setAlwaysOnTop(true);
        await windowManager.setSkipTaskbar(true);
        await windowManager.setAlignment(Alignment.topCenter);
        await windowManager.setResizable(false);
      } else {
        await windowManager.setAlwaysOnTop(false);
        await windowManager.setSkipTaskbar(false);
        await windowManager.setResizable(true);
        await windowManager.setSize(kQuickSupportWindowSize);
        await windowManager.setAlignment(Alignment.center);
        await windowManager.setResizable(false);
      }
    } catch (e) {
      debugPrint('quick support window: $e');
    }
  }

  bool get _connected =>
      _state.phase == OnboardingPhase.supportWaiting ||
      _state.phase == OnboardingPhase.supportInSession;

  @override
  void onWindowClose() => _close();

  /// Closing ends the session; while connected it asks first.
  Future<void> _close() async {
    if (_connected) {
      final name = (_state.supporterName ?? '').trim();
      final ok = await showNdDialog<bool>((close, _) => NdDialog(
            title: tr('nd-qs-end-confirm', [name]),
            width: 400,
            onClose: () => close(false),
            closeTooltip: translate('Close'),
            children: const [],
            actions: [
              NdButton(label: translate('Cancel'), onPressed: () => close(false)),
              NdButton(
                  label: tr('nd-end-session'),
                  kind: NdButtonKind.danger,
                  onPressed: () => close(true)),
            ],
          ));
      if (ok != true) return;
    }
    if (_connected ||
        _state.phase == OnboardingPhase.supportConsent ||
        _state.phase == OnboardingPhase.supportConnecting) {
      await widget.service.endSupport();
    }
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
    exit(0);
  }

  /// Opens [panel] under the bar, or closes it when it is open.
  void _toggle(_Panel panel) {
    setState(() => _panel = _panel == panel ? _Panel.none : panel);
    _applyWindow();
  }

  Widget? _logo() {
    final b = BrandingModel.current;
    if (!b.hasLogo.value || b.logoPath.value.isEmpty) return null;
    return BrandingLogoImage(
      path: b.logoPath.value,
      cacheKey: 'branding-qs-${b.logoPath.value}-${b.logoEpoch.value}',
      maxHeight: 26,
      fit: BoxFit.contain,
      alignment: Alignment.center,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_bar) {
      return Material(
        type: MaterialType.transparency,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SessionBar(
                state: _state,
                chatOpen: _panel == _Panel.chat,
                onDrag: () => windowManager.startDragging(),
                onChat: () => _toggle(_Panel.chat),
                onFiles: () => _toggle(_Panel.files),
                onStop: () => widget.service.endSupport(),
              ),
              if (_panel == _Panel.chat) ...[
                const SizedBox(height: 8),
                SessionChatPanel(
                  state: _state,
                  onSend: widget.service.sendChat,
                  onClose: () => _toggle(_Panel.none),
                ),
              ],
              if (_panel == _Panel.files) ...[
                const SizedBox(height: 8),
                SessionFilesPanel(
                  state: _state,
                  onClose: () => _toggle(_Panel.none),
                ),
              ],
            ],
          ),
        ),
      );
    }
    return NdWindowFrame(
      titleBar: GestureDetector(
        onPanStart: (_) => windowManager.startDragging(),
        child: NdTitleBar(
          height: 36,
          brand: NdTitleBrand(title: tr('nd-qs-window-title')),
          controls: NdWindowControls(
            height: 36,
            onMinimize: () => windowManager.minimize(),
            onClose: _close,
          ),
        ),
      ),
      child: QuickSupportView(
        state: _state,
        logo: _logo(),
        onAllow: (grants) => widget.service.consent(true, grants),
        onDecline: () => widget.service.consent(false),
        onCancel: () => widget.service.endSupport(),
        onClose: _close,
        onRetry: () {
          final link = _state.link;
          if (link != null) widget.service.redeemSupport(link);
        },
      ),
    );
  }
}
