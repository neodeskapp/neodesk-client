// The receiver's home window (receiver plan, step 4): exactly Get help,
// Messages and My tickets, the ticket form in the shape of the console's
// POST /api/tickets/nd, news about a ticket and new messages with their
// notification, count and page. With ND_SHOTS_DIR set it writes the
// screenshots of the pull request.

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common/widgets/nd/nd.dart'
    show NdTitleBar, NdTitleBrand, NdWindowControls, NdWindowFrame;
import 'package:flutter_hbb/desktop/pages/nd_chat_page.dart';
import 'package:flutter_hbb/models/nd_chat_model.dart';
import 'package:flutter_hbb/onboarding/onboarding_service.dart';
import 'package:flutter_hbb/receiver/receiver_home.dart';
import 'package:flutter_hbb/receiver/tickets_model.dart';
import 'package:flutter_hbb/receiver/tickets_view.dart';
import 'package:flutter_test/flutter_test.dart';

import 'chat_fakes.dart';
import 'harness.dart';

/// The console's device routes as a test double: answers the list and the
/// tickets it keeps, records every request.
class FakeConsole implements ReceiverBackend {
  final requests = <(String, String, Map<String, Object?>?)>[];
  final notes = <(String, String, String)>[];
  final tickets = <Map<String, Object?>>[];
  final comments = <int, List<Map<String, Object?>>>{};
  int status = 200;
  Map<String, String> person = const {
    'reporter': 'Mara Jensen',
    'os': 'Windows 11 Pro 24H2 (26100)',
  };

  List<Map<String, Object?>> posts(String path) => [
        for (final r in requests)
          if (r.$1 == 'POST' && r.$2 == path) r.$3 ?? const {}
      ];

  @override
  Future<NdTicketAnswer> request(String method, String path,
      [Map<String, Object?>? body]) async {
    requests.add((method, path, body));
    if (status != 200) return NdTicketAnswer(status, '');
    final one = RegExp(r'^/api/tickets/nd/(\d+)(/.*)?$').firstMatch(path);
    if (path == kNdTicketsPath && method == 'GET') {
      return NdTicketAnswer(
          200, jsonEncode({'tickets': tickets, 'total': tickets.length}));
    }
    if (path == kNdTicketsPath && method == 'POST') {
      final id = 24 + tickets.length;
      final t = ticket(id, (body?['description'] as String).split('\n').first,
          description: body?['description'] as String);
      tickets.add(t);
      return NdTicketAnswer(
          201, jsonEncode({'success': true, 'ticket_id': id, 'ticket': t}));
    }
    if (one != null) {
      final id = int.parse(one.group(1)!);
      final t = tickets.firstWhere((t) => t['id'] == id, orElse: () => {});
      if (t.isEmpty)
        return const NdTicketAnswer(404, '{"error":"Ticket not found"}');
      switch ((method, one.group(2))) {
        case ('GET', null):
          return NdTicketAnswer(
              200,
              jsonEncode({
                'ticket': t,
                'comments': comments[id] ?? [],
                'attachments': [
                  {
                    'id': 16,
                    'name': 'computer-info.json',
                    'type': 'application/json',
                    'size': 912,
                    'comment_id': null
                  },
                  {
                    'id': 17,
                    'name': 'screen-2026-11-27-101500.png',
                    'type': 'image/png',
                    'size': 482113,
                    'comment_id': null
                  },
                ],
              }));
        case ('POST', '/read'):
          t['unread'] = false;
          return const NdTicketAnswer(204, '');
        case ('POST', '/comments'):
          (comments[id] ??= []).add(comment(90 + (comments[id]?.length ?? 0),
              'Mara Jensen', body?['body'] as String,
              staff: false));
          return const NdTicketAnswer(201, '{"success":true}');
      }
    }
    return const NdTicketAnswer(404, '');
  }

  @override
  Future<int> download(String path, String to) async => 200;

  @override
  Future<Map<String, String>> about() async => person;

  @override
  void notify(String title, String body, String link) =>
      notes.add((title, body, link));
}

