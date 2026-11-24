import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart' show translate;
import 'package:flutter_hbb/common/widgets/nd/nd.dart';
import 'package:flutter_hbb/desktop/pages/install_view.dart';
import 'package:flutter_hbb/desktop/pages/settings/settings_index.dart';
import 'package:flutter_hbb/desktop/pages/settings/settings_widgets.dart';
import 'package:flutter_hbb/desktop/widgets/nd_toolbar_button.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';
import 'harness.dart';

/// A row of the index drawn with the design's example value.
Widget _row(SettingsIndexEntry e, {bool locked = false}) {
  Widget control;
  switch (e.control) {
    case 'switch':
      control = NdSwitch(value: e.on, onChanged: locked ? null : (_) {});
      break;
    case 'seg':
      final current = int.tryParse(e.value) ?? 0;
      control = NdSegmented<int>(
        segments: [
          for (var i = 0; i < e.options.length; i++) NdSegment(i, e.options[i])
        ],
        value: e.options.length > 2 && e.label == 'One-time password length'
            ? 1
            : current,
        onChanged: locked ? null : (_) {},
      );
      break;
    case 'select':
      control = NdSelect<String>(
        width: 220,
        options: [NdOption(e.value, e.value)],
        value: e.value,
        onChanged: locked ? null : (_) {},
      );
      break;
    default:
      control = NdButton(
          label: e.value, size: NdButtonSize.sm, onPressed: locked ? null : () {});
  }
  return SettingsRow(
    label: translate(e.label),
    description: translateOrNull(e.desc),
    control: control,
  );
}

List<Widget> _sections(String group, {bool locked = false}) {
  final out = <Widget>[];
  String? section;
  var rows = <Widget>[];
  void flush() {
    if (section != null) {
      out.add(SettingsSection(
        title: translate(section),
        lead: translateOrNull('$section-lead'),
        children: rows,
      ));
    }
  }

  for (final e in kSettingsIndex.where((e) => e.group == group)) {
    if (e.section != section) {
      flush();
      section = e.section;
      rows = [];
    }
    rows.add(_row(e, locked: locked));
  }
  flush();
  return out;
}

const _groups = ['general', 'security', 'server', 'advanced', 'about'];

Widget _settings(String group, {bool locked = false}) {
  Widget content;
  if (group == 'about') {
    content = AboutView(
      facts: const AboutFacts(
          version: '1.5.0',
          buildDate: '20 Nov 2026',
          id: '418205739',
          fingerprint: '8f3a 61c2 d09b 4e77'),
      onViewLicence: () {},
      onSource: () {},
      onUpstream: () {},
      onCheckUpdates: () {},
      updateResult: tr('nd-about-latest'),
    );
  } else {
    content = SettingsGroupPage(
      title: tr('nd-set-$group'),
      lead: tr('nd-set-$group-lead'),
      children: [
        if (locked) SettingsLockNotice(onUnlock: () {}),
        if (group == 'server')
          ServerSummary(
            connected: true,
            server: fernServer,
            relay: '$fernServer:21117',
            api: 'https://$fernServer',
            keyText: '0eVuKk5nlHiXp+APNn0Y3pC1Iwpwn44JGqrQCsWqmBw=',
            joinedLine: 'Joined on 22 Nov 2026 with an invite from Fernhill IT.',
            actions: [
              NdButton(label: tr('nd-join-a-server'), onPressed: () {}),
              NdButton(label: tr('nd-set-up-by-hand'), onPressed: () {}),
              NdButton(label: tr('nd-set-pair-code'), onPressed: () {}),
            ],
          ),
        ..._sections(group, locked: locked),
      ],
    );
  }
  return mainWindow(
    Row(children: [
      SettingsNav<String>(
        items: [
          for (final g in _groups)
            SettingsNavItem(g, tr('nd-set-$g'), dividerBefore: g == 'about'),
        ],
        value: group,
        onChanged: (_) {},
        search: NdSearchField(placeholder: tr('nd-set-search'), height: 32),
      ),
      Expanded(child: content),
    ]),
    settingsOpen: true,
  );
}

