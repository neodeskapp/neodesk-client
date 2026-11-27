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

/// The quick support app in the main window: the 480 x 720 window with the
/// consent and status screens. During the session the connection window
/// (the --cm process, the same as in the full client) is the bar at the top
/// of the screen, so this window hides and comes back for the end
/// (DESIGN.md, Quick support app).
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
  bool _hidden = false;

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
    setState(() => _state = s);
    if ((s.accentHex ?? '').isNotEmpty) {
      BrandingModel.current.accentColor.value = s.accentHex!;
    }
    // While the supporter is connected the connection window is the bar
    final hide = s.phase == OnboardingPhase.supportInSession;
    if (hide == _hidden) return;
    _hidden = hide;
    try {
      if (hide) {
        await windowManager.hide();
      } else {
        await windowManager.show();
        await windowManager.focus();
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
        onFeedback: widget.service.sendFeedback,
        onRetry: () {
          final link = _state.link;
          if (link != null) widget.service.redeemSupport(link);
        },
      ),
    );
  }
}
