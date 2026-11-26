// original cm window in Sciter version.

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common/widgets/nd/nd.dart';
import 'package:flutter_hbb/desktop/pages/cm/cm_widgets.dart';
import 'package:flutter_hbb/onboarding/joining_view.dart' show formatNdId;
import 'package:flutter_hbb/common/widgets/audio_input.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/desktop/widgets/tabbar_widget.dart';
import 'package:flutter_hbb/models/chat_model.dart';
import 'package:flutter_hbb/models/cm_file_model.dart';
import 'package:flutter_hbb/utils/platform_channel.dart';
import 'package:get/get.dart';
import 'package:percent_indicator/linear_percent_indicator.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import '../../common.dart';
import '../../common/widgets/chat_page.dart';
import '../../models/file_model.dart';
import '../../models/platform_model.dart';
import '../../models/server_model.dart';

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
        builder: (context, serverModel, child) {
          final body = Scaffold(
            backgroundColor: context.nd.bg,
            body: ConnectionManager(),
          );
          return isLinux
              ? buildVirtualWindowFrame(context, body)
              : workaroundWindowBorder(
                  context,
                  Container(
                    decoration: BoxDecoration(
                        border: Border.all(color: context.nd.rule)),
                    child: body,
                  ));
        },
      ),
    );
  }

  @override
  bool get wantKeepAlive => true;
}

class ConnectionManager extends StatefulWidget {
  @override
  State<StatefulWidget> createState() => ConnectionManagerState();
}

