// original cm window in Sciter version.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common/widgets/nd/nd.dart';
import 'package:flutter_hbb/desktop/pages/cm/cm_widgets.dart';
import 'package:flutter_hbb/common/widgets/audio_input.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/desktop/widgets/tabbar_widget.dart';
import 'package:flutter_hbb/models/chat_model.dart';
import 'package:flutter_hbb/models/cm_file_model.dart';
import 'package:flutter_hbb/utils/platform_channel.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import '../../common.dart';
import '../../common/widgets/chat_page.dart';
import '../../models/file_model.dart';
import '../../models/platform_model.dart';
import '../../models/server_model.dart';
import '../../native/window_frame.dart';

/// Set only by this window's own close control, and only once the user has confirmed. Any other
/// way the window can go - a session logout closing every window, the window manager, a native
/// title-bar button this app does not draw - leaves it false, which is the honest answer:
/// nothing in that close says who asked for it. It lives at file scope because the control that
/// sets it (`ConnectionManagerState`) and the handler that reads it (`_DesktopServerPageState`)
/// are different widgets.
bool _cmClosedByOperator = false;

class DesktopServerPage extends StatefulWidget {
  const DesktopServerPage({Key? key}) : super(key: key);

  @override
  State<DesktopServerPage> createState() => _DesktopServerPageState();
}

class _DesktopServerPageState extends State<DesktopServerPage>
    with WindowListener, AutomaticKeepAliveClientMixin {
  final tabController = gFFI.serverModel.tabController;

  _DesktopServerPageState() {
    gFFI.ffiModel.updateEventListener(gFFI.sessionId, "");
    Get.put<DesktopTabController>(tabController);
    tabController.onRemoved = (_, id) {
      onRemoveId(id);
    };
  }

  @override
  void initState() {
    windowManager.addListener(this);
    super.initState();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowClose() {
    // Other platforms keep the old behaviour exactly: the ambiguity this guards against is a
    // Linux session logout, which closes every window in the session.
    final byOperator = _cmClosedByOperator || !isLinux;
    Future.wait([gFFI.serverModel.closeAll(byOperator: byOperator), gFFI.close()]).then((_) {
      if (isMacOS) {
        RdPlatformChannel.instance.terminate();
      } else {
        windowManager.setPreventClose(false);
        windowManager.close();
      }
    });
    super.onWindowClose();
  }

  void onRemoveId(String id) {
    if (tabController.state.value.tabs.isEmpty) {
      windowManager.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: gFFI.serverModel),
        ChangeNotifierProvider.value(value: gFFI.chatModel),
      ],
      child: Consumer<ServerModel>(
        builder: (context, serverModel, child) => ConnectionManager(),
      ),
    );
  }

  @override
  bool get wantKeepAlive => true;
}

/// The card's window: background, border and on Linux the drawn frame. The
/// bar has none of them.
Widget _cardFrame(BuildContext context, Widget child) {
  final body = Scaffold(backgroundColor: context.nd.bg, body: child);
  return isLinux
      ? buildVirtualWindowFrame(context, body)
      : workaroundWindowBorder(
          context,
          Container(
            decoration:
                BoxDecoration(border: Border.all(color: context.nd.rule)),
            child: body,
          ));
}

/// Gives the window a shape once, and again only when it changes. It waits
/// until the window's start gave it its first size (showCmWindow or
/// hideCmWindow at startup), so that size can't land after the bar's: a
/// session let in without Allow starts as the bar at once, and the start's
/// card size (380 wide) used to win and squeeze the bar's sentence.
class CmWindowShaper {
  CmWindowShaper(this._apply, {required Future<void> started})
      : _started = started;

  final Future<void> Function(CmShape shape, CmShape? before) _apply;
  final Future<void> _started;

  /// The shape the window has now; null when something else set its size.
  CmShape? current;

  Future<void> shape(CmShape shape) async {
    await _started;
    final before = current;
    if (before == shape) return;
    current = shape;
    await _apply(shape, before);
  }

  /// Something else sized the window: the next build shapes it again.
  void forget() => current = null;
}

/// Completed by the window's start once it gave the window its first size.
final cmWindowStarted = Completer<void>();

final cmWindowShaper = CmWindowShaper(_applyCmShape, started: cmWindowStarted.future);

/// Whether the window has the bar's frame (none) now.
bool _cmFramelessBar = false;

/// Gives the connection window [shape] (through [cmWindowShaper]).
Future<void> applyCmShape(CmShape shape) => cmWindowShaper.shape(shape);

