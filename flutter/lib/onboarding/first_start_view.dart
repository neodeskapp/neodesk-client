import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common.dart' show translate;
import 'package:flutter_hbb/common/widgets/bd/bd.dart';

import 'onboarding_service.dart';

/// The sentence for an onboarding error. [server] fills "Can't reach ...".
String onboardingErrorText(OnboardingError kind, String? server) {
  switch (kind) {
    case OnboardingError.notAnInvite:
      return tr('bd-invite-error-not-invite');
    case OnboardingError.expired:
      return tr('bd-invite-error-expired');
    case OnboardingError.usedUp:
      return tr('bd-invite-error-used');
    case OnboardingError.unreachable:
      return tr('bd-invite-error-unreachable',
          [server ?? tr('bd-the-server')]);
    case OnboardingError.tooManyTries:
      return tr('bd-invite-error-too-many');
    case OnboardingError.insecureHttp:
      return tr('bd-invite-insecure', [server ?? '']);
    case OnboardingError.other:
      return tr('bd-invite-error-other');
  }
}

/// First start without a server: one task, paste the invite.
class FirstStartView extends StatefulWidget {
  const FirstStartView({
    super.key,
    required this.service,
    required this.onSetUpByHand,
    this.initialText,
  });

  final OnboardingService service;
  final VoidCallback onSetUpByHand;
  final String? initialText;

  @override
  State<FirstStartView> createState() => _FirstStartViewState();
}

class _FirstStartViewState extends State<FirstStartView> {
  late final _input = TextEditingController(text: widget.initialText);
  final _server = TextEditingController();
  final _inputFocus = FocusNode();
  final _serverFocus = FocusNode();
  StreamSubscription<OnboardingState>? _sub;
  OnboardingError? _error;
  String? _errorServer;
  bool _confirmInsecure = false;
  bool _busy = false;

  InviteInput get _parsed => InviteInput.parse(_input.text);

  @override
  void initState() {
    super.initState();
    final s = widget.service.current;
    if (s.phase == OnboardingPhase.notSetUp && s.errorKind != null) {
      _error = s.errorKind;
      _errorServer = s.server;
    }
    _sub = widget.service.states.listen((s) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        if (s.phase == OnboardingPhase.notSetUp) {
          _error = s.errorKind;
          _errorServer = s.server;
        }
      });
    });
    if (widget.initialText == null) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _inputFocus.requestFocus());
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _input.dispose();
    _server.dispose();
    _inputFocus.dispose();
    _serverFocus.dispose();
    super.dispose();
  }

  bool get _canContinue {
    final p = _parsed;
    if (_busy || p.kind == InviteKind.empty) return false;
    if (p.needsServer && _server.text.trim().isEmpty) return false;
    return true;
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) return;
    _input.text = text;
    _input.selection = TextSelection.collapsed(offset: text.length);
    setState(() => _error = null);
  }

  Future<void> _submit({bool insecureOk = false}) async {
    if (!_canContinue) return;
    final p = _parsed;
    if (p.kind == InviteKind.invalid) {
      setState(() => _error = OnboardingError.notAnInvite);
      return;
    }
    if (p.isPlainHttp && !insecureOk) {
      setState(() {
        _confirmInsecure = true;
        _errorServer = p.host;
      });
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _confirmInsecure = false;
    });
    if (p.kind == InviteKind.supportLink) {
      await widget.service.redeemSupport(_input.text.trim());
    } else if (p.needsServer) {
      final host = _server.text.trim().replaceFirst(RegExp(r'^https?://'), '')
          .replaceAll(RegExp(r'/+$'), '');
      await widget.service.redeemJoin('https://$host/join/${p.displayCode}');
    } else {
      await widget.service.redeemJoin(_input.text.trim());
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.bd;
    final t = context.bdText;
    final p = _parsed;
    final errorText =
        _error == null ? null : onboardingErrorText(_error!, _errorServer);
    final column = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(tr('bd-first-start-title'), style: t.display),
        const SizedBox(height: 12),
        ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Text(tr('bd-first-start-lead'), style: t.lead)),
        const SizedBox(height: 32),
        BdField(
          label: tr('bd-invite-field'),
          controller: _input,
          focusNode: _inputFocus,
          large: true,
          mono: true,
          hint: tr('bd-invite-hint'),
          error: errorText,
          onChanged: (_) => setState(() {
            _error = null;
            _confirmInsecure = false;
          }),
          onSubmitted: (_) {
            if (p.needsServer && _server.text.trim().isEmpty) {
              setState(() {});
              _serverFocus.requestFocus();
            } else {
              _submit();
            }
          },
          trailing: BdButton(
              label: translate('Paste'),
              size: BdButtonSize.sm,
              onPressed: _busy ? null : _paste),
        ),
        if (p.needsServer) ...[
          const SizedBox(height: 20),
          BdField(
            label: tr('bd-invite-server-field'),
            controller: _server,
            focusNode: _serverFocus,
            large: true,
            hint: tr('bd-invite-server-hint'),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _submit(),
          ),
        ],
        if (_confirmInsecure) ...[
          const SizedBox(height: 20),
          BdNotice(
            tone: BdTone.warning,
            text: tr('bd-invite-insecure', [_errorServer ?? p.host ?? '']),
          ),
          const SizedBox(height: 16),
          Row(children: [
            BdButton(
                label: tr('bd-continue-anyway'),
                size: BdButtonSize.lg,
                onPressed: () => _submit(insecureOk: true)),
            const SizedBox(width: 8),
            BdButton(
                label: translate('Cancel'),
                size: BdButtonSize.lg,
                kind: BdButtonKind.ghost,
                onPressed: () => setState(() => _confirmInsecure = false)),
          ]),
        ] else ...[
          const SizedBox(height: 20),
          BdButton.primary(
            label: translate('Continue'),
            size: BdButtonSize.lg,
            onPressed: _canContinue ? () => _submit() : null,
          ),
        ],
      ],
    );

    final bottom = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        BdButton.link(
            label: tr('bd-set-up-by-hand'), onPressed: widget.onSetUpByHand),
        const SizedBox(height: 6),
        Text(tr('bd-set-up-by-hand-hint'), style: t.small),
      ],
    );

    return LayoutBuilder(builder: (context, box) {
      // The mark's shapes at 350 px a square, running off the right and
      // bottom edges. Below 1100 wide they keep their place and get cut.
      const unit = 350 / 32;
      const size = 44 * unit;
      final left = (box.maxWidth - 431).clamp(669.0, double.infinity);
      return Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          Positioned(
            left: left,
            top: box.maxHeight - 474,
            width: size,
            height: size,
            child: IgnorePointer(
              child: CustomPaint(
                painter: BdMarkPainter(
                    c.logoSquare, c.logoCircle, c.logoOverlap,
                    unit: unit),
              ),
            ),
          ),
          Positioned.fill(
            child: SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: box.maxHeight),
                child: IntrinsicHeight(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 72, right: 32),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Spacer(flex: 6),
                        const SizedBox(height: 50),
                        SizedBox(width: 452, child: column),
                        const SizedBox(height: 32),
                        const Spacer(flex: 5),
                        SizedBox(width: 452, child: bottom),
                        const SizedBox(height: 36),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    });
  }
}