void main() {
  for (final g in _groups) {
    forBothThemes('settings $g', (tester, b) async {
      await pumpScreen(tester, _settings(g), size: mainSize, brightness: b);
      await shot(tester, g == 'about' ? 'client-about' : 'client-settings-$g', b);
    });
  }

  forBothThemes('settings security locked', (tester, b) async {
    await pumpScreen(tester, _settings('security', locked: true),
        size: mainSize, brightness: b);
    await shot(tester, 'client-settings-security-locked', b);
  });

  test('every setting of the design has a label and a description', () {
    useLanguage('en');
    expect(kSettingsIndex.length, 95);
    for (final e in kSettingsIndex) {
      expect(translate(e.label), isNot(e.label.startsWith('nd-') ? e.label : ''),
          reason: e.label);
      expect(translateOrNull(e.desc), isNotNull, reason: e.desc);
    }
  });

  testWidgets('search finds a setting by its description', (tester) async {
    await pumpScreen(
      tester,
      SettingsSearchResults(query: 'proxy', hits: [
        for (final e in kSettingsIndex)
          if (translate(e.label).toLowerCase().contains('proxy') ||
              (translateOrNull(e.desc) ?? '').toLowerCase().contains('proxy'))
            SettingsSearchHit(label: translate(e.label), path: e.group),
      ]),
      size: const Size(800, 400),
    );
    expect(find.text('Proxy'), findsOneWidget);
    await pumpScreen(
        tester, const SettingsSearchResults(query: 'proxi', hits: []),
        size: const Size(800, 400));
    expect(find.text("No setting matches 'proxi'."), findsOneWidget);
  });

  for (final state in ['default', 'options', 'installing', 'copying', 'failed']) {
    forBothThemes('install $state', (tester, b) async {
      final path = TextEditingController(text: r'C:\Program Files\NeoDesk');
      addTearDown(path.dispose);
      await pumpScreen(
        tester,
        NdWindowFrame(
          titleBar: NdTitleBar(
            brand: NdTitleBrand(title: tr('nd-install-title')),
            controls: NdWindowControls(onClose: () {}),
          ),
          child: InstallView(
            lead: tr('nd-install-lead-join', [fernCompany, fernServer]),
            installingLead: tr('nd-install-installing-join', [fernCompany]),
            pathController: path,
            startMenu: true,
            desktopIcon: true,
            printer: true,
            onStartMenu: (_) {},
            onDesktopIcon: (_) {},
            onPrinter: (_) {},
            onInstall: () {},
            onChangePath: () {},
            onLicence: () {},
            onRunWithout: () {},
            optionsOpen: state == 'options',
            onToggleOptions: () {},
            installing: state == 'installing' || state == 'copying',
            step: state == 'copying'
                ? InstallStep.copying
                : InstallStep.permission,
            copyPercent: state == 'copying' ? 45 : null,
            error: state == 'failed' ? tr('nd-install-cancelled') : null,
          ),
        ),
        size: const Size(680, 560),
        brightness: b,
      );
      switch (state) {
        case 'installing':
          expect(find.text('Asking Windows for permission'), findsOneWidget);
          expect(find.text('Starting NeoDesk'), findsOneWidget);
          break;
        case 'copying':
          expect(find.text('Copying NeoDesk to this computer (45%)'),
              findsOneWidget);
          expect(find.byType(NdSpinner), findsOneWidget);
          break;
        case 'failed':
          expect(find.textContaining('Windows did not get permission'),
              findsOneWidget);
          expect(find.text('Install'), findsOneWidget);
          break;
      }
      await shot(tester, 'client-install-$state', b);
    });
  }

  forBothThemes('remote toolbar', (tester, b) async {
    await pumpScreen(
      tester,
      Builder(
        builder: (context) => NdWindowFrame(
          titleBar: NdTitleBar(
            brand: const NdLogoMark(size: 18),
            tabs: [
              NdWindowTab(
                  label: 'Reception PC',
                  leading: const NdOsMark(os: NdOs.windows),
                  selected: true,
                  onClose: () {}),
            ],
            controls: NdWindowControls(
                onMinimize: () {}, onMaximize: () {}, onClose: () {}),
          ),
          child: Container(
            color: context.nd.canvas,
            alignment: Alignment.topCenter,
            padding: const EdgeInsets.only(top: 8),
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: context.nd.bgFloat,
                borderRadius: NdSize.r,
                border: Border.all(color: context.nd.rule),
                boxShadow: context.nd.shadowFloat,
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                NdToolbarButton(
                    icon: NdIcons.keyboard,
                    label: tr('nd-tb-keyboard'),
                    onPressed: () {}),
                NdToolbarButton(
                    icon: NdIcons.folder,
                    label: tr('nd-tb-files'),
                    onPressed: () {}),
                NdToolbarButton(
                    icon: NdIcons.chat, label: 'Chat', onPressed: () {}),
                NdToolbarButton(
                    icon: NdIcons.fullscreen,
                    label: tr('nd-tb-full-screen'),
                    onPressed: () {}),
                NdToolbarButton(
                    icon: NdIcons.moreHoriz,
                    label: tr('nd-tb-more'),
                    onPressed: () {}),
                Container(
                    width: 1,
                    height: 24,
                    margin: const EdgeInsets.symmetric(horizontal: 6),
                    color: context.nd.rule),
                NdToolbarButton(
                    icon: NdIcons.callEnd,
                    label: tr('nd-tb-end'),
                    danger: true,
                    onPressed: () {}),
              ]),
            ),
          ),
        ),
      ),
      size: mainSize,
      brightness: b,
    );
    await shot(tester, 'client-remote-default', b);
  });
}
