// What a failed pull of the Devices tab means for the account, and what the
// tab says about it (L500, L507).

import 'package:flutter_hbb/common/widgets/nd/nd_window.dart' show tr;

/// The server refused a sealed request (its replay check). That says
/// nothing about the account token.
const kSecureEnvelopeRejected = 'secure_envelope_rejected';

/// No NeoDesk service took the window's call to seal it
/// (src/hbbs_http/sealed_calls.rs).
const kServiceUnavailable = 'neodesk_service_unavailable';

/// Whether an answer with [statusCode] and the error [error] means the
/// account token is no longer valid, so the person is signed out. A refused
/// envelope keeps a fresh sign-in.
bool groupPullSignsOut(int statusCode, String error) =>
    statusCode == 401 && error != kSecureEnvelopeRejected;

/// The Devices tab's sentence for the error [error] of a pull, null for an
/// error the tab shows as it is.
String? groupPullErrorText(String error) {
  switch (error) {
    case kServiceUnavailable:
      return tr('nd-devices-no-service');
    case kSecureEnvelopeRejected:
      return tr('nd-devices-envelope-rejected');
  }
  return null;
}
