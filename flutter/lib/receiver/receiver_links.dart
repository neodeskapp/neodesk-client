// The links of the receiver (neodesk://help, neodesk://chat,
// neodesk://tickets/<id>): the tray's entries and the notifications open
// the home window's areas with them. In receiver mode no other link does
// anything but bring the window to the front: no settings, no connections
// to other computers (common.dart urlLinkToCmdArgs).

/// True in the receiver's main window (main.dart runReceiverApp).
bool ndReceiverMode = false;

/// Opens a link's page, its authority and path without the scheme
/// ("tickets/24"); set by the receiver's window.
void Function(String page)? ndReceiverOpen;

/// What a neodesk:// link of the receiver opens: its host and path,
/// "tickets/24" for neodesk://tickets/24.
String ndReceiverPage(Uri uri) =>
    [uri.authority, ...uri.pathSegments.where((s) => s.isNotEmpty)].join('/');
