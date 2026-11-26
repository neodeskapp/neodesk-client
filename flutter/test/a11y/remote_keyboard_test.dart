// WCAG 2.1.2 No Keyboard Trap: the remote screen sends every key to the
// remote computer, so one combination must always give the keyboard back,
// put focus on the session toolbar and say so. The screen must have a name.
// (findings.md F14, F16, F17)

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common/widgets/remote_keyboard.dart';
import 'package:flutter_test/flutter_test.dart';

import '../nd/harness.dart';

class _Session {
  final screen = FocusNode(debugLabel: 'screen');
  final display = FocusNode(debugLabel: 'Display');
  late final controller = RemoteKeyboardController(screenNode: screen);
  final toRemote = <String>[];
  final toolbarShown = ValueNotifier<bool>(true);
  var leftRemote = 0;

  void dispose() {
    controller.dispose();
    screen.dispose();
    display.dispose();
  }

  Widget build({bool raw = false}) => Builder(
        builder: (context) => RemoteKeyboardTakeBack(
          onTake: () => controller.take(enterRemote: screen.requestFocus),
          child: Column(children: [
            ValueListenableBuilder<bool>(
              valueListenable: toolbarShown,
              builder: (_, shown, __) => FocusScope(
                node: controller.toolbarScope,
                child: shown
                    ? Row(children: [
                        TextButton(
                            focusNode: display,
                            onPressed: () {},
                            child: const Text('Display')),
                      ])
                    : const SizedBox(height: 40),
              ),
            ),
            Expanded(
              child: RemoteKeyboardScope(
                focusNode: screen,
                useRawKeyEvents: raw,
                onKeyEvent: (e) {
                  if (e is KeyDownEvent) toRemote.add(e.logicalKey.keyLabel);
                  return KeyEventResult.handled;
                },
                onRawKeyEvent: (e) {
                  // ignore: deprecated_member_use
                  if (e is RawKeyDownEvent) {
                    toRemote.add(e.logicalKey.keyLabel);
                  }
                  return KeyEventResult.handled;
                },
                peerName: 'Workshop PC',
                onReleaseKeyboard: () => controller.release(context,
                    leaveRemote: () => leftRemote++,
                    showToolbar: () => toolbarShown.value = true),
                child: const SizedBox.expand(),
              ),
            ),
          ]),
        ),
      );
}

Future<void> _chord(WidgetTester tester,
    {bool command = false,
    bool shift = true,
    String platform = 'windows',
    LogicalKeyboardKey? ctrl,
    LogicalKeyboardKey alt = LogicalKeyboardKey.altLeft}) async {
  final first = ctrl ??
      (command ? LogicalKeyboardKey.metaLeft : LogicalKeyboardKey.controlLeft);
  final mods = [
    first,
    alt,
    if (shift) LogicalKeyboardKey.shiftLeft,
  ];
  for (final m in mods) {
    await tester.sendKeyDownEvent(m, platform: platform);
  }
  await tester.sendKeyDownEvent(LogicalKeyboardKey.keyG, platform: platform);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.keyG, platform: platform);
  for (final m in mods.reversed) {
    await tester.sendKeyUpEvent(m, platform: platform);
  }
  await tester.pump();
}

List<String> _announcements(WidgetTester tester) {
  final said = <String>[];
  tester.binding.defaultBinaryMessenger.setMockDecodedMessageHandler<dynamic>(
      SystemChannels.accessibility, (dynamic msg) async {
    final m = msg as Map;
    if (m['type'] == 'announce') said.add('${(m['data'] as Map)['message']}');
    return null;
  });
  addTearDown(() => tester.binding.defaultBinaryMessenger
      .setMockDecodedMessageHandler<dynamic>(SystemChannels.accessibility, null));
  return said;
}