Map<String, Object?> ticket(int id, String title,
        {String status = 'open',
        bool unread = false,
        String description = '',
        String created = '2026-11-27 09:12:00'}) =>
    {
      'id': id,
      'title': title,
      'description': description.isEmpty ? title : description,
      'status': status,
      'priority': 'medium',
      'category': null,
      'device_id': device,
      'created_by': 'agent:$device',
      'assigned_to': null,
      'created_at': created,
      'updated_at': created,
      'source': 'device',
      'reporter': 'Mara Jensen',
      'last_reply_at': null,
      'unread': unread,
      'replies': 0,
    };

Map<String, Object?> comment(int id, String name, String body,
        {bool staff = true, String at = '2026-11-27 10:40:00'}) =>
    {
      'id': id,
      'author_name': name,
      'from': staff ? 'staff' : 'device',
      'body': body,
      'created_at': at,
    };

/// A picture of the screen and a file for the form, as real files.
class Files {
  Files() {
    dir = Directory.systemTemp.createTempSync('nd-rcv-test');
    picture = File('${dir.path}/screen-2026-11-27-101500.png')
      ..writeAsBytesSync(screenPng ?? base64Decode(_tinyPng));
    log = File('${dir.path}/printer-log.txt')
      ..writeAsStringSync('Error 0x0000011b while printing');
  }

  late final Directory dir;
  late final File picture;
  late final File log;

  NdTicketLocalFile get pictureFile =>
      NdTicketLocalFile(picture.path, picture.lengthSync());
  NdTicketLocalFile get logFile =>
      NdTicketLocalFile(log.path, log.lengthSync());

  /// A 2 x 2 PNG.
  static const _tinyPng =
      'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAEElEQVR4nGPQiFoARAwQCgAd5gSJoVLBMgAAAABJRU5ErkJggg==';

  /// A plain picture of a desktop with a window and a message box, for
  /// the screenshots (made once by [makeScreenPng]).
  static List<int>? screenPng;
}

/// Draws [Files.screenPng]: a desktop, a taskbar, a window and a message.
Future<void> makeScreenPng(WidgetTester tester) async {
  if (Files.screenPng != null) return;
  await tester.runAsync(() async {
    const w = 1280.0, h = 720.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    void rect(double l, double t, double r, double b, int color) => canvas
        .drawRect(Rect.fromLTRB(l, t, r, b), Paint()..color = Color(color));
    rect(0, 0, w, h, 0xFF2D4A63);
    rect(0, h - 48, w, h, 0xFF1F2328);
    rect(160, 90, 1000, 560, 0xFFF3F4F5);
    rect(160, 90, 1000, 126, 0xFFDDE1E2);
    rect(420, 240, 860, 420, 0xFFFFFFFF);
    rect(420, 240, 860, 272, 0xFFE9EBEC);
    rect(450, 300, 480, 330, 0xFFD93025);
    rect(500, 304, 800, 314, 0xFF9AA0A6);
    rect(500, 322, 720, 332, 0xFFBDC1C6);
    rect(740, 372, 840, 402, 0xFF00677A);
    final image = await recorder.endRecording().toImage(w.toInt(), h.toInt());
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    Files.screenPng = data!.buffer.asUint8List();
  });
}

class Home {
  Home(
      {List<Map<String, Object?>> tickets = const [],
      this.area = ReceiverArea.help}) {
    console.tickets.addAll([for (final t in tickets) Map.of(t)]);
    chatModel = NdChatModel(
        connect: server.connect,
        files: FakeFiles(),
        notify: (title, body) => chatNotes.add((title, body)),
        random: Random(1),
        now: () => t0.add(const Duration(minutes: 5)));
    chatModel.start();
    router = ReceiverRouter(area);
    // Read at once: file IO doesn't finish under the test's fake clock
    model = NdTicketsModel(
        backend: console,
        readFile: (path) async => File(path).readAsBytesSync());
  }

  final ReceiverArea area;
  final console = FakeConsole();
  final server = Server();
  final chatNotes = <(String, String)>[];
  late final NdChatModel chatModel;
  late final ReceiverRouter router;
  late final NdTicketsModel model;
  final onboarding = FakeOnboardingService();
  final files = Files();
  final picked = <List<NdTicketLocalFile>>[];
  var screenshots = 0;
  bool screenshotFails = false;

