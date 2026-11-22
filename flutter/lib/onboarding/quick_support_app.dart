import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/widgets/bd/bd.dart';
import 'package:flutter_hbb/common/widgets/bd/bd_dialog_host.dart';
import 'package:flutter_hbb/common/widgets/branding_logo.dart';
import 'package:flutter_hbb/models/branding_model.dart';
import 'package:window_manager/window_manager.dart';

import 'onboarding_service.dart';
import 'quick_support_view.dart';

const kQuickSupportWindowSize = Size(480, 560);

/// The bar window: wide enough for the bar and its shadow.
const _kBarWindow = Size(560, 64);
const _kBarWindowChat = Size(560, 64 + 8 + 400);

/// The quick support app in the main window: the 480 x 560 window with the
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
  bool _chat = false;
  int _seenMessages = 0;

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
    // A new chat message opens the panel.
    final fromSupporter = s.messages.where((m) => m.fromSupporter).length;
    final newMessage = fromSupporter > _seenMessages;
    _seenMessages = fromSupporter;
    setState(() {
      _state = s;
      if (wantBar && newMessage) _chat = true;
      if (!wantBar) _chat = false;
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
        await windowManager.setSize(_chat ? _kBarWindowChat : _kBarWindow);
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
      final ok = await showBdDialog<bool>((close, _) => BdDialog(
            title: tr('bd-qs-end-confirm', [name]),
            width: 400,
            onClose: () => close(false),
            closeTooltip: translate('Close'),
            children: const [],
            actions: [
              BdButton(label: translate('Cancel'), onPressed: () => close(false)),
              BdButton(
                  label: tr('bd-end-session'),
                  kind: BdButtonKind.danger,
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
                chatOpen: _chat,
                onDrag: () => windowManager.startDragging(),
                onChat: () {
                  setState(() => _chat = !_chat);
                  _applyWindow();
                },
                onStop: () => widget.service.endSupport(),
              ),
              if (_chat) ...[
                const SizedBox(height: 8),
                SessionChatPanel(
                  state: _state,
                  onSend: widget.service.sendChat,
                  onClose: () {
                    setState(() => _chat = false);
                    _applyWindow();
                  },
                ),
              ],
            ],
          ),
        ),
      );
    }
    return BdWindowFrame(
      titleBar: GestureDetector(
        onPanStart: (_) => windowManager.startDragging(),
        child: BdTitleBar(
          height: 36,
          brand: BdTitleBrand(title: tr('bd-qs-window-title')),
          controls: BdWindowControls(
            height: 36,
            onMinimize: () => windowManager.minimize(),
            onClose: _close,
          ),
        ),
      ),
      child: QuickSupportView(
        state: _state,
        logo: _logo(),
        onAllow: () => widget.service.consent(true),
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
