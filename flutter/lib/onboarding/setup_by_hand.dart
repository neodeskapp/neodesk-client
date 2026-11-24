import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart' show translate;
import 'package:flutter_hbb/common/widgets/nd/nd.dart';

/// What the hand setup saves.
class HandSetup {
  const HandSetup({
    required this.idServer,
    required this.key,
    this.relayServer = '',
    this.apiServer = '',
  });

  final String idServer;
  final String key;
  final String relayServer;
  final String apiServer;
}

/// Errors per field after Save; null when the field is fine.
class HandSetupErrors {
  const HandSetupErrors({this.idServer, this.key, this.relayServer, this.apiServer});
  final String? idServer;
  final String? key;
  final String? relayServer;
  final String? apiServer;
  bool get isEmpty =>
      idServer == null && key == null && relayServer == null && apiServer == null;
}

/// Set up by hand: the server address and key from an administrator.
/// Replaces the old ID/Relay Server dialog.
class SetupByHandDialog extends StatefulWidget {
  const SetupByHandDialog({
    super.key,
    required this.initial,
    required this.onSave,
    required this.onCancel,
    this.locked = false,
  });

  final HandSetup initial;

  /// Checks and saves; returns the errors to show, or an empty set.
  final Future<HandSetupErrors> Function(HandSetup) onSave;
  final VoidCallback onCancel;

  /// Fields the server or a built-in option fixes.
  final bool locked;

  @override
  State<SetupByHandDialog> createState() => _SetupByHandDialogState();
}

class _SetupByHandDialogState extends State<SetupByHandDialog> {
  late final _id = TextEditingController(text: widget.initial.idServer);
  late final _key = TextEditingController(text: widget.initial.key);
  late final _relay = TextEditingController(text: widget.initial.relayServer);
  late final _api = TextEditingController(text: widget.initial.apiServer);
  late bool _more = widget.initial.relayServer.isNotEmpty ||
      widget.initial.apiServer.isNotEmpty;
  HandSetupErrors _errors = const HandSetupErrors();
  bool _busy = false;

  @override
  void dispose() {
    _id.dispose();
    _key.dispose();
    _relay.dispose();
    _api.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    final errors = await widget.onSave(HandSetup(
      idServer: _id.text.trim(),
      key: _key.text.trim(),
      relayServer: _relay.text.trim(),
      apiServer: _api.text.trim(),
    ));
    if (!mounted) return;
    setState(() {
      _busy = false;
      _errors = errors;
      if (errors.relayServer != null || errors.apiServer != null) _more = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.ndText;
    final enabled = !widget.locked && !_busy;
    return NdDialog(
      title: tr('nd-set-up-by-hand'),
      width: 520,
      onClose: widget.onCancel,
      closeTooltip: translate('Close'),
      children: [
        Text(tr('nd-hand-text'), style: t.body.copyWith(
            fontSize: 15, height: 22 / 15, color: context.nd.textMuted)),
        NdField(
          label: tr('nd-hand-server'),
          hint: tr('nd-hand-server-hint'),
          error: _errors.idServer,
          controller: _id,
          enabled: enabled,
          large: true,
          autofocus: true,
          onSubmitted: (_) => _save(),
        ),
        NdField(
          label: tr('nd-hand-key'),
          hint: tr('nd-hand-key-hint'),
          error: _errors.key,
          controller: _key,
          enabled: enabled,
          large: true,
          mono: true,
          onSubmitted: (_) => _save(),
        ),
        NdDisclosure(
          label: tr('nd-hand-more'),
          open: _more,
          onToggle: () => setState(() => _more = !_more),
          child: Column(children: [
            NdField(
              label: tr('nd-hand-relay'),
              hint: tr('nd-hand-relay-hint'),
              error: _errors.relayServer,
              controller: _relay,
              enabled: enabled,
            ),
            const SizedBox(height: 16),
            NdField(
              label: tr('nd-hand-api'),
              hint: tr('nd-hand-relay-hint'),
              error: _errors.apiServer,
              controller: _api,
              enabled: enabled,
            ),
          ]),
        ),
      ],
      actions: [
        NdButton(label: translate('Cancel'), onPressed: widget.onCancel),
        NdButton.primary(
            label: tr('nd-save'), onPressed: enabled ? _save : null),
      ],
    );
  }
}
