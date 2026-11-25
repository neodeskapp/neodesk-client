import 'dart:async';

import 'package:flutter/foundation.dart' show mapEquals;
import 'package:flutter/material.dart';

/// What the Server page shows of this computer's server: the options with
/// the addresses and key, and whether the service is connected to it.
class ServerReading {
  const ServerReading({required this.options, required this.connected});
  final Map<String, dynamic> options;
  final bool connected;

  /// Whether [other] shows the same, so the page needs no new frame.
  bool sameAs(ServerReading? other) =>
      other != null &&
      other.connected == connected &&
      mapEquals(other.options, options);
}

/// Whether a connect status (main_get_connect_status) says the service is
/// connected, as Home reads it: status_num 1.
bool connectedOf(Map<String, dynamic> status) => status['status_num'] == 1;

/// The Server page's summary, built from [read] and read again every
/// [interval] while it shows, so a join or a change of the server's answer
/// shows without leaving Settings (L466). Home reads the same connect
/// status every second.
class LiveServerReading extends StatefulWidget {
  const LiveServerReading({
    super.key,
    required this.read,
    required this.builder,
    this.interval = const Duration(seconds: 1),
  });

  final Future<ServerReading> Function() read;
  final Widget Function(BuildContext context, ServerReading reading) builder;
  final Duration interval;

  @override
  State<LiveServerReading> createState() => _LiveServerReadingState();
}

class _LiveServerReadingState extends State<LiveServerReading> {
  ServerReading? _reading;
  Timer? _timer;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _read();
    _timer = Timer.periodic(widget.interval, (_) => _read());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _read() async {
    if (_busy) return;
    _busy = true;
    try {
      final r = await widget.read();
      // A new frame only when something changed: a rebuild every second
      // redraws the window, which costs about a tenth of a core without a
      // GPU (L529)
      if (mounted && !r.sameAs(_reading)) setState(() => _reading = r);
    } finally {
      _busy = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _reading;
    return r == null ? const SizedBox.shrink() : widget.builder(context, r);
  }
}
