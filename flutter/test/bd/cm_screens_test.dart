import 'package:flutter/material.dart';
import 'package:flutter_hbb/common/widgets/bd/bd.dart';
import 'package:flutter_hbb/desktop/pages/cm/cm_widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

const _cmSize = Size(380, 600);

Widget _cmWindow(Widget body, Widget foot) => Builder(
      builder: (context) => BdWindowFrame(
        titleBar: BdTitleBar(
          brand: const BdTitleBrand(title: 'BetterDesk'),
          controls: BdWindowControls(onMinimize: () {}),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(child: body),
          Container(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            decoration: BoxDecoration(
                border: Border(top: BorderSide(color: context.bd.rule))),
            child: foot,
          ),
        ]),
      ),
    );

List<CmPermission> _perms({bool all = false, ValueChanged<bool>? onFirst}) => [
      CmPermission(
          label: tr('bd-cm-perm-input'),
          value: true,
          onChanged: onFirst ?? (_) {}),
      CmPermission(
          label: tr('bd-cm-perm-clipboard'), value: true, onChanged: (_) {}),
      CmPermission(
          label: tr('bd-cm-perm-files'), value: true, onChanged: (_) {}),
      CmPermission(
          label: tr('bd-cm-perm-sound'), value: true, onChanged: (_) {}),
      CmPermission(
          label: tr('bd-cm-perm-restart'), value: false, onChanged: (_) {}),
      CmPermission(
          label: tr('bd-cm-perm-record'), value: false, onChanged: (_) {}),
      if (all) ...[
        CmPermission(
            label: tr('bd-cm-perm-block'), value: false, onChanged: (_) {}),
        CmPermission(
            label: tr('bd-cm-perm-privacy'), value: false, onChanged: (_) {}),
      ],
    ];

void main() {
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
        BdButton(
            label: tr('bd-cm-stop'),
            kind: BdButtonKind.danger,
            size: BdButtonSize.lg,
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
    await tester.tap(find.byType(BdSwitch).first);
    expect(got, isFalse);
    expect(find.text('Turned off in Settings'), findsOneWidget);
  });

  test('connected time reads in minutes, then hours and minutes', () {
    useLanguage('en');
    expect(cmConnectedFor(const Duration(minutes: 12)),
        'Connected for 12 minutes');
    expect(cmConnectedFor(const Duration(minutes: 80)),
        'Connected for 1 h 20 min');
  });
}