/// The bar is frameless, always on top, at the top centre of the screen
/// and not in the taskbar; the card gets its frame back at the top right.
/// Between the bar and the bar with a panel only the height changes, so a
/// bar the person moved stays there.
Future<void> _applyCmShape(CmShape shape, CmShape? before) async {
  final bar = shape != CmShape.card;
  final barBefore = before != null && before != CmShape.card;
  try {
    if (bar != _cmFramelessBar && isWindows) {
      if (bar) {
        await windowManager.setAsFrameless();
        await windowManager.setHasShadow(false);
      } else {
        await windowManager.setTitleBarStyle(TitleBarStyle.hidden);
      }
      setMainWindowPlain(bar);
    }
    _cmFramelessBar = bar;
    await windowManager.setResizable(true);
    await windowManager.setSize(switch (shape) {
      CmShape.card => kConnectionManagerWindowSizeClosedChat,
      CmShape.bar => kCmBarWindow,
      CmShape.barPanel => kCmBarWindowPanel,
    });
    if (bar != barBefore || before == null) {
      await windowManager.setAlwaysOnTop(true);
      await windowManager.setSkipTaskbar(bar);
      await windowManager
          .setAlignment(bar ? Alignment.topCenter : Alignment.topRight);
    }
    await windowManager.setResizable(false);
  } catch (e) {
    debugPrint('connection window shape: $e');
  }
}

/// A connection someone was let in on and that still runs.
bool cmActive(Client c) => c.authorized && !c.disconnected;

/// Whether the window may be the bar: someone was let in, and nobody waits
/// for Allow or Decline (a request always shows the card).
bool cmBarAllowed(Iterable<Client> clients) =>
    clients.any(cmActive) && !clients.any((c) => !c.authorized && !c.disconnected);

/// The connection the bar's Chat and Files belong to: the selected one when
/// it runs, else the first remote session, else the first that runs.
Client? cmBarClient(List<Client> clients, int selected) {
  if (selected >= 0 &&
      selected < clients.length &&
      cmActive(clients[selected]) &&
      clients[selected].type_() == ClientType.remote) {
    return clients[selected];
  }
  return clients.firstWhereOrNull(
          (c) => cmActive(c) && c.type_() == ClientType.remote) ??
      clients.firstWhereOrNull(cmActive);
}

/// The people on this computer now, each named as the window names a
/// caller (cmCaller, A271): a name the server confirmed, otherwise the
/// caller's own only where the rules allow it. Several connections of one
/// caller (the screen and the files) count once.
List<String> cmBarPeople(Iterable<Client> clients,
    {required bool quickSupport}) {
  final seen = <String>{};
  final names = <String>[];
  for (final c in clients.where(cmActive)) {
    if (!seen.add(c.peerId)) continue;
    names.add(cmCaller(
            name: c.name,
            peerId: c.peerId,
            vouched: c.vouched,
            vouchedVia: c.vouchedVia,
            quickSupport: quickSupport,
            offersAllow: false)
        .name);
  }
  return names;
}

/// The name on a connection's tab: the window's name for the caller
/// (cmCaller, A271), never a name nobody confirmed where the window calls
/// the caller unknown.
String cmTabLabel(Client c, {required bool quickSupport}) => cmCaller(
        name: c.name,
        peerId: c.peerId,
        vouched: c.vouched,
        vouchedVia: c.vouchedVia,
        quickSupport: quickSupport,
        offersAllow: false)
    .name;

class ConnectionManager extends StatefulWidget {
  @override
  State<StatefulWidget> createState() => ConnectionManagerState();
}

