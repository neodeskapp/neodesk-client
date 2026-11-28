// The connection window as the one in-session UI (receiver step 1): the bar
// at the top of the screen during a session, the card with the switches
// when the person expands it, and the people it names (A271).
//
// The window's page (server_page.dart ConnectionManager) needs the client
// core, so these tests build the bar and the card from the same parts the
// page uses: CmBarOrCard switches between them, cmBarPeople and cmBarText
// name the people, cmBarAllowed and cmBarClient pick the shape and the
// connection.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common.dart' show translate;
import 'package:flutter_hbb/common/widgets/nd/nd.dart';
import 'package:flutter_hbb/desktop/pages/cm/cm_widgets.dart';
import 'package:flutter_hbb/desktop/pages/server_page.dart'
    show
        CmFileList,
        CmWindowShaper,
        cmBarAllowed,
        cmBarClient,
        cmBarPeople,
        cmTabLabel;
import 'package:flutter_hbb/models/cm_file_model.dart';
import 'package:flutter_hbb/models/file_model.dart' show JobState;
import 'package:flutter_hbb/models/server_model.dart' show Client;
import 'package:flutter_test/flutter_test.dart';

import '../a11y/a11y_helpers.dart' show recordAnnouncements;
import 'fixtures.dart' show fernAccent;
import 'harness.dart';

const _barSize = Size(760, 64);
const _barPanelSize = Size(760, 472);
const _cardSize = Size(380, 600);

/// Room for the bar and the card, as the window is either.
const _windowSize = Size(760, 600);

/// A caller as the connection manager gets it.
Client _client(int id, String name, String peerId,
    {bool authorized = true,
    bool vouched = false,
    bool file = false,
    bool disconnected = false}) {
  final c = Client(id, authorized, file, false, name, peerId, true, true, true);
  c.vouched = vouched;
  c.disconnected = disconnected;
  return c;
}

/// The quick support supporter the server named (the redeem answer or a
/// vouched click).
final _mara = _client(1, 'Mara Jensen', 'neodesk-web-mwwuezpy', vouched: true);

List<CmPermission> _perms() => [
      CmPermission(
          label: tr('nd-cm-perm-input'), value: true, onChanged: (_) {}),
      CmPermission(
          label: tr('nd-cm-perm-clipboard'), value: false, onChanged: (_) {}),
      CmPermission(
          label: tr('nd-cm-perm-files'), value: false, onChanged: (_) {}),
      CmPermission(
          label: tr('nd-cm-perm-sound'), value: true, onChanged: (_) {}),
    ];

/// The bar as the page builds it for [clients].
Widget _bar(List<Client> clients, VoidCallback expand,
    {bool quickSupport = true,
    bool using = false,
    List<String>? calls,
    Widget? panel,
    bool files = false}) {
  final people = cmBarPeople(clients, quickSupport: quickSupport);
  return CmBarWindow(
    bar: CmSessionBar(
      text: cmBarText(people, using: using),
      onChat: () => calls?.add('chat'),
      onFiles: files ? () => calls?.add('files') : null,
      filesLabel: files ? tr('nd-qs-files-count', [2]) : null,
      filesOpen: panel != null,
      onStop: () => calls?.add('stop'),
      onExpand: expand,
    ),
    panel: panel,
  );
}

/// The card: one tab label per person, then the selected one's header, its
/// tabs and the switches, and the control that collapses it.
Widget _card(List<Client> clients, VoidCallback? collapse,
        {bool quickSupport = true}) =>
    Builder(builder: (context) {
      final people = cmBarPeople(clients, quickSupport: quickSupport);
      return NdWindowFrame(
        titleBar: NdTitleBar(
          brand: NdTitleBrand(
              title: cmWindowTitle('NeoDesk', quickSupport: quickSupport)),
          controls: Row(mainAxisSize: MainAxisSize.min, children: [
            if (collapse != null)
              NdIconButton(
                  icon: NdIcons.expandLess,
                  tooltip: tr('nd-cm-bar-collapse'),
                  onPressed: collapse),
            NdWindowControls(onMinimize: () {}),
          ]),
        ),
        child: CmScreen(
          body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (people.length > 1)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: Row(children: [
                  for (final p in people)
                    Padding(
                        padding: const EdgeInsets.only(right: 16),
                        child: Text(p, key: ValueKey('tab-$p'))),
                ]),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    CmHeader(
                        name: people.isEmpty ? 'Mara Jensen' : people.first,
                        subtitle: cmConnectedFor(const Duration(minutes: 4))),
                    const SizedBox(height: 16),
                    CmTabs(value: CmTab.access, onChanged: (_) {}),
                  ]),
            ),
            Expanded(
              child: CmTabBody(
                tab: CmTab.access,
                access: _perms(),
                chat: (_) => const SizedBox(),
                files: (_) => const SizedBox(),
              ),
            ),
          ]),
          foot: NdButton(
              label: tr('nd-cm-stop'),
              kind: NdButtonKind.danger,
              size: NdButtonSize.lg,
              block: true,
              onPressed: () {}),
        ),
      );
    });

