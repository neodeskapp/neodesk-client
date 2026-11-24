// Texts that say what the product does: the password a connection asks
// for, and where a code's server address is.

import 'dart:io';

import 'package:flutter_hbb/common.dart' show translate;
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

void main() {
  test('the password step names no product, the other computer may run either',
      () {
    final dialog = File('lib/common/widgets/dialog.dart').readAsStringSync();
    expect(dialog, isNot(contains("'verify_rustdesk_password_tip'")));
    expect(dialog, contains("translate('nd-verify-password-tip')"));
    for (final lang in ['en', 'de']) {
      useLanguage(lang);
      final text = translate('nd-verify-password-tip');
      expect(text, isNot('nd-verify-password-tip'), reason: lang);
      // The client shows its own name wherever a text says RustDesk.
      expect(text, isNot(contains('RustDesk')), reason: lang);
      expect(text, isNot(contains('NeoDesk')), reason: lang);
    }
  });

  test('the server address hint says where the invite page shows it', () {
    useLanguage('en');
    final hint = translate('nd-invite-server-hint');
    expect(hint, contains('under the code on the invite page'));
    expect(hint, contains('https://'));
    useLanguage('de');
    expect(translate('nd-invite-server-field'), 'Serveradresse');
    expect(translate('nd-invite-server-hint'), contains('unter dem Code'));
  });
}
