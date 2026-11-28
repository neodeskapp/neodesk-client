import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common.dart' show translate;
import 'package:flutter_hbb/common/widgets/nd/nd.dart';
import 'package:flutter_hbb/desktop/pages/cm/cm_widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

const _cmSize = Size(380, 600);

Widget _cmWindow(Widget body, Widget foot) => Builder(
      builder: (context) => NdWindowFrame(
        titleBar: NdTitleBar(
          brand: const NdTitleBrand(title: 'NeoDesk'),
          controls: NdWindowControls(onMinimize: () {}),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(child: body),
          Container(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            decoration: BoxDecoration(
                border: Border(top: BorderSide(color: context.nd.rule))),
            child: foot,
          ),
        ]),
      ),
    );

List<CmPermission> _perms({bool all = false, ValueChanged<bool>? onFirst}) => [
      CmPermission(
          label: tr('nd-cm-perm-input'),
          value: true,
          onChanged: onFirst ?? (_) {}),
      CmPermission(
          label: tr('nd-cm-perm-clipboard'), value: true, onChanged: (_) {}),
      CmPermission(
          label: tr('nd-cm-perm-files'), value: true, onChanged: (_) {}),
      CmPermission(
          label: tr('nd-cm-perm-sound'), value: true, onChanged: (_) {}),
      CmPermission(
          label: tr('nd-cm-perm-restart'), value: false, onChanged: (_) {}),
      CmPermission(
          label: tr('nd-cm-perm-record'), value: false, onChanged: (_) {}),
      if (all) ...[
        CmPermission(
            label: tr('nd-cm-perm-block'), value: false, onChanged: (_) {}),
        CmPermission(
            label: tr('nd-cm-perm-privacy'), value: false, onChanged: (_) {}),
      ],
    ];

/// A quick support caller as the window names it (A271).
CmCaller _qsCaller({required bool vouched}) => cmCaller(
    name: 'Olga Operator',
    peerId: 'neodesk-web-mwwuezpy',
    vouched: vouched,
    quickSupport: true,
    offersAllow: cmOffersAllow('password', vouched: vouched));

/// A request as the window shows it, with every switch: the list scrolls,
/// the buttons stay at the foot.
Widget _request({bool vouched = true}) {
  final caller = _qsCaller(vouched: vouched);
  return NdWindowFrame(
    titleBar: NdTitleBar(
      brand: NdTitleBrand(
          title: cmWindowTitle('NeoDesk Quick Support', quickSupport: true)),
      controls: NdWindowControls(onMinimize: () {}),
    ),
    child: CmScreen(
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        child: CmRequestBody(
          header: CmHeader(name: caller.name, subtitle: caller.line),
          warning: caller.warning,
          name: caller.name,
          permissions: _perms(all: true),
        ),
      ),
      foot: CmRequestActions(
          onDecline: () {},
          onAllow: cmOffersAllow('password', vouched: vouched) ? () {} : null),
    ),
  );
}