/// The window that switches between them, as the page uses it.
Widget _window(List<Client> clients,
        {List<CmShape>? shapes, bool quickSupport = true}) =>
    CmBarOrCard(
      barAllowed: cmBarAllowed(clients),
      onShape: shapes?.add,
      bar: (expand) => _bar(clients, expand, quickSupport: quickSupport),
      card: (collapse) =>
          _card(clients, collapse, quickSupport: quickSupport),
    );

List<CmFileLog> _jobs() => [
      CmFileLog()
        ..id = 1
        ..fileName = r'C:\Users\jo\Downloads\printer-driver.zip'
        ..action = CmFileAction.remoteToLocal
        ..totalSize = 4718592
        ..finishedSize = 4718592
        ..state = JobState.done,
      CmFileLog()
        ..id = 2
        ..fileName = r'C:\Users\jo\Desktop\error.log'
        ..action = CmFileAction.localToRemote
        ..totalSize = 1536
        ..finishedSize = 1536
        ..state = JobState.done,
    ];

void main() {
  final viewing = 'Mara Jensen is viewing and controlling your computer';

  testWidgets('a session collapses into the bar; expand shows the switches, '
      'collapse goes back', (tester) async {
    useLanguage('en');
    final shapes = <CmShape>[];
    await pumpScreen(tester, _window([_mara], shapes: shapes),
        size: _windowSize);
    await tester.pump();
    expect(find.text(viewing, findRichText: true), findsOneWidget);
    expect(find.text(tr('nd-cm-perm-input')), findsNothing);
    expect(shapes.last, CmShape.bar);

    await tester.tap(find.byTooltip(tr('nd-cm-bar-expand')));
    await tester.pump();
    await tester.pump();
    expect(find.text(viewing, findRichText: true), findsNothing);
    expect(find.text(tr('nd-cm-tab-access')), findsOneWidget);
    expect(find.byType(NdSwitch), findsNWidgets(4));
    expect(find.text(tr('nd-cm-perm-input')), findsOneWidget);
    expect(shapes.last, CmShape.card);

    await tester.tap(find.byTooltip(tr('nd-cm-bar-collapse')));
    await tester.pump();
    await tester.pump();
    expect(find.text(viewing, findRichText: true), findsOneWidget);
    expect(find.text(tr('nd-cm-perm-input')), findsNothing);
    expect(shapes.last, CmShape.bar);
  });

  testWidgets('before Allow the window stays the card, without a bar to '
      'collapse into', (tester) async {
    useLanguage('en');
    final asking = _client(1, 'Mara Jensen', 'neodesk-web-mwwuezpy',
        authorized: false, vouched: true);
    final shapes = <CmShape>[];
    await pumpScreen(tester, _window([asking], shapes: shapes),
        size: _windowSize);
    await tester.pump();
    expect(shapes.last, CmShape.card);
    expect(find.text(viewing, findRichText: true), findsNothing);
    expect(find.byTooltip(tr('nd-cm-bar-collapse')), findsNothing);
    // A second person asking while a session runs shows the card too
    expect(cmBarAllowed([_mara, _client(2, 'Jo', '828416401', authorized: false)]),
        isFalse);
    expect(cmBarAllowed([_mara]), isTrue);
    expect(cmBarAllowed([_client(1, 'Mara', '1', disconnected: true)]), isFalse);
  });

  testWidgets('after a request is allowed the window is the bar again, '
      'even when it was expanded before', (tester) async {
    useLanguage('en');
    final allowed = ValueNotifier(true);
    await pumpScreen(
        tester,
        ValueListenableBuilder<bool>(
          valueListenable: allowed,
          builder: (_, a, __) => CmBarOrCard(
            barAllowed: a,
            bar: (expand) => _bar([_mara], expand),
            card: (collapse) => _card([_mara], collapse),
          ),
        ),
        size: _windowSize);
    await tester.tap(find.byTooltip(tr('nd-cm-bar-expand')));
    await tester.pump();
    expect(find.text(viewing, findRichText: true), findsNothing);
    // A second person asks: the card with Allow and Decline
    allowed.value = false;
    await tester.pump();
    expect(find.text(viewing, findRichText: true), findsNothing);
    // Allowed: the bar
    allowed.value = true;
    await tester.pump();
    expect(find.text(viewing, findRichText: true), findsOneWidget);
  });

  testWidgets('several people: the bar counts them, expanding shows a tab each',
      (tester) async {
    useLanguage('en');
    final two = [
      _mara,
      // The same supporter's file transfer is one more connection, not one
      // more person
      _client(2, 'Mara Jensen', 'neodesk-web-mwwuezpy',
          vouched: true, file: true),
      _client(3, 'Jo Berg', '828416401', vouched: true),
    ];
    await pumpScreen(tester, _window(two), size: _windowSize);
    expect(find.text('2 people are connected'), findsOneWidget);
    await tester.tap(find.byTooltip(tr('nd-cm-bar-expand')));
    await tester.pump();
    expect(find.byKey(const ValueKey('tab-Mara Jensen')), findsOneWidget);
    expect(find.byKey(const ValueKey('tab-Jo Berg')), findsOneWidget);
    expect(cmBarPeople([two[0], two[1]], quickSupport: true), ['Mara Jensen']);
    useLanguage('de');
    expect(cmBarText(['a', 'b'], using: false).sentence,
        '2 Personen sind verbunden');
    useLanguage('en');
  });

  // A271: a name the server confirmed always wins; the caller's own name
  // counts only where the window shows it anyway
  test('the bar names people as the request names them', () {
    useLanguage('en');
    // Quick support: the confirmed supporter by name, anyone else unknown,
    // whatever name they send
    expect(cmBarPeople([_mara], quickSupport: true), ['Mara Jensen']);
    final claims = _client(1, 'Mara Jensen', 'neodesk-web-mwwuezpy');
    expect(cmBarPeople([claims], quickSupport: true), ['Someone unknown']);
    final desktop = _client(2, 'Mara Jensen', '828416401');
    expect(cmBarPeople([desktop], quickSupport: true), ['Someone unknown']);
    // The full client: a desktop caller keeps its name, the web console's
    // viewer needs the server's word
    expect(cmBarPeople([desktop], quickSupport: false), ['Mara Jensen']);
    expect(cmBarPeople([_client(3, '', '828416401')], quickSupport: false),
        ['828416401']);
    expect(cmBarPeople([claims], quickSupport: false), ['Someone unknown']);
    expect(cmBarPeople([_mara], quickSupport: false), ['Mara Jensen']);
    // Ended connections are not on the computer any more
    expect(
        cmBarPeople([_client(4, 'Jo', '1', disconnected: true)],
            quickSupport: false),
        isEmpty);
  });

  test('a tab names the caller as the request does: unknown unless confirmed (A271)',
      () {
    useLanguage('en');
    final refused = _client(3, 'admin', 'neodesk-web-k2j4h8', authorized: false);
    expect(cmTabLabel(refused, quickSupport: false), 'Someone unknown');
    expect(cmTabLabel(refused, quickSupport: true), 'Someone unknown');
    final confirmed = _client(4, 'Olga Operator', 'neodesk-web-k2j4h8', vouched: true);
    expect(cmTabLabel(confirmed, quickSupport: false), 'Olga Operator');
    // A desktop caller outside quick support keeps its name, as on the card
    final desktop = _client(5, 'Mara', '828416401', authorized: false);
    expect(cmTabLabel(desktop, quickSupport: false), 'Mara');
  });

  test('once connected the header says who confirmed the caller (A279)', () {
    useLanguage('en');
    CmCaller of(String via, {bool vouched = true}) => cmCaller(
        name: 'Olga Operator',
        peerId: 'neodesk-web-k2j4h8',
        vouched: vouched,
        vouchedVia: via,
        quickSupport: false,
        offersAllow: false);
    expect(cmConfirmedLine(of('console'), vouched: true),
        'From the NeoDesk web console');
    expect(cmConfirmedLine(of('desktop'), vouched: true), 'From the NeoDesk app');
    expect(cmConfirmedLine(of('', vouched: false), vouched: false), isNull);
  });

  testWidgets('the connected header shows the confirmed line', (tester) async {
    await pumpScreen(
        tester,
        const CmHeader(
            name: 'Olga Operator',
            subtitle: 'Connected for 1 min',
            note: 'From the NeoDesk app'),
        size: const Size(380, 120));
    expect(find.text('Connected for 1 min'), findsOneWidget);
    expect(find.text('From the NeoDesk app'), findsOneWidget);
  });

  test('the bar shapes the window only after the window\'s start sized it',
      () async {
    final started = Completer<void>();
    final applied = <CmShape>[];
    final shaper = CmWindowShaper((shape, _) async => applied.add(shape),
        started: started.future);
    // A session let in without Allow asks for the bar before the start
    // sized the window as the card
    final asked = shaper.shape(CmShape.bar);
    await Future<void>.delayed(Duration.zero);
    expect(applied, isEmpty);
    started.complete();
    await asked;
    expect(applied, [CmShape.bar]);
    await shaper.shape(CmShape.bar);
    expect(applied, [CmShape.bar], reason: 'the same shape is set once');
    shaper.forget();
    await shaper.shape(CmShape.bar);
    expect(applied, [CmShape.bar, CmShape.bar]);
  });

  test('Chat and Files belong to the selected remote session', () {
    final file = _client(2, 'Mara Jensen', 'neodesk-web-mwwuezpy',
        vouched: true, file: true);
    expect(cmBarClient([file, _mara], 0)?.id, 1);
    expect(cmBarClient([file, _mara], 1)?.id, 1);
    expect(cmBarClient([file], 0)?.id, 2);
    expect(cmBarClient([_client(1, 'a', '1', authorized: false)], 0), isNull);
  });

  testWidgets('the bar says "is using your computer" while input arrives',
      (tester) async {
    useLanguage('en');
    await pumpScreen(tester, _bar([_mara], () {}, using: true),
        size: _barSize);
    expect(find.text('Mara Jensen is using your computer', findRichText: true),
        findsOneWidget);
    useLanguage('de');
    expect(cmBarText(['Mara'], using: true).sentence, 'Mara benutzt deinen Computer');
    useLanguage('en');
  });

  testWidgets('the bar is said when it appears and its controls are reached '
      'by Tab with their names', (tester) async {
    useLanguage('en');
    final said = recordAnnouncements(tester);
    final calls = <String>[];
    var expanded = 0;
    await pumpScreen(
        tester, _bar([_mara], () => expanded++, calls: calls, files: true),
        size: _barSize);
    await tester.pump();
    expect(said.map((a) => a.message), contains(viewing));
    expect(said.firstWhere((a) => a.message == viewing).assertive, isTrue);
    final reached = <String>[];
    for (var i = 0; i < 6; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      final focus = FocusManager.instance.primaryFocus?.context;
      final label = focus == null
          ? null
          : (focus.findAncestorWidgetOfExactType<NdButton>()?.label ??
              focus.findAncestorWidgetOfExactType<NdIconButton>()?.tooltip);
      if (label != null && !reached.contains(label)) reached.add(label);
    }
    expect(reached, [
      tr('nd-qs-files-count', [2]),
      translate('Chat'),
      tr('nd-stop'),
      tr('nd-cm-bar-expand'),
    ]);
    await tester.tap(find.text(tr('nd-stop')));
    await tester.tap(find.text(translate('Chat')));
    expect(calls, ['stop', 'chat']);
    // Each control has its name for the screen reader
    final semantics = tester.ensureSemantics();
    for (final name in reached) {
      expect(find.bySemanticsLabel(name), findsOneWidget, reason: name);
    }
    semantics.dispose();
  });

  forBothThemes('connection bar', (tester, b) async {
    await pumpScreen(tester, _bar([_mara], () {}, files: true),
        size: _barSize, brightness: b, accent: fernAccent);
    await shot(tester, 'client-cm-bar', b);
  });

  forBothThemes('connection bar with files', (tester, b) async {
    await pumpScreen(
        tester,
        _bar([_mara], () {},
            files: true,
            panel: CmBarPanel(
              title: tr('nd-qs-files'),
              onClose: () {},
              child: CmFileList(jobs: _jobs()),
            )),
        size: _barPanelSize,
        brightness: b,
        accent: fernAccent);
    expect(find.text(r'C:\Users\jo\Desktop\error.log'), findsOneWidget);
    // Newest first
    expect(
        tester.getTopLeft(find.text(r'C:\Users\jo\Desktop\error.log')).dy <
            tester
                .getTopLeft(find.text(r'C:\Users\jo\Downloads\printer-driver.zip'))
                .dy,
        isTrue);
    await shot(tester, 'client-cm-bar-files', b);
  });

  forBothThemes('connection bar expanded', (tester, b) async {
    await pumpScreen(tester, _card([_mara], () {}),
        size: _cardSize, brightness: b, accent: fernAccent);
    await shot(tester, 'client-cm-bar-expanded', b);
  });
}
