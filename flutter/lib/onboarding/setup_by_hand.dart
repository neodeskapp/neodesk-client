import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart' show translate;
import 'package:flutter_hbb/common/widgets/bd/bd.dart';

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
    final t = context.bdText;
    final enabled = !widget.locked && !_busy;
    return BdDialog(
      title: tr('bd-set-up-by-hand'),
      width: 520,
      onClose: widget.onCancel,
      closeTooltip: translate('Close'),
      children: [
        Text(tr('bd-hand-text'), style: t.body.copyWith(
            fontSize: 15, height: 22 / 15, color: context.bd.textMuted)),
        BdField(
          label: tr('bd-hand-server'),
          hint: tr('bd-hand-server-hint'),
          error: _errors.idServer,
          controller: _id,
          enabled: enabled,
          large: true,
          autofocus: true,
          onSubmitted: (_) => _save(),
        ),
        BdField(
          label: tr('bd-hand-key'),
          hint: tr('bd-hand-key-hint'),
          error: _errors.key,
          controller: _key,
          enabled: enabled,
          large: true,
          mono: true,
          onSubmitted: (_) => _save(),
        ),
        BdDisclosure(
          label: tr('bd-hand-more'),
          open: _more,
          onToggle: () => setState(() => _more = !_more),
          child: Column(children: [
            BdField(
              label: tr('bd-hand-relay'),
              hint: tr('bd-hand-relay-hint'),
              error: _errors.relayServer,
              controller: _relay,
              enabled: enabled,
            ),
            const SizedBox(height: 16),
            BdField(
              label: tr('bd-hand-api'),
              hint: tr('bd-hand-relay-hint'),
              error: _errors.apiServer,
              controller: _api,
              enabled: enabled,
            ),
          ]),
        ),
      ],
      actions: [
        BdButton(label: translate('Cancel'), onPressed: widget.onCancel),
        BdButton.primary(
            label: tr('bd-save'), onPressed: enabled ? _save : null),
      ],
    );
  }
}
