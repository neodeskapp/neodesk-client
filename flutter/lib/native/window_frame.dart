import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart' as win32;

// DWM window attributes of Windows 11 (build 22000 and later). Older
// Windows rejects them and the call does nothing.
const _kDwmwaWindowCornerPreference = 33;
const _kDwmwaBorderColor = 34;
const _kDwmwcpDefault = 0;
const _kDwmwcpDoNotRound = 1;
const _kDwmwaColorNone = 0xFFFFFFFE;
const _kDwmwaColorDefault = 0xFFFFFFFF;

/// The main window of this process: the runner's Flutter window.
int _mainWindow() {
  final cls = 'FLUTTER_RUNNER_WIN32_WINDOW'.toNativeUtf16();
  final pid = calloc<Uint32>();
  try {
    final self = win32.GetCurrentProcessId();
    var hwnd = 0;
    while (true) {
      hwnd = win32.FindWindowEx(0, hwnd, cls, nullptr);
      if (hwnd == 0) return 0;
      win32.GetWindowThreadProcessId(hwnd, pid);
      if (pid.value == self) return hwnd;
    }
  } finally {
    calloc.free(cls);
    calloc.free(pid);
  }
}

void _setDword(int hwnd, int attribute, int value) {
  final p = calloc<Uint32>()..value = value;
  try {
    win32.DwmSetWindowAttribute(hwnd, attribute, p, sizeOf<Uint32>());
  } finally {
    calloc.free(p);
  }
}

/// Turns the border and the rounded corners that Windows 11 draws around
/// the main window off ([plain]) or back on.
///
/// A window that shows only a floating card on a transparent background,
/// like the quick support bar, otherwise gets a thin rounded outline around
/// its whole transparent area.
void setMainWindowPlain(bool plain) {
  if (!Platform.isWindows) return;
  try {
    final hwnd = _mainWindow();
    if (hwnd == 0) return;
    _setDword(hwnd, _kDwmwaBorderColor,
        plain ? _kDwmwaColorNone : _kDwmwaColorDefault);
    _setDword(hwnd, _kDwmwaWindowCornerPreference,
        plain ? _kDwmwcpDoNotRound : _kDwmwcpDefault);
  } catch (_) {}
}
