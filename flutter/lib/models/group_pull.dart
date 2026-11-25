// What the Devices tab says about a failed pull (L507).

import 'package:flutter_hbb/common/widgets/nd/nd_window.dart' show tr;

/// No NeoDesk service took the window's call to seal it
/// (src/hbbs_http/sealed_calls.rs).
const kServiceUnavailable = 'neodesk_service_unavailable';

/// The Devices tab's sentence for the error [error] of a pull, null for an
/// error the tab shows as it is.
String? groupPullErrorText(String error) {
  switch (error) {
    case kServiceUnavailable:
      return tr('nd-devices-no-service');
  }
  return null;
}