  Widget widget() => ReceiverHome(
        router: router,
        onboarding: onboarding,
        chat: chatModel,
        company: 'Fernhill Dental',
        messages: (_) => NdChatPage(
          model: chatModel,
          showClose: false,
          windowFocused: ValueNotifier(true),
          onClose: () {},
          actions: NdChatPageActions(
            pickFiles: () async => const [],
            saveFile: (_) async => '',
            picture: (_) async => null,
            openLink: (_) {},
            screenshot: () async =>
                NdChatLocalFile(files.picture.path, files.picture.lengthSync()),
          ),
        ),
        tickets: model,
        ticketActions: NdTicketActions(
          pickFiles: () async => picked.isEmpty ? const [] : picked.removeAt(0),
          screenshot: () async {
            screenshots++;
            return screenshotFails ? null : files.pictureFile;
          },
          saveFile: (_) async => '',
        ),
      );

  void openChat({List<Map<String, dynamic>> messages = const []}) {
    server.last.serve(welcome());
    server.last.serve({
      'type': 'history',
      'conversation_id': device,
      'before': '0',
      'more': false,
      'messages': messages,
      'reads': [],
    });
    server.last
        .serve({'type': 'helper', 'name': 'Anna Weber', 'state': 'open'});
  }
}

Future<Home> pumpHome(WidgetTester tester,
    {List<Map<String, Object?>> tickets = const [],
    ReceiverArea area = ReceiverArea.help,
    Brightness brightness = Brightness.light,
    String lang = 'en',
    bool framed = false}) async {
  final home = Home(tickets: tickets, area: area);
  // The screenshots show the window as the app draws it: the title bar
  // with the company's name from the branding, the window's buttons.
  final screen = framed
      ? NdWindowFrame(
          titleBar: NdTitleBar(
            height: 36,
            brand: const NdTitleBrand(serverName: 'Fernhill Dental'),
            controls: NdWindowControls(
                height: 36,
                onMinimize: () {},
                onMaximize: () {},
                onClose: () {}),
          ),
          child: home.widget())
      : home.widget();
  await pumpScreen(tester, screen,
      size: Size(960, framed ? 660 : 624), brightness: brightness, lang: lang);
  await settle(tester);
  addTearDown(() async {
    home.chatModel.dispose();
    home.files.dir.deleteSync(recursive: true);
  });
  return home;
}

/// Lets the fake console's answers arrive.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump();
  }
}

Future<void> takeDown(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 5));
}

/// Every text, tooltip and label on the screen.
List<String> shownTexts(WidgetTester tester) => [
      for (final w in tester.widgetList<Text>(find.byType(Text)))
        w.data ?? w.textSpan?.toPlainText() ?? '',
      for (final w in tester.widgetList<RichText>(find.byType(RichText)))
        w.text.toPlainText(),
      for (final w in tester.widgetList<Semantics>(find.byType(Semantics)))
        w.properties.label ?? '',
      for (final w in tester.widgetList<Tooltip>(find.byType(Tooltip)))
        w.message ?? '',
    ].where((t) => t.isNotEmpty).toList();