class ConnectionManagerState extends State<ConnectionManager>
    with WidgetsBindingObserver {
  final RxBool _controlPageBlock = false.obs;

  ConnectionManagerState() {
    gFFI.serverModel.tabController.onSelected = (client_id_str) {
      final client_id = int.tryParse(client_id_str);
      if (client_id != null) {
        final client =
            gFFI.serverModel.clients.firstWhereOrNull((e) => e.id == client_id);
        if (client != null) {
          gFFI.chatModel.changeCurrentKey(MessageKey(client.peerId, client.id));
          if (client.unreadChatMessageCount.value > 0) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              client.unreadChatMessageCount.value = 0;
              gFFI.chatModel.showChatPage(MessageKey(client.peerId, client.id));
            });
          }
          windowManager.setTitle(getWindowNameWithId(client.peerId));
          gFFI.cmFileModel.updateCurrentClientId(client.id);
        }
      }
    };
    gFFI.chatModel.isConnManager = true;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      if (!allowRemoteCMModification()) {
        shouldBeBlocked(_controlPageBlock, null);
      }
    }
  }

  @override
  void initState() {
    gFFI.serverModel.updateClientState();
    WidgetsBinding.instance.addObserver(this);
    super.initState();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Files moves the bar has seen, to open the files when a new one comes.
  int _seenJobs = 0;

  @override
  Widget build(BuildContext context) {
    final serverModel = Provider.of<ServerModel>(context);
    final chat = Provider.of<ChatModel>(context);
    final clients = serverModel.clients;
    final primary =
        cmBarClient(clients, serverModel.tabController.state.value.selected);
    final barAllowed = primary != null && cmBarAllowed(clients);
    final tab = primary == null ? CmTab.access : chat.cmTabOf(primary.id);
    return CmBarOrCard(
      barAllowed: barAllowed,
      panelOpen: barAllowed && tab != CmTab.access,
      onShape: applyCmShape,
      bar: (expand) => _bar(context, serverModel, primary!, tab, expand),
      card: (collapse) => _cardFrame(context, _card(serverModel, collapse)),
    );
  }

  /// The bar of the session, with the chat or the files of [primary] open
  /// under it when its tab is Chat or Files.
  Widget _bar(BuildContext context, ServerModel model, Client primary,
      CmTab tab, VoidCallback expand) {
    final clients = model.clients;
    void setTab(CmTab t) =>
        checkClickTime(primary.id, () => gFFI.chatModel.setCMTab(primary.id, t));
    // The files of every connection of this caller (the screen and the
    // files are two connections)
    final ids = clients
        .where((c) => cmActive(c) && c.peerId == primary.peerId)
        .map((c) => c.id)
        .toList();
    final hasFileSession =
        clients.any((c) => ids.contains(c.id) && c.type_() == ClientType.file);
    final canChat = primary.type_() == ClientType.remote ||
        primary.type_() == ClientType.file ||
        primary.type_() == ClientType.camera;
    final people = cmBarPeople(clients,
        quickSupport: bind.mainOnboardIsQuickSupport());
    final using = clients.any((c) => cmActive(c) && c.inputActive);
    final chatOpen = tab == CmTab.chat;
    // With the chat open only its message field takes keyboard focus while
    // keys a remote computer types can reach this window (A269)
    final guard = chatOpen && cmRemoteKeysReachHere(clients);
    return Obx(() {
      final jobs = gFFI.cmFileModel.jobsOf(ids);
      if (jobs.length > _seenJobs) {
        // A new file opens the files, as a new message opens the chat
        WidgetsBinding.instance.addPostFrameCallback(
            (_) => gFFI.chatModel.setCMTab(primary.id, CmTab.files));
      }
      _seenJobs = jobs.length;
      final showFiles = hasFileSession || jobs.isNotEmpty;
      final name = people.length == 1 ? people.first : '';
      final content = CmBarWindow(
        bar: ExcludeFocus(
          excluding: guard,
          child: CmSessionBar(
            text: cmBarText(people, using: using),
            onDrag: () => windowManager.startDragging(),
            onFiles: showFiles
                ? () => setTab(tab == CmTab.files ? CmTab.access : CmTab.files)
                : null,
            filesOpen: tab == CmTab.files,
            filesLabel: jobs.isEmpty
                ? tr('nd-qs-files')
                : tr('nd-qs-files-count', [jobs.length]),
            onChat: canChat
                ? () => setTab(chatOpen ? CmTab.access : CmTab.chat)
                : null,
            onStop: () => checkClickTime(primary.id, () {
              // Every session ends: the bar speaks for everyone on it
              for (final c in clients.where((c) => !c.disconnected)) {
                bind.cmCloseConnection(connId: c.id);
              }
            }),
            onExpand: () => checkClickTime(primary.id, () {
              gFFI.chatModel.setCMTab(primary.id, CmTab.access);
              expand();
            }),
          ),
        ),
        panel: switch (tab) {
          CmTab.chat => CmBarPanel(
              title: name.isEmpty ? translate('Chat') : tr('nd-qs-chat-with', [name]),
              closeFocusable: !guard,
              onClose: () => setTab(CmTab.access),
              child: ChatPage(type: ChatPageType.desktopCM),
            ),
          CmTab.files => CmBarPanel(
              title: tr('nd-qs-files'),
              onClose: () => setTab(CmTab.access),
              child: CmFileList(jobs: jobs),
            ),
          CmTab.access => null,
        },
      );
      if (allowRemoteCMModification()) return content;
      return cmControlPageBlock(
          child: content,
          block: _controlPageBlock,
          remoteMaySendKeys: cmRemoteMaySendKeys(clients),
          systemBlocksRemoteKeys: cmSystemBlocksRemoteKeys(),
          chatOpen: chatOpen);
    });
  }

  /// The card: Waiting, or one tab per person with the request or the
  /// session. [collapse] turns it back into the bar.
  Widget _card(ServerModel serverModel, VoidCallback? collapse) {
    return serverModel.clients.isEmpty
        ? Column(
            children: [
              buildTitleBar(),
              Expanded(
                child: Center(
                  child: Text(translate("Waiting"), style: context.ndText.body),
                ),
              ),
            ],
          )
        : DesktopTab(
              showTitle: false,
              showMaximize: false,
              showMinimize: true,
              // Closing would end every session: minimize only.
              showClose: false,
              onWindowCloseButton: handleWindowCloseButton,
              controller: serverModel.tabController,
              selectedBorderColor: null,
              maxLabelWidth: 100,
              tail: collapse == null
                  ? null
                  : NdIconButton(
                      icon: NdIcons.expandLess,
                      tooltip: tr('nd-cm-bar-collapse'),
                      color: context.nd.text,
                      iconSize: 20,
                      onPressed: () {
                        final client = cmBarClient(serverModel.clients,
                            serverModel.tabController.state.value.selected);
                        checkClickTime(client?.id ?? 0, () {
                          if (client != null) {
                            gFFI.chatModel.setCMTab(client.id, CmTab.access);
                          }
                          collapse();
                        });
                      }),
              tabBuilder: (key, icon, label, themeConf) {
                final client = serverModel.clients
                    .firstWhereOrNull((client) => client.id.toString() == key);
                return Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Tooltip(
                        message: key,
                        waitDuration: Duration(seconds: 1),
                        child: label),
                    unreadMessageCountBuilder(client?.unreadChatMessageCount)
                        .marginOnly(left: 4),
                  ],
                );
              },
              // The window keeps one size: Access, Chat and Files are tabs
              // of the card, so opening one never resizes the window.
              pageViewBuilder: (pageView) => Container(
                color: context.nd.bg,
                child: allowRemoteCMModification()
                    ? pageView
                    : Consumer<ServerModel>(
                        builder: (_, model, __) => Consumer<ChatModel>(
                            builder: (_, chat, __) => cmControlPageBlock(
                                child: pageView,
                                block: _controlPageBlock,
                                remoteMaySendKeys:
                                    cmRemoteMaySendKeys(model.clients),
                                systemBlocksRemoteKeys:
                                    cmSystemBlocksRemoteKeys(),
                                chatOpen: _chatOpen(model, chat)))),
              ),
            );
  }

  /// Whether the selected card shows its chat.
  bool _chatOpen(ServerModel model, ChatModel chat) {
    final selected = model.tabController.state.value.selected;
    if (selected < 0 || selected >= model.clients.length) return false;
    return chat.cmTabOf(model.clients[selected].id) == CmTab.chat;
  }

  Widget buildTitleBar() {
    return Container(
      height: kDesktopRemoteTabBarHeight,
      decoration: BoxDecoration(
        color: context.nd.titlebar,
        border: Border(bottom: BorderSide(color: context.nd.rule)),
      ),
      child: Row(
        children: [
          Expanded(
            child: NdTitleDragArea(
              onDragStart: () => windowManager.startDragging(),
              child: Padding(
                padding: const EdgeInsets.only(left: 14),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: NdTitleBrand(
                      title: cmWindowTitle(bind.mainGetAppNameSync(),
                          quickSupport: bind.mainOnboardIsQuickSupport())),
                ),
              ),
            ),
          ),
          NdWinButton(
            glyph: NdWinGlyph.minimize,
            tooltip: translate('Minimize'),
            height: kDesktopRemoteTabBarHeight - 1,
            onTap: () => windowManager.minimize(),
          ),
        ],
      ),
    );
  }

  Widget buildScrollJumper() {
    final offstage = gFFI.serverModel.clients.length < 2;
    final sc = gFFI.serverModel.tabController.state.value.scrollController;
    return Offstage(
        offstage: offstage,
        child: Row(
          children: [
            ActionIcon(
                icon: NdIcons.chevronLeft, iconSize: 22, onTap: sc.backward),
            ActionIcon(
                icon: NdIcons.chevronRight, iconSize: 22, onTap: sc.forward),
          ],
        ));
  }

  Future<bool> handleWindowCloseButton() async {
    var tabController = gFFI.serverModel.tabController;
    final connLength = tabController.length;
    if (connLength <= 1) {
      _cmClosedByOperator = true;
      windowManager.close();
      return true;
    } else {
      final bool res;
      if (!option2bool(kOptionEnableConfirmClosingTabs,
          bind.mainGetLocalOption(key: kOptionEnableConfirmClosingTabs))) {
        res = true;
      } else {
        res = await closeConfirmDialog();
      }
      if (res) {
        // After the dialog, never before it: an external close while it is open must not
        // inherit an intent the user had not expressed yet.
        _cmClosedByOperator = true;
        windowManager.close();
      }
      return res;
    }
  }
}

