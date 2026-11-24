import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common.dart' show translate;
import 'package:flutter_hbb/common/widgets/nd/nd.dart';

import 'onboarding_service.dart';

/// The sentence for an onboarding error. [server] fills "Can't reach ...".
String onboardingErrorText(OnboardingError kind, String? server) {
  switch (kind) {
    case OnboardingError.notAnInvite:
      return tr('nd-invite-error-not-invite');
    case OnboardingError.expired:
      return tr('nd-invite-error-expired');
    case OnboardingError.usedUp:
      return tr('nd-invite-error-used');
    case OnboardingError.unreachable:
      return tr('nd-invite-error-unreachable',
          [server ?? tr('nd-the-server')]);
    case OnboardingError.tooManyTries:
      return tr('nd-invite-error-too-many');
    case OnboardingError.insecureHttp:
      return tr('nd-invite-insecure', [server ?? '']);
    case OnboardingError.refused:
      return tr('nd-join-failed-lead-refused');
    case OnboardingError.other:
      return tr('nd-invite-error-other');
  }
}

/// The join link for a bare [code] and the [server] typed next to it. The
/// scheme and port stay as typed; a server without scheme gets https.
String joinLinkFor(String server, String code) {
  final typed = server.trim().replaceAll(RegExp(r'/+$'), '');
  final base = RegExp(r'^https?://', caseSensitive: false).hasMatch(typed)
      ? typed
      : 'https://$typed';
  return '$base/join/$code';
}

/// What a join of [typed] redeems: a link as it is, a bare code at the
/// [server] typed next to it. Null for a code without a server.
String? joinTextFor(String typed, String server) {
  final input = InviteInput.parse(typed);
  if (!input.needsServer) return typed.trim();
  if (server.trim().isEmpty) return null;
  return joinLinkFor(server, input.displayCode ?? '');
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
      await widget.service
          .redeemJoin(joinLinkFor(_server.text, p.displayCode ?? ''));
    } else {
      await widget.service.redeemJoin(_input.text.trim());
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.nd;
    final t = context.ndText;
    final p = _parsed;
    final errorText =
        _error == null ? null : onboardingErrorText(_error!, _errorServer);
    final column = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(tr('nd-first-start-title'), style: t.display),
        const SizedBox(height: 12),
        ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Text(tr('nd-first-start-lead'), style: t.lead)),
        const SizedBox(height: 32),
        NdField(
          label: tr('nd-invite-field'),
          controller: _input,
          focusNode: _inputFocus,
          large: true,
          mono: true,
          hint: tr('nd-invite-hint'),
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
          trailing: NdButton(
              label: translate('Paste'),
              size: NdButtonSize.sm,
              onPressed: _busy ? null : _paste),
        ),
        if (p.needsServer) ...[
          const SizedBox(height: 20),
          NdField(
            label: tr('nd-invite-server-field'),
            controller: _server,
            focusNode: _serverFocus,
            large: true,
            hint: tr('nd-invite-server-hint'),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _submit(),
          ),
        ],
        if (_confirmInsecure) ...[
          const SizedBox(height: 20),
          NdNotice(
            tone: NdTone.warning,
            text: tr('nd-invite-insecure', [_errorServer ?? p.host ?? '']),
          ),
          const SizedBox(height: 16),
          Row(children: [
            NdButton(
                label: tr('nd-continue-anyway'),
                size: NdButtonSize.lg,
                onPressed: () => _submit(insecureOk: true)),
            const SizedBox(width: 8),
            NdButton(
                label: translate('Cancel'),
                size: NdButtonSize.lg,
                kind: NdButtonKind.ghost,
                onPressed: () => setState(() => _confirmInsecure = false)),
          ]),
        ] else ...[
          const SizedBox(height: 20),
          NdButton.primary(
            label: translate('Continue'),
            size: NdButtonSize.lg,
            onPressed: _canContinue ? () => _submit() : null,
          ),
        ],
      ],
    );

    final bottom = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        NdButton.link(
            label: tr('nd-set-up-by-hand'), onPressed: widget.onSetUpByHand),
        const SizedBox(height: 6),
        Text(tr('nd-set-up-by-hand-hint'), style: t.small),
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
                painter: NdMarkPainter(
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
