// The status line of Home: what the service and the server say about this
// computer, in the order that tells the person what is true.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common/widgets/nd/nd.dart';
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

  /// Connections to this computer are paused (the option stop-service).
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
  VoidCallback? onStartService,
}) {
  final server = facts.server;
  if (facts.serviceStopped) {
    return HomeStatus(NdStatusKind.offline, tr('nd-home-status-paused'),
        linkLabel: tr('nd-home-accept'), onLink: onTurnOn);
  }
  if (facts.noServer) {
    return HomeStatus(NdStatusKind.bad, tr('nd-home-status-no-server'),
        linkLabel: tr('nd-set-up-by-hand'), onLink: onSetUp);
  }
  final standing = _standingOf(facts.standing);
  final said = standing['reason'] as String? ?? '';
  String withReason(String text) => said.isEmpty
      ? text
      : '$text ${tr('nd-home-status-server-says', [said])}';
  if (standing['banned'] == true) {
    return HomeStatus(
        NdStatusKind.bad, withReason(tr('nd-home-status-banned', [server])));
  }
  if (standing['enrollment'] == 'rejected') {
    return HomeStatus(
        NdStatusKind.bad, withReason(tr('nd-home-status-removed', [server])));
  }
  if (standing['signal'] == 'refused') {
    return HomeStatus(
        NdStatusKind.bad, tr('nd-home-status-key-refused', [server]));
  }
  if (facts.status == SvcStatus.ready) {
    return HomeStatus(NdStatusKind.good, tr('nd-home-status-ready', [server]));
  }
  if (standing['enrollment'] == 'pending' ||
      standing['signal'] == 'pending' ||
      facts.reason == 'deployment_required') {
    return HomeStatus(NdStatusKind.wait, tr('nd-home-status-approval'));
  }
  if (facts.reason == 'ipc_disconnected') {
    // The window of an installed client waits for its service, which holds
    // this computer's key, and offers to start it.
    return HomeStatus(NdStatusKind.bad, tr('nd-home-status-no-service'),
        linkLabel: onStartService == null ? null : tr('nd-home-start-service'),
        onLink: onStartService);
  }
  if (facts.status == SvcStatus.connecting) {
    return HomeStatus(
        NdStatusKind.wait, tr('nd-home-status-connecting', [server]));
  }
  return HomeStatus(NdStatusKind.bad, tr('nd-home-status-offline', [server]),
      linkLabel: tr('nd-home-try-now'), onLink: onTryNow);
}