Widget buildConnectionCard(Client client) {
  return Consumer<ServerModel>(
    builder: (context, value, child) =>
        _CmCard(key: ValueKey(client.id), client: client),
  );
}

/// One person: the request with Allow and Decline, or once connected what
/// they may do and Stop session (DESIGN.md, Connection manager).
class _CmCard extends StatefulWidget {
  const _CmCard({Key? key, required this.client}) : super(key: key);
  final Client client;

  @override
  State<_CmCard> createState() => _CmCardState();
}

class _CmCardState extends State<_CmCard> with AutomaticKeepAliveClientMixin {
  Client get client => widget.client;
  final _seconds = 0.obs;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (client.authorized && !client.disconnected) _seconds.value++;
    });
    // Call onSelected in post frame callback, since we cannot guarantee that the callback will not call setState.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      gFFI.serverModel.tabController.onSelected?.call(client.id.toString());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  bool get wantKeepAlive => true;

  String? get _kind {
    switch (client.type_()) {
      case ClientType.terminal:
        return translate('Terminal');
      case ClientType.file:
        return translate('Transfer file');
      case ClientType.camera:
        return translate('View camera');
      default:
        return client.portForward.isNotEmpty
            ? 'Port Forward: ${client.portForward}'
            : null;
    }
  }

  List<CmPermission> _permissions() {
    final canModify =
        bind.mainGetBuildinOption(key: kOptionEnablePermChangeInAcceptWindow) !=
            'N';
    CmPermission perm(String label, bool value, String name,
        void Function(bool) apply) {
      return CmPermission(
        label: label,
        value: value,
        onChanged: canModify
            ? (v) => checkClickTime(client.id, () {
                  // Turning a permission on takes effect here first, so this
                  // window's controls leave keyboard focus before the remote
                  // computer can type (cmControlPageBlock); turning it off
                  // goes to the server first.
                  void here() {
                    setState(() => apply(v));
                    gFFI.serverModel.clientPermissionChanged();
                  }

                  if (v) here();
                  bind.cmSwitchPermission(
                      connId: client.id, name: name, enabled: v);
                  if (!v) here();
                })
            : null,
      );
    }

    final t = client.type_();
    if (t == ClientType.file ||
        t == ClientType.portForward ||
        t == ClientType.terminal ||
        client.disconnected) {
      return [];
    }
    if (t == ClientType.camera) {
      return [
        perm(tr('nd-cm-perm-sound'), client.audio, 'audio',
            (v) => client.audio = v),
        perm(tr('nd-cm-perm-record'), client.recording, 'recording',
            (v) => client.recording = v),
      ];
    }
    return [
      perm(tr('nd-cm-perm-input'), client.keyboard, 'keyboard',
          (v) => client.keyboard = v),
      perm(tr('nd-cm-perm-clipboard'), client.clipboard, 'clipboard',
          (v) => client.clipboard = v),
      perm(tr('nd-cm-perm-files'), client.file, 'file',
          (v) => client.file = v),
      perm(tr('nd-cm-perm-sound'), client.audio, 'audio',
          (v) => client.audio = v),
      perm(tr('nd-cm-perm-restart'), client.restart, 'restart',
          (v) => client.restart = v),
      perm(tr('nd-cm-perm-record'), client.recording, 'recording',
          (v) => client.recording = v),
      if (isWindows)
        perm(tr('nd-cm-perm-block'), client.blockInput, 'block_input',
            (v) => client.blockInput = v),
      if (bind.mainSupportedPrivacyModeImpls() != '[]')
        perm(tr('nd-cm-perm-privacy'), client.privacyMode, 'privacy_mode',
            (v) => client.privacyMode = v),
    ];
  }

  /// Who asks, as the window names them: the helper the server vouched
  /// for, or a caller nobody confirmed (A271).
  CmCaller _caller(BuildContext context) => cmCaller(
      name: client.name,
      peerId: client.peerId,
      vouched: client.vouched,
      vouchedVia: client.vouchedVia,
      quickSupport: bind.mainOnboardIsQuickSupport(),
      offersAllow: cmOffersAllow(Provider.of<ServerModel>(context).approveMode,
          vouched: client.vouched, askAlways: client.askAlways));

  /// The open tab. A file transfer has no Access tab and opens on Files.
  CmTab _tab(BuildContext context) => cmShownTab(
      Provider.of<ChatModel>(context).cmTabOf(client.id),
      file: client.type_() == ClientType.file,
      camera: client.type_() == ClientType.camera);

  /// In quick support the quick support window shows the end of the
  /// session, so a card whose connection ended goes away by itself instead
  /// of waiting for Close.
  bool _closing = false;
  void _closeWhenEnded() {
    if (_closing || !client.disconnected || !bind.mainOnboardIsQuickSupport()) {
      return;
    }
    _closing = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await bind.cmRemoveDisconnectedConnection(connId: client.id);
      if (await bind.cmGetClientsLength() == 0) {
        windowManager.close();
      }
    });
  }

  Widget _avatar(String name, {bool own = true}) {
    // The picture a caller sends is its own claim: only for a caller shown
    // by its name
    if (!own) return NdAvatar(name: name, size: 48);
    return buildAvatarWidget(
          avatar: client.avatar,
          size: 48,
          borderRadius: NdSize.radius,
          fallback: NdAvatar(name: name, size: 48),
        ) ??
        NdAvatar(name: name, size: 48);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    _closeWhenEnded();
    // The card names the caller as the bar does (A271)
    final caller = _caller(context);
    final own = !caller.unknown;
    final name = caller.name;
    final permissions = _permissions();
    Widget body;
    Widget foot = _CmControlPanel(client: client);
    if (!client.authorized) {
      body = SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        child: CmRequestBody(
          focusOnArrival: true,
          header: CmHeader(
              name: name,
              subtitle: caller.line,
              mono: caller.lineIsId,
              kind: _kind,
              avatar: _avatar(name, own: own)),
          warning: caller.warning,
          name: name,
          permissions: permissions,
        ),
      );
    } else {
      final type = client.type_();
      final hasTabs = !client.disconnected &&
          (type == ClientType.remote ||
              type == ClientType.file ||
              type == ClientType.camera);
      final tab = _tab(context);
      // With the chat open only its message field takes keyboard focus
      // while keys a remote computer types can reach this window
      final guard = hasTabs &&
          tab == CmTab.chat &&
          cmRemoteKeysReachHere(Provider.of<ServerModel>(context).clients);
      foot = ExcludeFocus(excluding: guard, child: foot);
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Obx(() => CmHeader(
                    name: name,
                    subtitle: client.disconnected
                        ? translate('Disconnected')
                        : cmConnectedFor(Duration(seconds: _seconds.value)),
                    note: cmConfirmedLine(caller, vouched: client.vouched),
                    kind: _kind,
                    avatar: _avatar(name, own: own))),
                const SizedBox(height: 16),
                if (hasTabs)
                  Obx(() => ExcludeFocus(
                      excluding: guard,
                      child: CmTabs(
                        value: tab,
                        showAccess: type != ClientType.file,
                        showFiles: type != ClientType.camera,
                        unread: client.unreadChatMessageCount.value,
                        onChanged: (tab) => checkClickTime(client.id,
                            () => gFFI.chatModel.setCMTab(client.id, tab)),
                      ))),
              ],
            ),
          ),
          Expanded(
            child: CmTabBody(
              tab: hasTabs ? tab : CmTab.access,
              access: permissions,
              chat: (_) => ChatPage(type: ChatPageType.desktopCM),
              files: (_) => _FileTransferLogPage(),
            ),
          ),
        ],
      );
    }
    return CmScreen(body: body, foot: foot);
  }
}

