// Typing into the fields of Settings, its dialogs and the first start
// (L435).
//
// The Windows and Linux engines hand every key to the framework first. A key
// nobody handles goes on as text to the text input client the engine holds
// at that moment; without a client the text is lost, while paste (a
// shortcut in the framework) and Escape still work. typeKeys() delivers keys
// the same way, so a field that shows focus but has lost its client loses
// the typed text here too.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common.dart'
    show CustomAlertDialog, OverlayDialogManager, globalKey;
import 'package:flutter_hbb/common/widgets/nd/nd.dart';
import 'package:flutter_hbb/common/widgets/nd/nd_dialog_host.dart';
import 'package:flutter_hbb/main.dart' show keyListenerBuilder;
import 'package:flutter_hbb/onboarding/first_start_view.dart';
import 'package:flutter_hbb/onboarding/onboarding_flow.dart';
import 'package:flutter_hbb/onboarding/onboarding_service.dart';
import 'package:flutter_hbb/onboarding/setup_by_hand.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'fixtures.dart';
import 'harness.dart';

final _desktops =
    TargetPlatformVariant({TargetPlatform.windows, TargetPlatform.linux});

LogicalKeyboardKey _keyFor(String ch) {
  switch (ch) {
    case '.':
      return LogicalKeyboardKey.period;
    case '-':
      return LogicalKeyboardKey.minus;
    default:
      return LogicalKeyboardKey(ch.codeUnitAt(0));
  }
}

EditableTextState? _focusedEditable(WidgetTester tester) {
  for (final s
      in tester.stateList<EditableTextState>(find.byType(EditableText))) {
    if (s.widget.focusNode.hasPrimaryFocus) return s;
  }
  return null;
}

/// Types [text] (a-z, 0-9, '.', '-') key by key as the desktop engines do.
Future<void> typeKeys(WidgetTester tester, String text) async {
  final platform = defaultTargetPlatform.name;
  for (final ch in text.split('')) {
    final key = _keyFor(ch);
    final handled =
        await tester.sendKeyDownEvent(key, platform: platform, character: ch);
    final target = _focusedEditable(tester);
    if (!handled && tester.testTextInput.hasAnyClients && target != null) {
      final v = target.textEditingValue;
      final at = v.selection.isValid
          ? v.selection
          : TextSelection.collapsed(offset: v.text.length);
      tester.testTextInput.updateEditingValue(v.replaced(at, ch));
    }
    await tester.sendKeyUpEvent(key, platform: platform);
    await tester.pump();
  }
}

/// The main window's app as main.dart builds it: GetMaterialApp on the
/// global navigator key, with the key listener of the main window.
Future<void> pumpApp(WidgetTester tester, Widget page) async {
  useLanguage('en');
  await loadNdFonts();
  tester.view.physicalSize = mainSize;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(GetMaterialApp(
    navigatorKey: globalKey,
    theme: NdTheme.theme(Brightness.light, desktop: true),
    builder: (context, child) => keyListenerBuilder(context, child),
    home: Scaffold(body: page),
  ));
  await tester.pumpAndSettle();
}

Finder _fieldIn(Finder parent, [int index = 0]) =>
    find.descendant(of: parent, matching: find.byType(EditableText)).at(index);

String _textOf(WidgetTester tester, Finder editable) =>
    tester.widget<EditableText>(editable).controller.text;

