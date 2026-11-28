// The window of an incoming-only client (the Support Agent) takes the size
// of Home's ID column whenever the column's size changes. The column sits
// in HomeLayout's padding, so the window has to include it, or each round
// makes the column, and with it the next window, narrower until only the
// title bar is left. And the column's box has to hold all of its content,
// or the window cuts off what lies below.

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common/widgets/nd/nd.dart';
import 'package:flutter_hbb/desktop/pages/home/home_widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

const _columnKey = ValueKey('this-computer');
const _footerKey = ValueKey('footer');

Widget _home() => HomeLayout(
      left: ThisComputerColumn(
        key: _columnKey,
        id: '418205739',
        password: 'k7m2qx9w',
        status: HomeStatus(NdStatusKind.wait, ''),
        onNewPassword: () async {},
        // A notice that can't tell its height before layout, like the
        // pairing QR code of a Support Agent without a server.
        notices: [
          LayoutBuilder(builder: (context, box) => const SizedBox(height: 240)),
        ],
        footer: const SizedBox(key: _footerKey, height: 36),
      ),
    );

void main() {
  testWidgets('the incoming-only window keeps its width round after round',
      (tester) async {
    // The runner opens the window at 800 x 600 before the first measurement.
    var window = const Size(800, 600);
    for (var round = 0; round < 6; round++) {
      await pumpScreen(tester, _home(), size: window);
      expect(tester.takeException(), isNull,
          reason: 'round $round in a window of $window');
      final column = tester.getSize(find.byKey(_columnKey));
      expect(column.width, HomeLayout.columnWidth,
          reason: 'round $round in a window of $window');
      window = HomeLayout.singleColumnSize(column.height);
    }
    // The column fits without scrolling: the window is as tall as it needs.
    final column = tester.getRect(find.byKey(_columnKey));
    expect(window.height, column.height + HomeLayout.singlePadding.vertical);
  });

  testWidgets('the incoming-only column holds everything down to its footer',
      (tester) async {
    await pumpScreen(tester, _home(), size: const Size(800, 600));
    expect(tester.takeException(), isNull);
    final column = tester.getRect(find.byKey(_columnKey));
    final footer = tester.getRect(find.byKey(_footerKey));
    expect(footer.bottom, lessThanOrEqualTo(column.bottom));
    expect(column.height, greaterThan(240 + 36));
  });
}
