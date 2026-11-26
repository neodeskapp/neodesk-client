import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart'
    show isMacOS, isWeb, isWindows, translate;
import 'package:flutter_hbb/common/widgets/nd/nd.dart';
import 'package:flutter_hbb/models/platform_model.dart' show bind;

/// The answer of the core's update check (main_get_common "nd-update-check"):
/// a newer release, none, or why the check failed.
class UpdateCheckResult {
  const UpdateCheckResult._({this.version, this.url, this.error});

  /// The newer release's version (1.5.0-rc.9), when there is one.
  final String? version;

  /// Its release page.
  final String? url;

  /// Why the check failed.
  final String? error;

  bool get hasUpdate => version != null && url != null;

  /// [answer] is `{"version": ..., "url": ...}`, empty for no newer
  /// release, or `error:<reason>`.
  factory UpdateCheckResult.parse(String answer) {
    if (answer.startsWith('error:')) {
      return UpdateCheckResult._(error: answer.substring('error:'.length));
    }
    if (answer.trim().isEmpty) return const UpdateCheckResult._();
    try {
      final data = jsonDecode(answer);
      final version = data['version'];
      final url = data['url'];
      if (version is String && url is String && version.isNotEmpty) {
        return UpdateCheckResult._(version: version, url: url);
      }
    } catch (_) {}
    return UpdateCheckResult._(error: answer);
  }

  /// The line About shows after the check.
  String message() {
    if (error != null) return tr('nd-about-check-failed', [error!]);
    if (hasUpdate) return tr('nd-about-new', [version!]);
    return tr('nd-about-latest');
  }

  /// The button for a newer release: Update to <version> where NeoDesk
  /// installs it itself ([canInstall]), Download <version> elsewhere.
  String? actionLabel({required bool canInstall}) {
    if (!hasUpdate) return null;
    return tr(canInstall ? 'nd-about-update' : 'nd-about-download', [version!]);
  }
}

/// Whether this NeoDesk installs a downloaded update itself: the installed
/// app on Windows and macOS. Portable and Linux builds get the release page.
bool canInstallUpdates() =>
    (isWindows || isMacOS) && bind.mainIsInstalled();

/// The plain NeoDesk Client build, the one the desktop releases update.
bool isUpdatableBuild() =>
    !isWeb && bind.mainGetCommonSync(key: 'nd-update-build') == 'true';

/// The version of a release page URL
/// (.../releases/tag/desktop-v1.5.0-rc.9 is 1.5.0-rc.9).
String versionOfReleaseUrl(String url) {
  final tag = url.split('/').lastWhere((part) => part.isNotEmpty, orElse: () => '');
  return tag.startsWith('desktop-v') ? tag.substring('desktop-v'.length) : tag;
}

/// The home screen's notice that a newer release is out, with its release
/// notes, Update (or Download) and a close button.
class UpdateNotice extends StatelessWidget {
  const UpdateNotice({
    super.key,
    required this.version,
    required this.canInstall,
    required this.onAction,
    required this.onWhatsNew,
    required this.onClose,
  });

  final String version;
  final bool canInstall;
  final VoidCallback onAction;
  final VoidCallback onWhatsNew;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return NdNotice(
      tone: NdTone.info,
      text: tr('nd-update-notice', [version]),
      action: Row(mainAxisSize: MainAxisSize.min, children: [
        NdButton.link(label: tr('nd-update-whats-new'), onPressed: onWhatsNew),
        const SizedBox(width: 12),
        NdButton(
            label: translate(canInstall ? 'Update' : 'Download'),
            size: NdButtonSize.sm,
            onPressed: onAction),
        const SizedBox(width: 4),
        NdIconButton(
            icon: NdIcons.close, tooltip: translate('Close'), onPressed: onClose),
      ]),
    );
  }
}