const double buttonBottomMargin = 8;

class _CmControlPanel extends StatelessWidget {
  final Client client;

  const _CmControlPanel({Key? key, required this.client}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return client.authorized
        ? client.disconnected
            ? buildDisconnected(context)
            : buildAuthorized(context)
        : buildUnAuthorized(context);
  }

  Widget _row(List<Widget> children) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(child: children[i]),
          ],
        ]),
      );

  buildAuthorized(BuildContext context) {
    final bool canElevate = bind.cmCanElevate();
    final model = Provider.of<ServerModel>(context);
    final showElevation = canElevate &&
        model.showElevation &&
        client.type_() == ClientType.remote;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (client.inVoiceCall)
          _row([
            Builder(
              builder: (bctx) => NdButton(
                label: translate('Audio Input'),
                icon: NdIcons.mic,
                block: true,
                onPressed: () => checkClickTime(client.id, () async {
                  final box = bctx.findRenderObject() as RenderBox;
                  final pos = box.localToGlobal(Offset.zero);
                  await _audioInputMenu(bctx, pos);
                }),
              ),
            ),
            NdButton(
              label: translate('Stop voice call'),
              icon: NdIcons.callEnd,
              kind: NdButtonKind.dangerQuiet,
              block: true,
              onPressed: () => checkClickTime(client.id, closeVoiceCall),
            ),
          ]),
        if (client.incomingVoiceCall)
          _row([
            NdButton.primary(
              label: translate('Accept'),
              icon: NdIcons.call,
              block: true,
              onPressed: () =>
                  checkClickTime(client.id, () => handleVoiceCall(true)),
            ),
            NdButton(
              label: translate('Dismiss'),
              icon: NdIcons.phoneDisabled,
              kind: NdButtonKind.dangerQuiet,
              block: true,
              onPressed: () =>
                  checkClickTime(client.id, () => handleVoiceCall(false)),
            ),
          ]),
        if (client.fromSwitch)
          _row([
            NdButton(
              label: translate('Switch Sides'),
              icon: NdIcons.reply,
              block: true,
              onPressed: () =>
                  checkClickTime(client.id, () => handleSwitchBack(context)),
            ),
          ]),
        if (showElevation)
          _row([
            NdButton(
              label: translate('Elevate'),
              icon: NdIcons.security,
              block: true,
              onPressed: () => checkClickTime(client.id, () {
                handleElevate(context);
                windowManager.minimize();
              }),
            ),
          ]),
        NdButton(
          label: tr('nd-cm-stop'),
          kind: NdButtonKind.danger,
          size: NdButtonSize.lg,
          block: true,
          onPressed: () => checkClickTime(client.id, handleDisconnect),
        ),
      ],
    );
  }

  Future<void> _audioInputMenu(BuildContext context, Offset pos) async {
    final devicesInfo = await AudioInput.getDevicesInfo(true, true);
    List<String> devices = devicesInfo['devices'] as List<String>;
    if (devices.isEmpty) {
      msgBox(
        gFFI.sessionId,
        'custom-nocancel-info',
        'Prompt',
        'no_audio_input_device_tip',
        '',
        gFFI.dialogManager,
      );
      return;
    }
    String currentDevice = devicesInfo['current'] as String;
    if (!context.mounted) return;
    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx, pos.dy),
      items: devices
          .map((d) => PopupMenuItem<String>(
                value: d,
                onTap: () => AudioInput.setDevice(d, true, true),
                child: Row(children: [
                  SizedBox(
                    width: 18,
                    child: d == currentDevice
                        ? Icon(NdIcons.check,
                            size: 18, color: context.nd.accent)
                        : null,
                  ),
                  const SizedBox(width: 10),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                        maxWidth:
                            kConnectionManagerWindowSizeClosedChat.width - 100),
                    child: Text(d,
                        overflow: TextOverflow.ellipsis, maxLines: 1),
                  ),
                ]),
              ))
          .toList(),
    );
  }

  buildDisconnected(BuildContext context) {
    return NdButton.primary(
      label: translate('Close'),
      size: NdButtonSize.lg,
      block: true,
      onPressed: () => checkClickTime(client.id, handleClose),
    );
  }

  buildUnAuthorized(BuildContext context) {
    final bool canElevate = bind.cmCanElevate();
    final model = Provider.of<ServerModel>(context);
    final showElevation = canElevate &&
        model.showElevation &&
        client.type_() == ClientType.remote;
    // In quick support only a caller the server vouched for (A271)
    final showAccept =
        cmOffersAllow(model.approveMode,
            vouched: client.vouched, askAlways: client.askAlways);
    return CmRequestActions(
      onDecline: () => checkClickTime(client.id, handleDisconnect),
      // Once allowed, the window turns into the bar at the top of the screen
      onAllow: showAccept
          ? () => checkClickTime(client.id, () => handleAccept(context))
          : null,
      onAllowElevated: showElevation && showAccept
          ? () => checkClickTime(client.id, () {
                handleAccept(context);
                handleElevate(context);
              })
          : null,
    );
  }

  void handleDisconnect() {
    bind.cmCloseConnection(connId: client.id);
  }

  void handleAccept(BuildContext context) {
    final model = Provider.of<ServerModel>(context, listen: false);
    model.sendLoginResponse(client, true);
  }

  void handleElevate(BuildContext context) {
    final model = Provider.of<ServerModel>(context, listen: false);
    model.setShowElevation(false);
    bind.cmElevatePortable(connId: client.id);
  }

  void handleClose() async {
    await bind.cmRemoveDisconnectedConnection(connId: client.id);
    if (await bind.cmGetClientsLength() == 0) {
      windowManager.close();
    }
  }

  void handleSwitchBack(BuildContext context) {
    bind.cmSwitchBack(connId: client.id);
  }

  void handleVoiceCall(bool accept) {
    bind.cmHandleIncomingVoiceCall(id: client.id, accept: accept);
  }

  void closeVoiceCall() {
    bind.cmCloseVoiceCall(id: client.id);
  }
}