void main() {
  testWidgets('the settings search takes typed text', (tester) async {
    final search = TextEditingController();
    addTearDown(search.dispose);
    await pumpApp(
        tester,
        Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
              width: 240,
              child: NdSearchField(
                  placeholder: 'Search settings', controller: search)),
        ));
    await tester.tap(find.byType(NdSearchField));
    await tester.pumpAndSettle();
    await typeKeys(tester, 'password');
    expect(search.text, 'password');
  }, variant: _desktops);

  testWidgets('Join a server takes typed text in a freshly opened dialog',
      (tester) async {
    final svc = FakeOnboardingService(
        const OnboardingState(phase: OnboardingPhase.joined));
    await pumpApp(
        tester,
        Center(
          child: NdButton(
              label: 'Join a server',
              onPressed: () => showJoinServerDialog(svc, currentServer: '')),
        ));
    await tester.tap(find.text('Join a server'));
    await tester.pumpAndSettle();
    final dialog = find.byType(NdDialog);
    expect(dialog, findsOneWidget);
    // No click: the invite field has the focus when the dialog opens.
    await typeKeys(tester, 'k7q4-m2xd');
    expect(_textOf(tester, _fieldIn(dialog)), 'k7q4-m2xd');
    // The server field that a bare code asks for.
    await tester.tap(_fieldIn(dialog, 1));
    await tester.pumpAndSettle();
    await typeKeys(tester, 'help.example');
    expect(_textOf(tester, _fieldIn(dialog, 1)), 'help.example');
  }, variant: _desktops);

  testWidgets('Set up by hand takes typed text in every field', (tester) async {
    await pumpApp(
        tester,
        Center(
          child: NdButton(
              label: 'Set up by hand',
              onPressed: () =>
                  showNdDialog<void>((close, _) => SetupByHandDialog(
                        initial: const HandSetup(idServer: '', key: ''),
                        onSave: (_) async => const HandSetupErrors(),
                        onCancel: close,
                      ))),
        ));
    await tester.tap(find.text('Set up by hand'));
    await tester.pumpAndSettle();
    final dialog = find.byType(SetupByHandDialog);
    await typeKeys(tester, '10.10.10.74');
    expect(_textOf(tester, _fieldIn(dialog)), '10.10.10.74');

    await tester.tap(_fieldIn(dialog, 1));
    await tester.pumpAndSettle();
    await typeKeys(tester, 'abc123');
    expect(_textOf(tester, _fieldIn(dialog, 1)), 'abc123');

    await tester.tap(find.text('Relay and API server'));
    await tester.pumpAndSettle();
    for (final i in [2, 3]) {
      await tester.tap(_fieldIn(dialog, i));
      await tester.pumpAndSettle();
      await typeKeys(tester, 'relay$i');
      expect(_textOf(tester, _fieldIn(dialog, i)), 'relay$i');
    }
  }, variant: _desktops);

  testWidgets('Escape closes a dialog with and without a field',
      (tester) async {
    var closed = 0;
    await pumpApp(
        tester,
        Column(mainAxisSize: MainAxisSize.min, children: [
          NdButton(
              label: 'question',
              onPressed: () async {
                await showNdDialog<bool>((close, _) => NdDialog(
                      title: 'Join another server?',
                      onClose: () => close(false),
                      children: const [Text('Leave it?')],
                      actions: [
                        NdButton(label: 'Join', onPressed: () => close(true)),
                      ],
                    ));
                closed++;
              }),
          NdButton(
              label: 'hand',
              onPressed: () async {
                await showNdDialog<void>((close, _) => SetupByHandDialog(
                      initial: const HandSetup(idServer: '', key: ''),
                      onSave: (_) async => const HandSetupErrors(),
                      onCancel: close,
                    ));
                closed++;
              }),
        ]));
    for (final opener in ['question', 'hand']) {
      await tester.tap(find.text(opener));
      await tester.pumpAndSettle();
      expect(find.byType(NdDialog), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape,
          platform: defaultTargetPlatform.name);
      await tester.pumpAndSettle();
      expect(find.byType(NdDialog), findsNothing);
    }
    expect(closed, 2);
  }, variant: _desktops);

  testWidgets('the first start screen takes typed text', (tester) async {
    final svc = FakeOnboardingService();
    await pumpApp(tester, FirstStartView(service: svc, onSetUpByHand: () {}));
    final view = find.byType(FirstStartView);
    // The invite field has the focus when the screen opens.
    await typeKeys(tester, 'k7q4-m2xd');
    expect(_textOf(tester, _fieldIn(view)), 'k7q4-m2xd');
    await tester.tap(_fieldIn(view, 1));
    await tester.pumpAndSettle();
    await typeKeys(tester, 'help.example');
    expect(_textOf(tester, _fieldIn(view, 1)), 'help.example');
  }, variant: _desktops);

  // Pair with code, the password, PIN and proxy dialogs: TextFields in a
  // CustomAlertDialog shown by the dialog manager.
  testWidgets('the dialog manager\'s dialogs take typed text', (tester) async {
    final server = TextEditingController();
    final code = TextEditingController();
    addTearDown(server.dispose);
    addTearDown(code.dispose);
    final manager = OverlayDialogManager();
    await pumpApp(
        tester,
        Center(
          child: NdButton(
              label: 'Pair with code',
              onPressed: () => manager.show(
                  (setState, close, context) => CustomAlertDialog(
                        title: const Text('Pair with code'),
                        content: Column(children: [
                          TextField(controller: server, autofocus: true),
                          TextField(controller: code),
                        ]),
                        onCancel: close,
                      ),
                  forceGlobal: true)),
        ));
    await tester.tap(find.text('Pair with code'));
    await tester.pumpAndSettle();
    await typeKeys(tester, 'help.example');
    expect(server.text, 'help.example');
    await tester.tap(find.byType(TextField).at(1));
    await tester.pumpAndSettle();
    await typeKeys(tester, '123456');
    expect(code.text, '123456');
    manager.dismissAll();
    await tester.pumpAndSettle();
  }, variant: _desktops);
}
