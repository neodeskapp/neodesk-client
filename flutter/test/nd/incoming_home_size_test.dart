// The window of an incoming-only client (the Support Agent) takes the size
// of Home's ID column each time the service status changes. The column sits
// in HomeLayout's padding, so the window has to include it, or each round
// makes the column, and with it the next window, narrower until only the
// title bar is left.

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common/widgets/nd/nd.dart';
import 'package:flutter_hbb/desktop/pages/home/home_widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

const _columnKey = ValueKey('this-computer');

Widget _home() => HomeLayout(
      left: ThisComputerColumn(
        key: _columnKey,
        id: '418205739',
        password: 'k7m2qx9w',
        status: HomeStatus(NdStatusKind.wait, ''),
        onNewPassword: () async {},
      ),
    );

void main() {
  testWidgets('the incoming-only window keeps its width round after round',
      (tester) async {
    // The runner opens the window at 800 x 600 before the first measurement.
    var window = const Size(800, 600);
    for (var round = 0; round < 6; round++) {
      await pumpScreen(tester, _home(), size: window);
      final column = tester.getSize(find.byKey(_columnKey));
      expect(column.width, HomeLayout.columnWidth,
          reason: 'round $round in a window of $window');
      expect(tester.takeException(), isNull,
          reason: 'round $round in a window of $window');
      window = HomeLayout.singleColumnSize(column.height);
    }
    // The column fits without scrolling: the window is as tall as it needs.
    final column = tester.getSize(find.byKey(_columnKey));
    expect(window.height,
        column.height + HomeLayout.singlePadding.vertical);
  });
}