void checkClickTime(int id, Function() callback) async {
  if (allowRemoteCMModification()) {
    callback();
    return;
  }
  var clickCallbackTime = DateTime.now().millisecondsSinceEpoch;
  await bind.cmCheckClickTime(connId: id);
  Timer(const Duration(milliseconds: 120), () async {
    var d = clickCallbackTime - await bind.cmGetClickTime();
    if (d > 120) callback();
  });
}

/// Whether a remote computer may type on this computer now: an accepted
/// remote control session with keyboard permission. Only such a session has
/// its keys typed here (the server's peer_keyboard_enabled).
bool cmRemoteMaySendKeys(Iterable<Client> clients) => clients.any((c) =>
    c.authorized &&
    !c.disconnected &&
    c.keyboard &&
    c.type_() == ClientType.remote);

/// True when this computer drops keys a remote computer types before they
/// reach the connection manager (Windows: src/cm_remote_keys.rs).
bool cmSystemBlocksRemoteKeys() =>
    bind.mainGetCommonSync(key: 'cm-remote-keys-blocked') == 'true';

/// The connection manager's control page when the remote side may not
/// change it.
///
/// - While the remote computer's mouse is over the window ([block]), the
///   page takes no clicks and no focus.
/// - The local keyboard reaches Allow, Decline, the switches and Stop
///   session only when no key from a remote computer can reach them: no
///   remote computer may type ([remoteMaySendKeys] false), or this computer
///   drops the keys remote computers type before they reach this window
///   ([systemBlocksRemoteKeys], Windows). Otherwise the page takes no
///   keyboard focus, as before.
/// - With the chat open ([chatOpen]) the page lets its message field take
///   focus, so the person can write; the card then keeps every other
///   control out of the keyboard's reach itself (cmRemoteKeysReachHere).
/// - Every action still checks that the click or key did not come from the
///   remote computer (checkClickTime), as a second layer.
Widget cmControlPageBlock(
        {required Widget child,
        required RxBool block,
        required bool remoteMaySendKeys,
        required bool systemBlocksRemoteKeys,
        bool chatOpen = false,
        RemoteBlockCheck check = shouldBeBlocked}) =>
    buildRemoteBlock(
        child: ExcludeFocus(
            excluding:
                remoteMaySendKeys && !systemBlocksRemoteKeys && !chatOpen,
            child: child),
        block: block,
        mask: false,
        check: check);

