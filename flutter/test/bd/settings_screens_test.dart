import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart' show translate;
import 'package:flutter_hbb/common/widgets/bd/bd.dart';
import 'package:flutter_hbb/desktop/pages/install_view.dart';
import 'package:flutter_hbb/desktop/pages/settings/settings_index.dart';
import 'package:flutter_hbb/desktop/pages/settings/settings_widgets.dart';
import 'package:flutter_hbb/desktop/widgets/bd_toolbar_button.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';
import 'harness.dart';

/// A row of the index drawn with the design's example value.
Widget _row(SettingsIndexEntry e, {bool locked = false}) {
  Widget control;
  switch (e.control) {
    case 'switch':
      control = BdSwitch(value: e.on, onChanged: locked ? null : (_) {});
      break;
    case 'seg':
      final current = int.tryParse(e.value) ?? 0;
      control = BdSegmented<int>(
        segments: [
          for (var i = 0; i < e.options.length; i++) BdSegment(i, e.options[i])
        ],
        value: e.options.length > 2 && e.label == 'One-time password length'
            ? 1
            : current,
        onChanged: locked ? null : (_) {},
      );
      break;
    case 'select':
      control = BdSelect<String>(
        width: 220,
        options: [BdOption(e.value, e.value)],
        value: e.value,
        onChanged: locked ? null : (_) {},
      );
      break;
    default:
      control = BdButton(
          label: e.value, size: BdButtonSize.sm, onPressed: locked ? null : () {});
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
        title: translate(section!),
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
      updateResult: tr('bd-about-latest'),
    );
  } else {
    content = SettingsGroupPage(
      title: tr('bd-set-$group'),
      lead: tr('bd-set-$group-lead'),
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
              BdButton(label: tr('bd-join-a-server'), onPressed: () {}),
              BdButton(label: tr('bd-set-up-by-hand'), onPressed: () {}),
              BdButton(label: tr('bd-set-pair-code'), onPressed: () {}),
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
            SettingsNavItem(g, tr('bd-set-$g'), dividerBefore: g == 'about'),
        ],
        value: group,
        onChanged: (_) {},
        search: BdSearchField(placeholder: tr('bd-set-search'), height: 32),
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
      expect(translate(e.label), isNot(e.label.startsWith('bd-') ? e.label : ''),
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

  for (final state in ['default', 'options', 'installing']) {
    forBothThemes('install $state', (tester, b) async {
      final path = TextEditingController(text: r'C:\Program Files\BetterDesk');
      addTearDown(path.dispose);
      await pumpScreen(
        tester,
        BdWindowFrame(
          titleBar: BdTitleBar(
            brand: BdTitleBrand(title: tr('bd-install-title')),
            controls: BdWindowControls(onClose: () {}),
          ),
          child: InstallView(
            lead: tr('bd-install-lead-join', [fernCompany, fernServer]),
            installingLead: tr('bd-install-installing-join', [fernCompany]),
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
            installing: state == 'installing',
          ),
        ),
        size: const Size(680, 560),
        brightness: b,
      );
      await shot(tester, 'client-install-$state', b);
    });
  }

  forBothThemes('remote toolbar', (tester, b) async {
    await pumpScreen(
      tester,
      Builder(
        builder: (context) => BdWindowFrame(
          titleBar: BdTitleBar(
            brand: const BdLogoMark(size: 18),
            tabs: [
              BdWindowTab(
                  label: 'Reception PC',
                  leading: const BdOsMark(os: BdOs.windows),
                  selected: true,
                  onClose: () {}),
            ],
            controls: BdWindowControls(
                onMinimize: () {}, onMaximize: () {}, onClose: () {}),
          ),
          child: Container(
            color: context.bd.canvas,
            alignment: Alignment.topCenter,
            padding: const EdgeInsets.only(top: 8),
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: context.bd.bgFloat,
                borderRadius: BdSize.r,
                border: Border.all(color: context.bd.rule),
                boxShadow: context.bd.shadowFloat,
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                BdToolbarButton(
                    icon: BdIcons.keyboard,
                    label: tr('bd-tb-keyboard'),
                    onPressed: () {}),
                BdToolbarButton(
                    icon: BdIcons.folder,
                    label: tr('bd-tb-files'),
                    onPressed: () {}),
                BdToolbarButton(
                    icon: BdIcons.chat, label: 'Chat', onPressed: () {}),
                BdToolbarButton(
                    icon: BdIcons.fullscreen,
                    label: tr('bd-tb-full-screen'),
                    onPressed: () {}),
                BdToolbarButton(
                    icon: BdIcons.moreHoriz,
                    label: tr('bd-tb-more'),
                    onPressed: () {}),
                Container(
                    width: 1,
                    height: 24,
                    margin: const EdgeInsets.symmetric(horizontal: 6),
                    color: context.bd.rule),
                BdToolbarButton(
                    icon: BdIcons.callEnd,
                    label: tr('bd-tb-end'),
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
