// Screens to compare the icons of the session window and the file transfer
// window with the session toolbar's: the window controls, the new tab
// button, the chat window's close and the file manager's buttons.
//
// The windows need a running session, so these are put together from the
// widgets the windows use (title bar, AddButton, BdToolbarButton,
// ChatWindowTitleBar, MenuButton, fileManagerIcon), laid out as the windows
// lay them out.

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/widgets/bd/bd.dart';
import 'package:flutter_hbb/common/widgets/overlay.dart';
import 'package:flutter_hbb/desktop/pages/file_manager_page.dart';
import 'package:flutter_hbb/desktop/widgets/bd_toolbar_button.dart';
import 'package:flutter_hbb/desktop/widgets/menu_button.dart';
import 'package:flutter_hbb/desktop/widgets/tabbar_widget.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'fixtures.dart';
import 'harness.dart';

List<ThemeExtension<dynamic>> _appExtensions(BdColors c) =>
    [ColorThemeExtension.from(c), TabbarTheme.from(c)];

/// The title bar of a session or file transfer window with one tab.
Widget _titleBar(String label, Widget lead) => BdTitleBar(
      brand: const BdLogoMark(size: 18),
      tabs: [
        BdWindowTab(
            label: label, leading: lead, selected: true, onClose: () {}),
      ],
      actions: const [AddButton()],
      controls: BdWindowControls(
          onMinimize: () {}, onMaximize: () {}, onClose: () {}),
    );

Widget _sessionTabLead() => Row(mainAxisSize: MainAxisSize.min, children: [
      const Icon(BdIcons.desktopWindows, size: 18),
      const SizedBox(width: 4),
      getConnectionIcon(true, true, size: 18),
    ]);

Widget _toolbar(BuildContext context) {
  final c = context.bd;
  return Column(mainAxisSize: MainAxisSize.min, children: [
    Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: c.bgFloat,
        borderRadius: BdSize.r,
        border: Border.all(color: c.rule),
        boxShadow: c.shadowFloat,
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        BdToolbarButton(
            icon: BdIcons.keyboard,
            label: tr('bd-tb-keyboard'),
            onPressed: () {}),
        BdToolbarButton(
            icon: BdIcons.folder, label: tr('bd-tb-files'), onPressed: () {}),
        BdToolbarButton(icon: BdIcons.chat, label: 'Chat', onPressed: () {}),
        BdToolbarButton(
            icon: BdIcons.fullscreen,
            label: tr('bd-tb-full-screen'),
            onPressed: () {}),
        BdToolbarButton(
            icon: BdIcons.moreHoriz, label: tr('bd-tb-more'), onPressed: () {}),
        Container(
            width: 1,
            height: 24,
            margin: const EdgeInsets.symmetric(horizontal: 6),
            color: c.rule),
        BdToolbarButton(
            icon: BdIcons.callEnd,
            label: tr('bd-tb-end'),
            danger: true,
            onPressed: () {}),
      ]),
    ),
    // The handle under the toolbar: drag, full screen, hide.
    Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: c.bgFloat,
        border: Border.all(color: c.rule),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(4)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(BdIcons.dragIndicator, size: 20, color: c.textMuted),
        const SizedBox(width: 8),
        const Icon(BdIcons.fullscreen, size: 20),
        const SizedBox(width: 8),
        const Icon(BdIcons.expandLess, size: 20),
      ]),
    ),
  ]);
}

Widget _chatWindow(BuildContext context) {
  final c = context.bd;
  Widget bubble(String text, bool me) => Align(
        alignment: me ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          constraints: const BoxConstraints(maxWidth: 210),
          decoration: BoxDecoration(
              color: me ? c.accentTint : c.bgSubtle, borderRadius: BdSize.r),
          child: Text(text, style: context.bdText.small),
        ),
      );
  return Container(
    decoration: BoxDecoration(
      color: c.bg,
      border: Border.all(color: c.rule),
      boxShadow: c.shadowFloat,
    ),
    child: Column(children: [
      ChatWindowTitleBar(focused: true.obs, onClose: () {}),
      Expanded(
        child: ListView(padding: const EdgeInsets.all(12), children: [
          bubble("I'm opening the printer settings now.", true),
          bubble("OK. It's the printer in the hallway.", false),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.all(8),
        child: Row(children: [
          Expanded(
            child: Container(
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              alignment: Alignment.centerLeft,
              decoration: BoxDecoration(
                  border: Border.all(color: c.border), borderRadius: BdSize.r),
              child: Text('Write a message',
                  style: context.bdText.small.copyWith(color: c.textMuted)),
            ),
          ),
          const SizedBox(width: 6),
          Icon(BdIcons.send, size: 20, color: c.accent),
        ]),
      ),
    ]),
  );
}

Widget _sessionWindow() => Builder(
      builder: (context) => BdWindowFrame(
        titleBar: _titleBar('Reception PC', _sessionTabLead()),
        child: Container(
          color: context.bd.canvas,
          child: Stack(children: [
            Align(
              alignment: Alignment.topCenter,
              child: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: _toolbar(context)),
            ),
            Positioned(
                right: 24,
                top: 120,
                width: 320,
                height: 380,
                child: _chatWindow(context)),
          ]),
        ),
      ),
    );