void main() {
  tearDown(() => releaseChordUsesCommandForTest = null);

  for (final raw in [false, true]) {
    final kind = raw ? 'raw key events (Linux)' : 'key events';
    testWidgets(
        'Ctrl+Alt+Shift+G gives the keyboard back and focuses the toolbar, '
        '$kind', (tester) async {
      releaseChordUsesCommandForTest = false;
      final s = _Session();
      addTearDown(s.dispose);
      final said = _announcements(tester);
      await pumpScreen(tester, s.build(raw: raw), size: const Size(600, 400));
      final platform = raw ? 'linux' : 'windows';

      expect(s.screen.hasPrimaryFocus, isTrue,
          reason: 'the screen takes the keyboard when the session opens');
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA, platform: platform);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab, platform: platform);
      expect(s.toRemote, ['A', 'Tab'],
          reason: 'keys, Tab too, go to the remote computer');

      await _chord(tester, platform: platform);
      await tester.pump();
      expect(s.toRemote.where((k) => k == 'G'), isEmpty,
          reason: 'the G of the combination must not reach the remote');
      expect(s.leftRemote, 1, reason: 'the grab ends');
      expect(s.screen.hasFocus, isFalse);
      expect(s.display.hasPrimaryFocus, isTrue,
          reason: 'focus moves to the first toolbar control');
      expect(said.last,
          'Keyboard released. Press Ctrl+Alt+Shift+G to give it back to the '
          'remote computer.');

      // Keys now stay on this computer.
      s.toRemote.clear();
      await tester.sendKeyEvent(LogicalKeyboardKey.keyB, platform: platform);
      expect(s.toRemote, isEmpty);

      // The same combination gives it back.
      await _chord(tester, platform: platform);
      expect(s.screen.hasPrimaryFocus, isTrue);
      expect(said.last,
          'Keyboard goes to Workshop PC. Press Ctrl+Alt+Shift+G to get it '
          'back.');
    });
  }

  testWidgets('Ctrl+Alt+G without Shift still goes to the remote computer',
      (tester) async {
    releaseChordUsesCommandForTest = false;
    final s = _Session();
    addTearDown(s.dispose);
    await pumpScreen(tester, s.build(), size: const Size(600, 400));
    await _chord(tester, shift: false);
    expect(s.toRemote, contains('G'));
    expect(s.leftRemote, 0);
    expect(s.screen.hasPrimaryFocus, isTrue);
  });

  testWidgets('AltGr+Shift+G still goes to the remote computer',
      (tester) async {
    // Windows reports AltGr as a left Ctrl with a right Alt.
    releaseChordUsesCommandForTest = false;
    final s = _Session();
    addTearDown(s.dispose);
    await pumpScreen(tester, s.build(), size: const Size(600, 400));
    await _chord(tester,
        ctrl: LogicalKeyboardKey.controlLeft,
        alt: LogicalKeyboardKey.altRight);
    expect(s.toRemote, contains('G'));
    expect(s.leftRemote, 0);
    // The right Ctrl with the right Alt is no AltGr: that is the combination.
    await _chord(tester,
        ctrl: LogicalKeyboardKey.controlRight,
        alt: LogicalKeyboardKey.altRight);
    expect(s.leftRemote, 1);
  });

  testWidgets('macOS uses Command+Option+Shift+G', (tester) async {
    releaseChordUsesCommandForTest = true;
    final s = _Session();
    addTearDown(s.dispose);
    final said = _announcements(tester);
    await pumpScreen(tester, s.build(), size: const Size(600, 400));
    await _chord(tester);
    expect(s.leftRemote, 0, reason: 'Ctrl is not the macOS chord');
    await _chord(tester, command: true);
    expect(s.leftRemote, 1);
    expect(said.last, contains('Command+Option+Shift+G'));
  });

  testWidgets('a hidden toolbar comes back and gets focus', (tester) async {
    releaseChordUsesCommandForTest = false;
    final s = _Session()..toolbarShown.value = false;
    addTearDown(s.dispose);
    await pumpScreen(tester, s.build(), size: const Size(600, 400));
    await _chord(tester);
    await tester.pump();
    expect(s.toolbarShown.value, isTrue);
    expect(s.display.hasPrimaryFocus, isTrue);
  });

  testWidgets('the remote screen is named and says how to leave it',
      (tester) async {
    releaseChordUsesCommandForTest = false;
    final handle = tester.ensureSemantics();
    final s = _Session();
    addTearDown(s.dispose);
    await pumpScreen(tester, s.build(), size: const Size(600, 400));
    final d = tester
        .getSemantics(find.byType(RemoteKeyboardScope))
        .getSemanticsData();
    expect(d.label, 'Screen of Workshop PC');
    expect(
        d.hint,
        'Keyboard and mouse go to Workshop PC. Press Ctrl+Alt+Shift+G to get '
        'the keyboard back and reach the toolbar.');
    handle.dispose();
  });
}
