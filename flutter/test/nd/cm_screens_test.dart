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

/// A request as the window shows it, with every switch: the list scrolls,
/// the buttons stay at the foot.
Widget _request() => NdWindowFrame(
      titleBar: NdTitleBar(
        brand: NdTitleBrand(
            title: cmWindowTitle('NeoDesk Quick Support', quickSupport: true)),
        controls: NdWindowControls(onMinimize: () {}),
      ),
      child: CmScreen(
        body: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: CmRequestBody(
            header: CmHeader(
                name: 'admin', subtitle: cmPeerLine('neodesk-web-mwwuezpy')),
            name: 'admin',
            permissions: _perms(all: true),
          ),
        ),
        foot: CmRequestActions(onDecline: () {}, onAllow: () {}),
      ),
    );

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

  test('the person sees who asks, never the console viewer\'s own id (L554)',
      () {
    useLanguage('en');
    expect(cmPeerLine('neodesk-web-mwwuezpy'), 'From the NeoDesk web console');
    expect(cmPeerLine('828416401'), '828 416 401');
    expect(cmPeerIsDevice('828 416 401'), isTrue);
    useLanguage('de');
    expect(cmPeerLine('neodesk-web-mwwuezpy'), 'Über die NeoDesk-Webkonsole');
    // One name for quick support in each language, the quick support
    // window's (L554)
    expect(cmWindowTitle('NeoDesk Quick Support', quickSupport: true),
        'NeoDesk Schnellhilfe');
    expect(cmWindowTitle('NeoDesk', quickSupport: false), 'NeoDesk');
    useLanguage('en');
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
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(top: 4),
                    child: CmPermissionList(items: _perms(all: true)),
                  ),
                ),
              ]),
        ),
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
}
