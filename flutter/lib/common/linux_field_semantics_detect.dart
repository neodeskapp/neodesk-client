import 'dart:io';

typedef HideRule = bool Function(
    {required bool linux, required String desktop, required bool screenReaderOn});

bool detect(HideRule rule) {
  if (!Platform.isLinux) return false;
  final env = Platform.environment;
  final desktop =
      '${env['XDG_CURRENT_DESKTOP'] ?? ''}:${env['DESKTOP_SESSION'] ?? ''}';
  // Only ask about the screen reader where the answer matters.
  if (!rule(linux: true, desktop: desktop, screenReaderOn: false)) {
    return false;
  }
  return rule(linux: true, desktop: desktop, screenReaderOn: _screenReaderOn());
}

bool _screenReaderOn() {
  try {
    final r = Process.runSync('gsettings', [
      'get',
      'org.gnome.desktop.a11y.applications',
      'screen-reader-enabled'
    ]);
    if ('${r.stdout}'.trim() == 'true') return true;
  } catch (_) {}
  try {
    if (Process.runSync('pgrep', ['-x', 'orca']).exitCode == 0) return true;
  } catch (_) {}
  return false;
}
