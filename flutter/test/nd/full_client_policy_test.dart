// The full desktop client under the organization's policy: ask_always
// offers Allow whatever the approve mode, and the settings page says in
// one read-only line that the organization's rule decides.

import 'package:flutter_hbb/desktop/pages/cm/cm_widgets.dart';
import 'package:flutter_hbb/desktop/pages/desktop_setting_page.dart'
    show orgApprovalLine;
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

void main() {
  test('ask_always offers Allow even when this computer takes passwords only',
      () {
    expect(cmOffersAllow('password', vouched: false), isFalse);
    expect(cmOffersAllow('password', vouched: false, askAlways: true), isTrue);
    expect(cmOffersAllow('click', vouched: false), isTrue);
  });

  test('the settings page names the organization\'s rule only when one applies',
      () {
    useLanguage('en');
    expect(orgApprovalLine('ask_always'),
        "Your organization's policy decides how sessions to this computer are accepted.");
    expect(orgApprovalLine('vouched'), orgApprovalLine('ask_always'));
    expect(orgApprovalLine(''), isNull);
    expect(orgApprovalLine('something else'), isNull);
    useLanguage('de');
    expect(orgApprovalLine('ask_always'),
        'Die Richtlinie deiner Organisation legt fest, wie Sitzungen auf diesem Computer angenommen werden.');
    useLanguage('en');
  });
}