void main() {
  // The consent window of the quick support incident (26 Nov): only Decline
  // was there. Allow and Decline are both in the window at its size, at
  // 100 to 200 % scaling, with every switch listed (L552)
  for (final scale in [1.0, 1.25, 1.5, 2.0]) {
    testWidgets('Allow and Decline stay in view at ${(scale * 100).round()} %',
        (tester) async {
      // The window's texts are made before pumpScreen: the language first
      useLanguage('de');
      await pumpScreen(tester, _request(), size: _cmSize, lang: 'de');
      tester.view.devicePixelRatio = scale;
      tester.view.physicalSize = _cmSize * scale;
      await tester.pumpAndSettle();
      for (final label in [tr('nd-allow'), translate('Decline')]) {
        final button = find.widgetWithText(NdButton, label);
        expect(button, findsOneWidget, reason: label);
        final rect = tester.getRect(button);
        expect(rect.bottom, lessThanOrEqualTo(_cmSize.height), reason: label);
        expect(rect.right, lessThanOrEqualTo(_cmSize.width), reason: label);
      }
    });
  }

  testWidgets('Enter alone accepts nothing; Tab reaches Decline and Allow',
      (tester) async {
    var allowed = 0;
    var declined = 0;
    await pumpScreen(
        tester,
        CmScreen(
          body: const SizedBox(),
          foot: CmRequestActions(
              onDecline: () => declined++, onAllow: () => allowed++),
        ),
        size: _cmSize);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(allowed, 0);
    final reached = <String>{};
    for (var i = 0; i < 6; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      final focus = FocusManager.instance.primaryFocus?.context;
      if (focus == null) continue;
      final button = focus.findAncestorWidgetOfExactType<NdButton>() ??
          (focus.widget is NdButton ? focus.widget as NdButton : null);
      if (button != null) reached.add(button.label);
    }
    expect(reached, containsAll([translate('Decline'), tr('nd-allow')]));
    expect(allowed, 0);
    expect(declined, 0);
  });

  // A271: the window names the caller only when the server vouched for it.
  // The console viewer's own peer ID and name are claims any caller can
  // make, so they never say "From the NeoDesk web console"
  test('a vouched helper is named, with where they come from', () {
    useLanguage('en');
    final helper = _qsCaller(vouched: true);
    expect(helper.name, 'Olga Operator');
    expect(helper.line, 'From the NeoDesk web console');
    expect(helper.warning, isNull);
    expect(helper.unknown, isFalse);
    expect(cmOffersAllow('password', vouched: true), isTrue);
    useLanguage('de');
    expect(_qsCaller(vouched: true).line, 'Über die NeoDesk-Webkonsole');
    // One name for quick support in each language, the quick support
    // window's (L554)
    expect(cmWindowTitle('NeoDesk Quick Support', quickSupport: true),
        'NeoDesk Schnellhilfe');
    expect(cmWindowTitle('NeoDesk', quickSupport: false), 'NeoDesk');
    useLanguage('en');
  });

  test('a caller nobody vouched for is unknown and gets no Allow in quick support',
      () {
    useLanguage('en');
    // Claims to be the web console (its peer ID and name): unknown
    final forged = _qsCaller(vouched: false);
    expect(forged.name, 'Someone unknown');
    expect(forged.line, 'The server did not confirm who this is');
    expect(forged.unknown, isTrue);
    expect(cmOffersAllow('password', vouched: false), isFalse);
    expect(forged.warning,
        "Only someone with the one-time password can connect. Decline if you don't expect this.");
    // A NeoDesk ID in quick support is a claim too
    final desktop = cmCaller(
        name: 'Olga Operator',
        peerId: '828416401',
        vouched: false,
        quickSupport: true,
        offersAllow: false);
    expect(desktop.name, 'Someone unknown');
    expect(desktop.line, isNot('828 416 401'));
    // Vouched without a name names nobody
    expect(
        cmCaller(
                name: ' ',
                peerId: 'neodesk-web-x',
                vouched: true,
                quickSupport: true,
                offersAllow: true)
            .name,
        'Someone unknown');
    useLanguage('de');
    expect(_qsCaller(vouched: false).name, 'Jemand Unbekanntes');
    expect(_qsCaller(vouched: false).line,
        'Der Server hat nicht bestätigt, wer das ist');
    useLanguage('en');
  });

  test('outside quick support a caller nobody vouched for gets a warning before Allow',
      () {
    useLanguage('en');
    expect(cmOffersAllow('click', vouched: false), isTrue);
    CmCaller desktop() => cmCaller(
        name: 'Mara',
        peerId: '828416401',
        vouched: false,
        quickSupport: false,
        offersAllow: true);
    expect(desktop().name, 'Mara');
    expect(desktop().line, '828 416 401');
    expect(desktop().lineIsId, isTrue);
    expect(desktop().warning,
        "NeoDesk can't confirm who is asking. Allow only if you expect this connection.");
    final web = cmCaller(
        name: 'admin',
        peerId: 'neodesk-web-mwwuezpy',
        vouched: false,
        quickSupport: false,
        offersAllow: true);
    expect(web.name, 'Someone unknown');
    expect(web.line, isNot('From the NeoDesk web console'));
    expect(web.warning, isNotNull);
    useLanguage('de');
    expect(desktop().warning,
        'NeoDesk kann nicht bestätigen, wer fragt. Erlaube es nur, wenn du diese Verbindung erwartest.');
    useLanguage('en');
  });

  test('an unattended caller on the receiver is named with how the server vouched (A279)',
      () {
    useLanguage('en');
    CmCaller of(String via) => cmCaller(
        name: 'Olga Operator',
        peerId: '828416401',
        vouched: true,
        vouchedVia: via,
        quickSupport: false,
        offersAllow: false);
    expect(of('desktop').name, 'Olga Operator');
    expect(of('desktop').line, 'From the NeoDesk app');
    expect(of('desktop').warning, isNull);
    expect(of('console').line, 'From the NeoDesk web console');
    expect(of('').line, 'From the NeoDesk web console');
    // Not vouched, the way it came in says nothing
    expect(
        cmCaller(
                name: 'Olga Operator',
                peerId: '828416401',
                vouched: false,
                vouchedVia: 'desktop',
                quickSupport: false,
                offersAllow: true)
            .line,
        '828 416 401');
  });

  testWidgets('an unknown caller in quick support sees Decline only and the warning',
      (tester) async {
    useLanguage('en');
    await pumpScreen(tester, _request(vouched: false), size: _cmSize);
    expect(find.text('Someone unknown'), findsOneWidget);
    expect(find.text('From the NeoDesk web console'), findsNothing);
    expect(find.textContaining('Olga'), findsNothing);
    expect(find.widgetWithText(NdButton, translate('Decline')), findsOneWidget);
    expect(find.widgetWithText(NdButton, tr('nd-allow')), findsNothing);
    expect(find.widgetWithText(NdNotice, tr('nd-cm-password-only')),
        findsOneWidget);
  });

  testWidgets('a vouched helper in quick support gets Allow and no warning',
      (tester) async {
    useLanguage('en');
    await pumpScreen(tester, _request(), size: _cmSize);
    expect(find.text('Olga Operator'), findsOneWidget);
    expect(find.text('From the NeoDesk web console'), findsOneWidget);
    expect(find.widgetWithText(NdButton, tr('nd-allow')), findsOneWidget);
    expect(find.byType(NdNotice), findsNothing);
  });

  forBothThemes('connection manager request', (tester, b) async {
    await pumpScreen(
      tester,
      _cmWindow(
        SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: CmRequestBody(
            header: const CmHeader(
                name: 'Mara Jensen', subtitle: '702 118 446', mono: true),
            name: 'Mara Jensen',
            permissions: _perms(),
          ),
        ),
        CmRequestActions(
            onDecline: () {}, onAllow: () {}, onAllowElevated: () {}),
      ),
      size: _cmSize,
      brightness: b,
    );
    await shot(tester, 'client-connection-manager-request', b);
  });

  forBothThemes('connection manager connected', (tester, b) async {
    await pumpScreen(
      tester,
      _cmWindow(
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  CmHeader(
                      name: 'Mara Jensen',
                      subtitle: cmConnectedFor(const Duration(minutes: 12))),
                  const SizedBox(height: 16),
                  CmTabs(value: CmTab.access, onChanged: (_) {}),
                ]),
          ),
          Expanded(
            child: CmTabBody(
              tab: CmTab.access,
              access: _perms(all: true),
              chat: (_) => const SizedBox(),
              files: (_) => const SizedBox(),
            ),
          ),
        ]),
        NdButton(
            label: tr('nd-cm-stop'),
            kind: NdButtonKind.danger,
            size: NdButtonSize.lg,
            block: true,
            onPressed: () {}),
      ),
      size: _cmSize,
      brightness: b,
    );
    await shot(tester, 'client-connection-manager-connected', b);
  });

  testWidgets('a switch reports the change; one without a handler shows the reason',
      (tester) async {
    bool? got;
    await pumpScreen(
      tester,
      CmPermissionList(items: [
        CmPermission(
            label: 'Use mouse and keyboard',
            value: true,
            onChanged: (v) => got = v),
        const CmPermission(
            label: 'Record the session',
            value: false,
            onChanged: null,
            reason: 'Turned off in Settings'),
      ]),
      size: const Size(380, 200),
    );
    await tester.tap(find.byType(NdSwitch).first);
    expect(got, isFalse);
    expect(find.text('Turned off in Settings'), findsOneWidget);
  });

  test('connected time reads in minutes, then hours and minutes', () {
    useLanguage('en');
    expect(cmConnectedFor(const Duration(minutes: 12)),
        'Connected for 12 min');
    // One minute too: no "1 minutes".
    expect(cmConnectedFor(const Duration(seconds: 70)), 'Connected for 1 min');
    expect(cmConnectedFor(const Duration(minutes: 80)),
        'Connected for 1 h 20 min');
  });

  // Files opened the chat before: every tab shows its own page, and the
  // window keeps its size
  testWidgets('each tab opens its own page in the same room', (tester) async {
    var tab = CmTab.access;
    await pumpScreen(
      tester,
      StatefulBuilder(
        builder: (context, setState) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
          CmTabs(value: tab, onChanged: (t) => setState(() => tab = t)),
          Expanded(
            child: CmTabBody(
              tab: tab,
              access: _perms(),
              chat: (_) => const Text('the chat'),
              files: (_) => const Text('the files'),
            ),
          ),
        ]),
      ),
      size: _cmSize,
    );
    expect(find.text(tr('nd-cm-perm-input')), findsOneWidget);
    await tester.tap(find.text(tr('nd-cm-tab-files')));
    await tester.pump();
    expect(find.text('the files'), findsOneWidget);
    expect(find.text('the chat'), findsNothing);
    await tester.tap(find.text(translate('Chat')));
    await tester.pump();
    expect(find.text('the chat'), findsOneWidget);
    expect(find.text('the files'), findsNothing);
    expect(tester.getSize(find.byType(CmTabBody)).width, _cmSize.width);
  });

  // The switches scroll at the card's full width, so the scrollbar runs
  // along the window's edge and not over them
  testWidgets('the switches scroll at full width with their own padding',
      (tester) async {
    await pumpScreen(
      tester,
      CmTabBody(
        tab: CmTab.access,
        access: _perms(all: true),
        chat: (_) => const SizedBox(),
        files: (_) => const SizedBox(),
      ),
      size: const Size(380, 200),
    );
    final scroll = find.byType(SingleChildScrollView);
    expect(tester.getSize(scroll).width, 380);
    final lastSwitch = tester.getTopRight(find.byType(NdSwitch).first);
    expect(lastSwitch.dx, lessThanOrEqualTo(380 - 20));
  });

  test('a file transfer opens on Files and a camera has no Files', () {
    expect(cmShownTab(CmTab.access, file: true), CmTab.files);
    expect(cmShownTab(CmTab.chat, file: true), CmTab.chat);
    expect(cmShownTab(CmTab.files, camera: true), CmTab.access);
    expect(cmShownTab(CmTab.files), CmTab.files);
  });

  testWidgets('a file transfer has no Access tab', (tester) async {
    await pumpScreen(
      tester,
      CmTabs(value: CmTab.files, showAccess: false, onChanged: (_) {}),
      size: const Size(380, 60),
    );
    expect(find.text(tr('nd-cm-tab-access')), findsNothing);
    expect(find.text(tr('nd-cm-tab-files')), findsOneWidget);
  });
}
