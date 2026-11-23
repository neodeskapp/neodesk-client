// The status line of Home: what the service and the server say about this
// computer, in the order that tells the person what is true.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common/widgets/bd/bd.dart';
import 'package:flutter_hbb/desktop/pages/home/home_widgets.dart';
import 'package:flutter_hbb/models/state_model.dart' show SvcStatus;

/// What the service reports, as the status line reads it.
class HomeStatusFacts {
  const HomeStatusFacts({
    required this.server,
    required this.status,
    this.reason = '',
    this.standing = '',
    this.serviceStopped = false,
    this.noServer = false,
  });

  /// The server's host, as people know it.
  final String server;

  /// The service's online state: ready only once the signal server took
  /// this computer's key.
  final SvcStatus status;

  /// The status reason of the connect status (deployment_required,
  /// ipc_disconnected, ...).
  final String reason;

  /// The option neodesk-device-standing: what the server last said about
  /// this computer (banned, enrollment, its reason, signal).
  final String standing;

  /// Connections to this computer are turned off.
  final bool serviceStopped;

  /// No server is set up.
  final bool noServer;
}

Map<String, dynamic> _standingOf(String raw) {
  try {
    final value = jsonDecode(raw);
    if (value is Map<String, dynamic>) return value;
  } catch (_) {}
  return const {};
}

/// The status line for [facts]. A computer the signal server took is ready,
/// even while an older answer of the enrollment API still says it waits.
HomeStatus homeStatusOf(
  HomeStatusFacts facts, {
  VoidCallback? onTurnOn,
  VoidCallback? onSetUp,
  VoidCallback? onTryNow,
}) {
  final server = facts.server;
  if (facts.serviceStopped) {
    return HomeStatus(BdStatusKind.offline, tr('bd-home-status-service-off'),
        linkLabel: tr('bd-home-turn-on'), onLink: onTurnOn);
  }
  if (facts.noServer) {
    return HomeStatus(BdStatusKind.bad, tr('bd-home-status-no-server'),
        linkLabel: tr('bd-set-up-by-hand'), onLink: onSetUp);
  }
  final standing = _standingOf(facts.standing);
  final said = standing['reason'] as String? ?? '';
  String withReason(String text) => said.isEmpty
      ? text
      : '$text ${tr('bd-home-status-server-says', [said])}';
  if (standing['banned'] == true) {
    return HomeStatus(
        BdStatusKind.bad, withReason(tr('bd-home-status-banned', [server])));
  }
  if (standing['enrollment'] == 'rejected') {
    return HomeStatus(
        BdStatusKind.bad, withReason(tr('bd-home-status-removed', [server])));
  }
  if (standing['signal'] == 'refused') {
    return HomeStatus(
        BdStatusKind.bad, tr('bd-home-status-key-refused', [server]));
  }
  if (facts.status == SvcStatus.ready) {
    return HomeStatus(BdStatusKind.good, tr('bd-home-status-ready', [server]));
  }
  if (standing['enrollment'] == 'pending' ||
      standing['signal'] == 'pending' ||
      facts.reason == 'deployment_required') {
    return HomeStatus(BdStatusKind.wait, tr('bd-home-status-approval'));
  }
  if (facts.reason == 'ipc_disconnected') {
    return HomeStatus(BdStatusKind.bad, tr('bd-home-status-no-service'));
  }
  if (facts.status == SvcStatus.connecting) {
    return HomeStatus(
        BdStatusKind.wait, tr('bd-home-status-connecting', [server]));
  }
  return HomeStatus(BdStatusKind.bad, tr('bd-home-status-offline', [server]),
      linkLabel: tr('bd-home-try-now'), onLink: onTryNow);
}
