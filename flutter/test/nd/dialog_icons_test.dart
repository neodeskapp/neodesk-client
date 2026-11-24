// The OS account step of "Password Required" (dialog.dart,
// enterPasswordDialog), put together from the widgets the dialog uses, to
// see its icons: the title's password glyph, the username and password
// fields and the buttons.

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/widgets/dialog.dart';
import 'package:flutter_hbb/common/widgets/nd/nd.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'fixtures.dart';
import 'harness.dart';

Widget _passwordDialog() => Builder(
      builder: (context) => withDialog(
        context,
        mainWindow(const SizedBox.expand()),
        CustomAlertDialog(
          title: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(NdIcons.password, color: MyTheme.accent),
              Text(translate('Password Required')).paddingOnly(left: 10),
            ],
          ),
          content: Column(children: [
            DialogTextField(
              title: translate(DialogTextField.kUsernameTitle),
              controller: TextEditingController(),
              prefixIcon: DialogTextField.kUsernameIcon,
              errorText: null,
            ),
            PasswordWidget(
                controller: TextEditingController(), autoFocus: false),
          ]),
          actions: [
            dialogButton('Cancel',
                icon: Icon(NdIcons.close), onPressed: () {}, isOutline: true),
            dialogButton('OK', icon: Icon(NdIcons.check), onPressed: () {}),
          ],
        ),
      ),
    );

void main() {
  forBothThemes('password dialog', (tester, b) async {
    await pumpScreen(tester, _passwordDialog(), size: mainSize, brightness: b);
    expect(find.byIcon(NdIcons.user), findsOneWidget);
    expect(find.byIcon(NdIcons.password), findsNWidgets(2));
    await shot(tester, 'client-dialog-password', b);
    // The dialog asks for focus on a zero timer at each build.
    await tester.pump(Duration.zero);
  });
}