class ConnectionManagerState extends State<ConnectionManager>
    with WidgetsBindingObserver {
  final RxBool _controlPageBlock = false.obs;
  final RxBool _sidePageBlock = false.obs;

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
        shouldBeBlocked(_sidePageBlock, null);
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

  @override
  Widget build(BuildContext context) {
    final serverModel = Provider.of<ServerModel>(context);
    pointerHandler(PointerEvent e) {
      if (serverModel.cmHiddenTimer != null) {
        serverModel.cmHiddenTimer!.cancel();
        serverModel.cmHiddenTimer = null;
        debugPrint("CM hidden timer has been canceled");
      }
    }

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
        : Listener(
            onPointerDown: pointerHandler,
            onPointerMove: pointerHandler,
            child: DesktopTab(
              showTitle: false,
              showMaximize: false,
              showMinimize: true,
              // Closing would end every session: minimize only.
              showClose: false,
              onWindowCloseButton: handleWindowCloseButton,
              controller: serverModel.tabController,
              selectedBorderColor: null,
              maxLabelWidth: 100,
              tail: null, //buildScrollJumper(),
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
              pageViewBuilder: (pageView) => LayoutBuilder(
                builder: (context, constrains) {
                  var borderWidth = 0.0;
                  if (constrains.maxWidth >
                      kConnectionManagerWindowSizeClosedChat.width) {
                    borderWidth = kConnectionManagerWindowSizeOpenChat.width -
                        constrains.maxWidth;
                  } else {
                    borderWidth = kConnectionManagerWindowSizeClosedChat.width -
                        constrains.maxWidth;
                  }
                  if (borderWidth < 0 || borderWidth > 50) {
                    borderWidth = 0;
                  }
                  final realClosedWidth =
                      kConnectionManagerWindowSizeClosedChat.width -
                          borderWidth;
                  final realChatPageWidth =
                      constrains.maxWidth - realClosedWidth;
                  final row = Row(children: [
                    if (constrains.maxWidth >
                        kConnectionManagerWindowSizeClosedChat.width)
                      Consumer<ChatModel>(
                          builder: (_, model, child) => SizedBox(
                                width: realChatPageWidth,
                                child: allowRemoteCMModification()
                                    ? buildSidePage()
                                    : buildRemoteBlock(
                                        child: buildSidePage(),
                                        block: _sidePageBlock,
                                        mask: true),
                              )),
                    SizedBox(
                        width: realClosedWidth,
                        child: SizedBox(
                            width: realClosedWidth,
                            child: allowRemoteCMModification()
                                ? pageView
                                : Consumer<ServerModel>(
                                    builder: (_, model, __) =>
                                        cmControlPageBlock(
                                            child: pageView,
                                            block: _controlPageBlock,
                                            remoteMaySendKeys:
                                                cmRemoteMaySendKeys(
                                                    model.clients),
                                            systemBlocksRemoteKeys:
                                                cmSystemBlocksRemoteKeys())))),
                  ]);
                  return Container(
                    color: context.nd.bg,
                    child: row,
                  );
                },
              ),
            ),
          );
  }

  Widget buildSidePage() {
    final selected = gFFI.serverModel.tabController.state.value.selected;
    if (selected < 0 || selected >= gFFI.serverModel.clients.length) {
      return Offstage();
    }
    final clientType = gFFI.serverModel.clients[selected].type_();
    if (clientType == ClientType.file) {
      return _FileTransferLogPage();
    } else {
      return ChatPage(type: ChatPageType.desktopCM);
    }
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
                  child: NdTitleBrand(title: bind.mainGetAppNameSync()),
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

  Widget _avatar() {
    final name = client.name.isNotEmpty ? client.name : client.peerId;
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
    final c = context.nd;
    final name = client.name.isNotEmpty ? client.name : client.peerId;
    final permissions = _permissions();
    Widget body;
    if (!client.authorized) {
      body = SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        child: CmRequestBody(
          focusOnArrival: true,
          header: CmHeader(
              name: name,
              subtitle: formatNdId(client.peerId),
              mono: true,
              kind: _kind,
              avatar: _avatar()),
          name: name,
          permissions: permissions,
        ),
      );
    } else {
      body = Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Obx(() => CmHeader(
                name: name,
                subtitle: client.disconnected
                    ? translate('Disconnected')
                    : cmConnectedFor(Duration(seconds: _seconds.value)),
                kind: _kind,
                avatar: _avatar())),
            const SizedBox(height: 16),
            if (!client.disconnected &&
                (client.type_() == ClientType.remote ||
                    client.type_() == ClientType.file ||
                    client.type_() == ClientType.camera))
              CmTabs(
                value: CmTab.access,
                showFiles: client.type_() != ClientType.camera,
                unread: client.unreadChatMessageCount.value,
                onChanged: (tab) => checkClickTime(client.id, () {
                  if (tab == CmTab.files) {
                    gFFI.chatModel.toggleCMFilePage();
                  } else if (tab == CmTab.chat) {
                    gFFI.chatModel
                        .toggleCMChatPage(MessageKey(client.peerId, client.id));
                  }
                }),
              ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(top: 4, bottom: 12),
                child: CmPermissionList(items: permissions),
              ),
            ),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: body),
        Container(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          decoration: BoxDecoration(
              border: Border(top: BorderSide(color: c.rule))),
          child: _CmControlPanel(client: client),
        ),
      ],
    );
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
                label: translate('Audio input'),
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
    final showAccept = model.approveMode != 'password';
    return CmRequestActions(
      onDecline: () => checkClickTime(client.id, handleDisconnect),
      onAllow: showAccept
          ? () => checkClickTime(client.id, () {
                handleAccept(context);
                windowManager.minimize();
              })
          : null,
      onAllowElevated: showElevation && showAccept
          ? () => checkClickTime(client.id, () {
                handleAccept(context);
                handleElevate(context);
                windowManager.minimize();
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
/// - Every action still checks that the click or key did not come from the
///   remote computer (checkClickTime), as a second layer.
Widget cmControlPageBlock(
        {required Widget child,
        required RxBool block,
        required bool remoteMaySendKeys,
        required bool systemBlocksRemoteKeys}) =>
    buildRemoteBlock(
        child: ExcludeFocus(
            excluding: remoteMaySendKeys && !systemBlocksRemoteKeys,
            child: child),
        block: block,
        mask: false);

bool allowRemoteCMModification() {
  return option2bool(kOptionAllowRemoteCmModification,
      bind.mainGetLocalOption(key: kOptionAllowRemoteCmModification));
}

class _FileTransferLogPage extends StatefulWidget {
  _FileTransferLogPage({Key? key}) : super(key: key);

  @override
  State<_FileTransferLogPage> createState() => __FileTransferLogPageState();
}

class __FileTransferLogPageState extends State<_FileTransferLogPage> {
  @override
  Widget build(BuildContext context) {
    return statusList();
  }

  Widget generateCard(Widget child) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.all(
          Radius.circular(15.0),
        ),
      ),
      child: child,
    );
  }

  iconLabel(CmFileLog item) {
    switch (item.action) {
      case CmFileAction.none:
        return Container();
      case CmFileAction.localToRemote:
      case CmFileAction.remoteToLocal:
        return Column(
          children: [
            Transform.rotate(
              angle: item.action == CmFileAction.remoteToLocal ? 0 : pi,
              child: Icon(NdIcons.arrowForward,
                  color: Theme.of(context).tabBarTheme.labelColor),
            ),
            Text(item.action == CmFileAction.remoteToLocal
                ? translate('Send')
                : translate('Receive'))
          ],
        );
      case CmFileAction.remove:
        return Column(
          children: [
            Icon(
              NdIcons.delete,
              color: Theme.of(context).tabBarTheme.labelColor,
            ),
            Text(translate('Delete'))
          ],
        );
      case CmFileAction.createDir:
        return Column(
          children: [
            Icon(
              NdIcons.createNewFolder,
              color: Theme.of(context).tabBarTheme.labelColor,
            ),
            Text(translate('Create Folder'))
          ],
        );
      case CmFileAction.rename:
        return Column(
          children: [
            Icon(
              NdIcons.rename,
              color: Theme.of(context).tabBarTheme.labelColor,
            ),
            Text(translate('Rename'))
          ],
        );
    }
  }

  Widget statusList() {
    return PreferredSize(
      preferredSize: const Size(200, double.infinity),
      child: Container(
          padding: const EdgeInsets.all(12.0),
          child: Obx(
            () {
              final jobTable = gFFI.cmFileModel.currentJobTable;
              statusListView(List<CmFileLog> jobs) => ListView.builder(
                    controller: ScrollController(),
                    itemBuilder: (BuildContext context, int index) {
                      final item = jobs[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 5),
                        child: generateCard(
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  SizedBox(
                                    width: 50,
                                    child: iconLabel(item),
                                  ).paddingOnly(left: 15),
                                  const SizedBox(
                                    width: 16.0,
                                  ),
                                  Expanded(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          item.fileName,
                                        ).paddingSymmetric(vertical: 10),
                                        if (item.totalSize > 0)
                                          Text(
                                            '${translate("Total")} ${readableFileSize(item.totalSize.toDouble())}',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: MyTheme.darkGray,
                                            ),
                                          ),
                                        if (item.totalSize > 0)
                                          Offstage(
                                            offstage: item.state !=
                                                JobState.inProgress,
                                            child: Text(
                                              '${translate("Speed")} ${readableFileSize(item.speed)}/s',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: MyTheme.darkGray,
                                              ),
                                            ),
                                          ),
                                        Offstage(
                                          offstage: !(item.isTransfer() &&
                                              item.state !=
                                                  JobState.inProgress),
                                          child: Text(
                                            translate(
                                              item.display(),
                                            ),
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: MyTheme.darkGray,
                                            ),
                                          ),
                                        ),
                                        if (item.totalSize > 0)
                                          Offstage(
                                            offstage: item.state !=
                                                JobState.inProgress,
                                            child: LinearPercentIndicator(
                                              padding:
                                                  EdgeInsets.only(right: 15),
                                              animateFromLastPercent: true,
                                              center: Text(
                                                '${(item.finishedSize / item.totalSize * 100).toStringAsFixed(0)}%',
                                              ),
                                              barRadius: Radius.circular(15),
                                              percent: item.finishedSize /
                                                  item.totalSize,
                                              progressColor: MyTheme.accent,
                                              backgroundColor:
                                                  Theme.of(context).hoverColor,
                                              lineHeight:
                                                  kDesktopFileTransferRowHeight,
                                            ).paddingSymmetric(vertical: 15),
                                          ),
                                      ],
                                    ),
                                  ),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [],
                                  ),
                                ],
                              ),
                            ],
                          ).paddingSymmetric(vertical: 10),
                        ),
                      );
                    },
                    itemCount: jobTable.length,
                  );

              return jobTable.isEmpty
                  ? generateCard(
                      Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(NdIcons.swapHoriz,
                                    size: 40,
                                    color: Theme.of(context)
                                        .tabBarTheme
                                        .labelColor)
                                .paddingOnly(bottom: 10),
                            Text(
                              translate("No transfers in progress"),
                              textAlign: TextAlign.center,
                              textScaler: TextScaler.linear(1.20),
                              style: TextStyle(
                                  color:
                                      Theme.of(context).tabBarTheme.labelColor),
                            ),
                          ],
                        ),
                      ),
                    )
                  : statusListView(jobTable);
            },
          )),
    );
  }
}