void main() {
  testWidgets(
      'the home window shows exactly Get help, Messages and My tickets, and nothing for settings or other computers',
      (tester) async {
    final home = await pumpHome(tester);
    final nav = find.byWidgetPredicate((w) =>
        w.key is ValueKey<String> &&
        (w.key as ValueKey<String>).value.startsWith('rcv-nav-') &&
        !(w.key as ValueKey<String>).value.startsWith('rcv-nav-new-'));
    expect(nav, findsNWidgets(3));
    expect(find.text('Get help'), findsWidgets);
    expect(find.text('Messages'), findsOneWidget);
    expect(find.text('My tickets'), findsOneWidget);

    // What the full client's home has: settings, the ID and password,
    // connecting to another computer, the address book
    const outside = [
      'settings',
      'password',
      'address book',
      'remote',
      'your id',
      'connect to',
      'recent sessions',
      'favorites',
    ];
    const outsideExact = ['ID', 'Connect', 'Settings'];
    for (final area in ReceiverArea.values) {
      home.router.go(area);
      await settle(tester);
      final texts = shownTexts(tester);
      expect(texts, isNotEmpty);
      for (final label in texts) {
        expect(outsideExact.contains(label.trim()), isFalse,
            reason: '"$label" in ${area.name}');
        for (final word in outside) {
          expect(label.toLowerCase().contains(word), isFalse,
              reason: '"$label" in ${area.name}');
        }
      }
    }
    expect(find.byKey(const ValueKey('rcv-tickets')), findsOneWidget);

    // Get help starts quick support with the code
    home.router.go(ReceiverArea.help);
    await settle(tester);
    await tester.enterText(find.byType(TextField), '7kq4-m2xd');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('rcv-help-start')));
    await tester.pump();
    expect(home.onboarding.calls, ['redeemSupport:7kq4-m2xd']);
    expect(
        find.text('Starting. A new window opens in a moment.'), findsOneWidget);
    await takeDown(tester);
  });

  testWidgets('Get help takes a support code or link, not a join link',
      (tester) async {
    final home = await pumpHome(tester);
    await tester.enterText(
        find.byType(TextField), 'https://help.fernhill.example/join/7KQ4M2XD');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('rcv-help-start')));
    await tester.pump();
    expect(home.onboarding.calls, isEmpty);
    await tester.enterText(
        find.byType(TextField), 'https://help.fernhill.example/s/7KQ4M2XD');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('rcv-help-start')));
    await tester.pump();
    expect(home.onboarding.calls,
        ['redeemSupport:https://help.fernhill.example/s/7KQ4M2XD']);
    await takeDown(tester);
  });

  testWidgets(
      'the ticket form sends what is wrong, the person, the system, the picture and the files as POST /api/tickets/nd takes them',
      (tester) async {
    final home = await pumpHome(tester, area: ReceiverArea.tickets);
    await tester.tap(find.byKey(const ValueKey('rcv-ticket-new')));
    await tester.pump();
    await tester.enterText(find.byType(TextField),
        'The printer prints nothing\nIt says error 0x0000011b.');
    await tester.pump();

    // The picture: taken, shown, removed, taken again
    await tester.tap(find.byKey(const ValueKey('rcv-form-picture')));
    await settle(tester);
    expect(home.screenshots, 1);
    expect(find.byKey(const ValueKey('rcv-form-preview')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('rcv-form-picture-remove')));
    await tester.pump();
    expect(find.byKey(const ValueKey('rcv-form-preview')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('rcv-form-picture')));
    await settle(tester);

    home.picked.add([home.files.logFile]);
    await tester.tap(find.byKey(const ValueKey('rcv-form-files')));
    await settle(tester);
    expect(find.textContaining('printer-log.txt'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const ValueKey('rcv-form-send')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('rcv-form-send')));
    await settle(tester);

    final sent = home.console.posts(kNdTicketsPath);
    expect(sent, hasLength(1));
    expect(sent.single, {
      'description': 'The printer prints nothing\nIt says error 0x0000011b.',
      'reporter': 'Mara Jensen',
      'os': 'Windows 11 Pro 24H2 (26100)',
      'screenshot': {
        'name': 'screen-2026-11-27-101500.png',
        'type': 'image/png',
        'data_b64': base64Encode(home.files.picture.readAsBytesSync()),
      },
      'files': [
        {
          'name': 'printer-log.txt',
          'type': 'text/plain',
          'data_b64':
              base64Encode(utf8.encode('Error 0x0000011b while printing')),
        }
      ],
    });
    // The new ticket opens with the conversation, and says it arrived
    expect(find.text('Sent. We answer here, and you get a notification.'),
        findsOneWidget);
    expect(find.text('Status: Received'), findsOneWidget);
    await takeDown(tester);
  });

  testWidgets('without a picture or files the ticket carries none',
      (tester) async {
    final home = await pumpHome(tester, area: ReceiverArea.tickets);
    await tester.tap(find.byKey(const ValueKey('rcv-ticket-new')));
    await tester.pump();
    await tester.enterText(
        find.byType(TextField), 'Outlook asks for my password all the time');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('rcv-form-send')));
    await settle(tester);
    expect(home.console.posts(kNdTicketsPath).single, {
      'description': 'Outlook asks for my password all the time',
      'reporter': 'Mara Jensen',
      'os': 'Windows 11 Pro 24H2 (26100)',
    });
    await takeDown(tester);
  });

  testWidgets(
      'news about a ticket notifies, counts on My tickets, and its link opens that ticket and marks it read',
      (tester) async {
    final home = await pumpHome(tester, tickets: [
      ticket(24, 'The printer prints nothing', status: 'in_progress'),
      ticket(23, 'New mouse', status: 'resolved'),
    ]);
    expect(find.byKey(const ValueKey('rcv-nav-new-My tickets')), findsNothing);

    // Staff answered ticket 24
    home.console.tickets.first['unread'] = true;
    home.console.comments[24] = [
      comment(81, 'Anna Weber',
          'I sent a new driver to your computer. Please try again.'),
    ];
    await home.model.onFrame({
      'type': 'ticket.updated',
      'ticket_id': 24,
      'status': 'in_progress',
      'unread': true,
    });
    await settle(tester);
    expect(home.console.notes, [
      ('nd-rcv-note-ticket', 'nd-rcv-note-ticket-body', 'tickets/24'),
    ]);
    expect(
        find.byKey(const ValueKey('rcv-nav-new-My tickets')), findsOneWidget);
    expect(find.text('1 new'), findsOneWidget);

    // The notification's click
    expect(home.router.open('tickets/24'), isTrue);
    await settle(tester);
    expect(find.byKey(const ValueKey('rcv-ticket-24')), findsOneWidget);
    expect(find.text('The printer prints nothing'), findsWidgets);
    expect(find.text('I sent a new driver to your computer. Please try again.'),
        findsOneWidget);
    expect(find.text('Status: Being worked on'), findsOneWidget);
    expect(home.console.posts('/api/tickets/nd/24/read'), hasLength(1));
    expect(find.byKey(const ValueKey('rcv-nav-new-My tickets')), findsNothing);
    // The server's own file about the computer isn't listed
    expect(find.textContaining('computer-info.json'), findsNothing);
    expect(find.textContaining('screen-2026-11-27-101500.png'), findsOneWidget);

    // Looking at it: no notification for it
    home.console.tickets.first['unread'] = true;
    await home.model.onFrame({
      'type': 'ticket.updated',
      'ticket_id': 24,
      'status': 'resolved',
      'unread': true
    });
    await settle(tester);
    expect(home.console.notes, hasLength(1));

    // With a tray, the tray notifies
    home.model.closeTicket();
    home.model.othersNotify = true;
    await home.model.onFrame({
      'type': 'ticket.updated',
      'ticket_id': 23,
      'status': 'closed',
      'unread': true
    });
    await settle(tester);
    expect(home.console.notes, hasLength(1));
    await takeDown(tester);
  });

  testWidgets('a reply goes to the ticket and shows in its conversation',
      (tester) async {
    final home = await pumpHome(tester,
        tickets: [ticket(24, 'The printer prints nothing')],
        area: ReceiverArea.tickets);
    await tester.tap(find.byKey(const ValueKey('rcv-ticket-row-24')));
    await settle(tester);
    await tester.enterText(find.byType(TextField), 'It works again, thank you');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('rcv-ticket-send')));
    await settle(tester);
    expect(home.console.posts('/api/tickets/nd/24/comments'), [
      {'body': 'It works again, thank you'}
    ]);
    expect(find.text('It works again, thank you'), findsOneWidget);
    await takeDown(tester);
  });

  testWidgets(
      'a new message notifies, counts on Messages, and the chat link opens Messages',
      (tester) async {
    final home = await pumpHome(tester);
    home.openChat();
    await tester.pump();
    home.server.last.serve({
      'type': 'message.new',
      'message': msg(5, text: 'Is the printer on?'),
    });
    await tester.pump();
    expect(home.chatNotes, [('Anna Weber', 'Is the printer on?')]);
    expect(find.byKey(const ValueKey('rcv-nav-new-Messages')), findsOneWidget);
    expect(find.byKey(const ValueKey('rcv-messages')), findsNothing);
    expect(home.router.open('chat'), isTrue);
    await settle(tester);
    expect(find.byKey(const ValueKey('rcv-messages')), findsOneWidget);
    expect(find.text('Is the printer on?'), findsOneWidget);
    // No back button: the areas are beside it
    expect(find.byTooltip('Close chat'), findsNothing);
    await takeDown(tester);
  });

  testWidgets('Messages takes a picture of the screen as a file of the message',
      (tester) async {
    final home = await pumpHome(tester, area: ReceiverArea.messages);
    home.openChat();
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('nd-chat-screenshot')));
    await settle(tester);
    expect(find.textContaining('screen-2026-11-27-101500.png'), findsOneWidget);
    await takeDown(tester);
  });

  test('links open their page and nothing else', () {
    final r = ReceiverRouter();
    expect(r.open('tickets/24'), isTrue);
    expect((r.area, r.ticket), (ReceiverArea.tickets, 24));
    expect(r.open('help'), isTrue);
    expect(r.area, ReceiverArea.help);
    expect(r.open('messages'), isTrue);
    expect(r.area, ReceiverArea.messages);
    expect(r.open('settings'), isFalse);
    expect(r.open('connection/new/123456789'), isFalse);
    expect(r.area, ReceiverArea.messages);
  });

  test('the console\'s times read as UTC', () {
    expect(ndTicketTime('2026-11-27 09:12:00'),
        DateTime.utc(2026, 11, 27, 9, 12).toLocal());
    expect(ndTicketTime('2026-11-27T09:12:00.000Z'),
        DateTime.utc(2026, 11, 27, 9, 12).toLocal());
    expect(ndTicketTime(null), isNull);
  });

  group('screenshots', () {
    forBothThemes('home window', (tester, b) async {
      final home = await pumpHome(tester, brightness: b, framed: true);
      home.openChat();
      await tester.pump();
      home.server.last.serve({
        'type': 'message.new',
        'message': msg(5, text: 'Is the printer on?')
      });
      await tester.pump();
      await shot(tester, 'receiver-home', b);
      await takeDown(tester);
    });

    // The line about unattended access under Get help (A279)
    forBothThemes('home window with unattended access', (tester, b) async {
      final home = await pumpHome(tester, brightness: b, framed: true);
      home.onboarding.emit(home.onboarding.current.copyWith(
          unattended: const UnattendedAccess(
              schedule: UnattendedSchedule(
                  days: ['mon', 'tue', 'wed', 'thu', 'fri'],
                  start: '8:00',
                  end: '18:00'))));
      await tester.pump();
      expect(find.textContaining('Mon to Fri 8:00 to 18:00'), findsOneWidget);
      await shot(tester, 'receiver-home-unattended', b);
      await takeDown(tester);
    });

    forBothThemes('messages', (tester, b) async {
      final home = await pumpHome(tester,
          brightness: b, area: ReceiverArea.messages, framed: true);
      home.openChat(messages: [
        msg(1,
            from: me,
            text:
                'The printer in the office prints nothing since this morning.'),
        msg(2,
            text: 'Hi Mara, I am looking at it. Is the printer switched on?'),
      ]);
      home.server.last.serve({
        'type': 'read',
        'reader': {'kind': 'device', 'id': device},
        'up_to': '2',
      });
      await tester.pump();
      await shot(tester, 'receiver-messages', b);
      await takeDown(tester);
    });

    forBothThemes('ticket form', (tester, b) async {
      await makeScreenPng(tester);
      final home = await pumpHome(tester,
          brightness: b, area: ReceiverArea.tickets, framed: true);
      await tester.tap(find.byKey(const ValueKey('rcv-ticket-new')));
      await tester.pump();
      await tester.enterText(find.byType(TextField),
          'The printer prints nothing. It says error 0x0000011b.');
      await tester.tap(find.byKey(const ValueKey('rcv-form-picture')));
      await settle(tester);
      home.picked.add([home.files.logFile]);
      await tester.tap(find.byKey(const ValueKey('rcv-form-files')));
      await settle(tester);
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      await shot(tester, 'receiver-ticket-form', b);
      await takeDown(tester);
    });

    forBothThemes('ticket with a reply', (tester, b) async {
      final home = await pumpHome(tester,
          brightness: b,
          area: ReceiverArea.tickets,
          framed: true,
          tickets: [
            ticket(24, 'The printer prints nothing',
                status: 'in_progress',
                unread: true,
                description:
                    'The printer prints nothing. It says error 0x0000011b.'),
            ticket(23, 'New mouse',
                status: 'resolved', created: '2026-11-20 14:03:00'),
          ]);
      home.console.comments[24] = [
        comment(81, 'Anna Weber',
            'I sent a new driver to your computer. Please print a test page and tell me if it works.'),
      ];
      await shot(tester, 'receiver-tickets', b);
      home.router.open('tickets/24');
      await settle(tester);
      await shot(tester, 'receiver-ticket', b);
      await takeDown(tester);
    });
  });
}