/// One side of the file manager: its two rows of buttons and a few files.
Widget _filePane(BuildContext context, {required bool local}) {
  final label = Theme.of(context).tabBarTheme.labelColor;
  final card = Theme.of(context).cardColor;
  final hover = Theme.of(context).hoverColor;
  Widget button(IconData icon, String tip) => MenuButton(
      tooltip: tip,
      onPressed: () {},
      color: card,
      hoverColor: hover,
      child: fileManagerIcon(icon, label));
  Widget row(IconData icon, String name, String size) => Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(children: [
          fileManagerIcon(icon, label),
          const SizedBox(width: 6),
          Expanded(child: Text(name, style: context.bdText.small)),
          Text(size, style: context.bdText.small),
        ]),
      );
  final send = ElevatedButton.icon(
    onPressed: () {},
    icon: local
        ? Text(translate('Send'))
        : Icon(BdIcons.arrowBack, size: 20, color: context.bd.onAccent),
    label: local
        ? Icon(BdIcons.arrowForward, size: 20, color: context.bd.onAccent)
        : Text(translate('Receive')),
  );
  return Container(
    margin: const EdgeInsets.all(16),
    padding: const EdgeInsets.all(8),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(
          width: 50,
          height: 50,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
              color: context.bd.accent, borderRadius: BorderRadius.circular(8)),
          child: getPlatformImage(local ? 'Windows' : 'Linux'),
        ),
        const SizedBox(width: 8),
        Text(translate(local ? 'Local Computer' : 'Remote Computer')),
      ]),
      const SizedBox(height: 15),
      Row(children: [
        button(BdIcons.arrowBack, 'Back'),
        button(BdIcons.arrowUpward, 'Parent directory'),
        Expanded(
          child: Container(
            height: 32,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
                color: card, borderRadius: BorderRadius.circular(8)),
            child: Row(children: [
              Text(local ? 'C:' : 'home', style: context.bdText.small),
              Icon(BdIcons.chevronRight, color: label),
              Text(local ? 'Users' : 'mara', style: context.bdText.small),
            ]),
          ),
        ),
        button(BdIcons.search, 'Search'),
        button(BdIcons.refresh, 'Refresh File'),
      ]),
      Row(children: [
        button(BdIcons.home, 'Home'),
        button(BdIcons.createNewFolder, 'Create Folder'),
        button(BdIcons.delete, 'Delete'),
        button(BdIcons.moreVert, 'More'),
        const Spacer(),
        send,
      ]).marginOnly(top: 8),
      const SizedBox(height: 8),
      if (local) row(BdIcons.hardDrive, 'C:', ''),
      row(BdIcons.folder, 'Documents', ''),
      row(BdIcons.folder, 'Pictures', ''),
      row(BdIcons.description, 'printer-setup.txt', '2 KB'),
      row(BdIcons.description, 'invoice-0425.pdf', '184 KB'),
    ]),
  );
}

Widget _fileTransferWindow() => Builder(
      builder: (context) => BdWindowFrame(
        titleBar:
            _titleBar('Reception PC', const Icon(BdIcons.folder, size: 18)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(flex: 3, child: _filePane(context, local: true)),
          Expanded(flex: 3, child: _filePane(context, local: false)),
          Expanded(
            flex: 2,
            child: Container(
              margin: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(8)),
              child: Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(BdIcons.swapHoriz,
                          size: 40,
                          color: Theme.of(context).tabBarTheme.labelColor)
                      .paddingOnly(bottom: 10),
                  Text(translate('No transfers in progress')),
                ]),
              ),
            ),
          ),
        ]),
      ),
    );

/// A menu with a plain item and one that opens a submenu, open.
Widget _menu(MenuController controller) => Builder(
      builder: (context) => Align(
        alignment: Alignment.topLeft,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: MenuAnchor(
            controller: controller,
            style: bdMenuStyle(context),
            menuChildren: [
              BdMenuItem(label: 'Fit window', onPressed: () {}),
              BdSubmenu(label: 'Image quality', children: [
                BdMenuItem(label: 'Best', onPressed: () {}),
              ]),
            ],
            child: const SizedBox(width: 10, height: 10),
          ),
        ),
      ),
    );

void main() {
  forBothThemes('session window with the chat open', (tester, b) async {
    await pumpScreen(tester, _sessionWindow(),
        size: mainSize, brightness: b, extra: _appExtensions);
    expect(find.byType(AddButton), findsOneWidget);
    await shot(tester, 'client-remote-chat', b);
  });

  forBothThemes('file transfer window', (tester, b) async {
    await pumpScreen(tester, _fileTransferWindow(),
        size: mainSize, brightness: b, extra: _appExtensions);
    await shot(tester, 'client-file-transfer', b);
  });

  forBothThemes('menu with a submenu', (tester, b) async {
    final controller = MenuController();
    await pumpScreen(tester, _menu(controller),
        size: const Size(360, 160), brightness: b);
    controller.open();
    await tester.pump();
    // The submenu mark is the chevron; Flutter's own arrow is transparent.
    expect(find.byIcon(BdIcons.chevronRight), findsOneWidget);
    final arrow = tester.element(find.byIcon(Icons.arrow_right));
    expect(IconTheme.of(arrow).color, Colors.transparent);
    await shot(tester, 'client-menu-submenu', b);
  });

  testWidgets('window controls, new tab and chat close draw 20 px icons',
      (tester) async {
    await pumpScreen(tester, _sessionWindow(),
        size: mainSize, extra: _appExtensions);
    List<double> sizes(IconData icon) =>
        tester.widgetList<Icon>(find.byIcon(icon)).map((i) => i.size!).toList()
          ..sort();
    expect(sizes(BdIcons.remove), [20]);
    expect(sizes(BdIcons.square), [20]);
    expect(sizes(BdIcons.add), [20]);
    // The tab's close stays at 16 next to its 13 px label; the window's
    // and the chat window's are 20.
    expect(sizes(BdIcons.close), [16, 20, 20]);
  });
}
