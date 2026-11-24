// The free part of a custom title bar moves the window (L482). The bars of
// the main window and the connection manager are put together as the
// windows lay them out, since the windows themselves need the native side.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hbb/common/widgets/nd/nd.dart';
import 'package:flutter_test/flutter_test.dart';

class _Calls {
  int drags = 0;
  int taps = 0;
  int settings = 0;
}

/// The main window's bar (tabbar_widget.dart): the brand, the tab strip it
/// keeps offstage, then Settings and the window buttons outside the area.
Widget _mainBar(_Calls calls) => Row(children: [
      Expanded(
        child: NdTitleDragArea(
          onDragStart: () => calls.drags++,
          onTap: () => calls.taps++,
          child: Row(children: [
            const Padding(
              padding: EdgeInsets.only(left: 14, right: 12),
              child: Text('NeoDesk'),
            ),
            Expanded(
              child: Offstage(
                offstage: true,
                child: ListView(scrollDirection: Axis.horizontal),
              ),
            ),
          ]),
        ),
      ),
      TextButton(
        key: const Key('settings'),
        onPressed: () => calls.settings++,
        child: const Text('Settings'),
      ),
    ]);

/// The connection manager's bar (server_page.dart): the brand aligned left.
Widget _cmBar(_Calls calls) => Row(children: [
      Expanded(
        child: NdTitleDragArea(
          onDragStart: () => calls.drags++,
          child: const Padding(
            padding: EdgeInsets.only(left: 14),
            child: Align(
                alignment: Alignment.centerLeft, child: Text('NeoDesk')),
          ),
        ),
      ),
      const SizedBox(width: 46),
    ]);

Future<void> _pump(WidgetTester tester, Widget bar) => tester.pumpWidget(
    MaterialApp(home: Scaffold(body: SizedBox(height: 40, child: bar))));

/// A point in the empty middle of the bar, away from brand and buttons.
Offset _gap(WidgetTester tester) {
  final r = tester.getRect(find.byType(NdTitleDragArea));
  return Offset(r.left + r.width * 0.6, r.center.dy);
}

void main() {
  testWidgets('dragging the empty middle of the main bar moves the window',
      (tester) async {
    final calls = _Calls();
    await _pump(tester, _mainBar(calls));
    await tester.dragFrom(_gap(tester), const Offset(60, 20),
        kind: PointerDeviceKind.mouse);
    expect(calls.drags, 1);
  });

  testWidgets('a double click in the empty middle reaches the tap handler',
      (tester) async {
    final calls = _Calls();
    await _pump(tester, _mainBar(calls));
    await tester.tapAt(_gap(tester), kind: PointerDeviceKind.mouse);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tapAt(_gap(tester), kind: PointerDeviceKind.mouse);
    expect(calls.taps, 2);
  });

  testWidgets('Settings next to the area still takes its click',
      (tester) async {
    final calls = _Calls();
    await _pump(tester, _mainBar(calls));
    await tester.tap(find.byKey(const Key('settings')));
    expect(calls.settings, 1);
    expect(calls.drags, 0);
    expect(calls.taps, 0);
  });

  testWidgets('dragging the empty part of the connection manager bar moves it',
      (tester) async {
    final calls = _Calls();
    await _pump(tester, _cmBar(calls));
    await tester.dragFrom(_gap(tester), const Offset(60, 20),
        kind: PointerDeviceKind.mouse);
    expect(calls.drags, 1);
  });
}