/// Whether a key a remote computer types can reach this window's controls.
bool cmRemoteKeysReachHere(Iterable<Client> clients) =>
    !allowRemoteCMModification() &&
    cmRemoteMaySendKeys(clients) &&
    !cmSystemBlocksRemoteKeys();

bool allowRemoteCMModification() {
  return option2bool(kOptionAllowRemoteCmModification,
      bind.mainGetLocalOption(key: kOptionAllowRemoteCmModification));
}

/// The Files tab of the selected card.
class _FileTransferLogPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      Obx(() => CmFileList(jobs: gFFI.cmFileModel.currentJobTable.toList()));
}

/// The files a caller sent or took, newest first.
class CmFileList extends StatefulWidget {
  const CmFileList({Key? key, required this.jobs}) : super(key: key);
  final List<CmFileLog> jobs;

  @override
  State<CmFileList> createState() => _CmFileListState();
}

class _CmFileListState extends State<CmFileList> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final jobs = widget.jobs;
    if (jobs.isEmpty) return _empty(context);
    return ListView.separated(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
      itemCount: jobs.length,
      separatorBuilder: (_, __) => const NdRule(),
      itemBuilder: (context, i) => _row(context, jobs[jobs.length - 1 - i]),
    );
  }

  Widget _empty(BuildContext context) {
    final c = context.nd;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(NdIcons.swapHoriz, size: 28, color: c.textMuted),
          const SizedBox(height: 8),
          Text(translate("No transfers in progress"),
              textAlign: TextAlign.center,
              style: context.ndText.body.copyWith(color: c.textMuted)),
        ]),
      ),
    );
  }

  (IconData, String) _what(CmFileLog item) => switch (item.action) {
        CmFileAction.remoteToLocal => (NdIcons.arrowUpward, translate('Send')),
        CmFileAction.localToRemote =>
          (NdIcons.arrowDownward, translate('Receive')),
        CmFileAction.remove => (NdIcons.delete, translate('Delete')),
        CmFileAction.createDir =>
          (NdIcons.createNewFolder, translate('Create Folder')),
        CmFileAction.rename => (NdIcons.rename, translate('Rename')),
        CmFileAction.none => (NdIcons.swapHoriz, ''),
      };

  Widget _row(BuildContext context, CmFileLog item) {
    final c = context.nd;
    final t = context.ndText;
    final (icon, action) = _what(item);
    final running = item.state == JobState.inProgress && item.totalSize > 0;
    final details = <String>[
      if (action.isNotEmpty) action,
      if (item.totalSize > 0) readableFileSize(item.totalSize.toDouble()),
      if (running) '${readableFileSize(item.speed)}/s',
      if (item.isTransfer() && item.state != JobState.inProgress)
        translate(item.display()),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(icon, size: 18, color: c.textMuted),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item.fileName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: t.body.copyWith(fontSize: 14, height: 20 / 14)),
              if (details.isNotEmpty)
                Text(details.join(', '), style: t.small),
              if (running) ...[
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: (item.finishedSize / item.totalSize)
                        .clamp(0.0, 1.0),
                    minHeight: 4,
                    color: c.accent,
                    backgroundColor: c.rule,
                  ),
                ),
              ],
            ],
          ),
        ),
      ]),
    );
  }
}
