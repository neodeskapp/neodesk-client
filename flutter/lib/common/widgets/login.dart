import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common/hbbs/hbbs.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/models/user_model.dart';
import 'package:get/get.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../common.dart';
import './dialog.dart';
import './oidc_auth_status.dart';
import 'package:flutter_hbb/common/widgets/nd/nd.dart';
import 'package:flutter_hbb/common/widgets/nd/nd_dialog_host.dart';

const kOpSvgList = [
  'github',
  'gitlab',
  'google',
  'apple',
  'okta',
  'facebook',
  'azure',
  'auth0',
  'microsoft'
];
const _requestingAccountAuth = 'Requesting account auth';
const _waitingAccountAuth = 'Waiting account auth';

class _OidcProviderBranding {
  final String label;
  final String iconKey;

  const _OidcProviderBranding({
    required this.label,
    required this.iconKey,
  });
}

_OidcProviderBranding _oidcProviderBranding(String op) {
  switch (op.toLowerCase()) {
    case 'azure':
      return _OidcProviderBranding(
        label: 'Microsoft',
        iconKey: 'microsoft',
      );
    default:
      return _OidcProviderBranding(
        label: {
              'github': 'GitHub',
              'gitlab': 'GitLab',
            }[op.toLowerCase()] ??
            toCapitalized(op),
        iconKey: op.toLowerCase(),
      );
  }
}

class _IconOP extends StatelessWidget {
  final String op;
  final String? icon;
  final EdgeInsets margin;
  const _IconOP(
      {Key? key,
      required this.op,
      required this.icon,
      this.margin = const EdgeInsets.symmetric(horizontal: 4.0)})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    final svgFile =
        kOpSvgList.contains(op.toLowerCase()) ? op.toLowerCase() : null;
    return Container(
      margin: margin,
      child: icon != null
          ? SvgPicture.string(
              icon!,
              width: 20,
            )
          : svgFile != null
              ? SvgPicture.asset(
                  'assets/auth-$svgFile.svg',
                  width: 20,
                )
              : Icon(NdIcons.howToReg, size: 20, color: ndColors.accent),
    );
  }
}

class ButtonOP extends StatelessWidget {
  final String op;
  final RxString curOP;
  final String? icon;
  final Color primaryColor;
  final double height;
  final Function() onTap;
  final bool Function() canStartAuth;

  const ButtonOP({
    Key? key,
    required this.op,
    required this.curOP,
    required this.icon,
    required this.primaryColor,
    required this.height,
    required this.onTap,
    required this.canStartAuth,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final branding = _oidcProviderBranding(op);
    final buttonLabel = translate("Continue with {${branding.label}}");
    return Row(children: [
      Container(
        height: height,
        width: 200,
        child: Obx(() => ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryColor,
            ).copyWith(elevation: ButtonStyleButton.allOrNull(0.0)),
            onPressed:
                curOP.value == 'rustdesk' || !canStartAuth() ? null : onTap,
            child: Row(
              children: [
                SizedBox(
                  width: 30,
                  child: _IconOP(
                    op: branding.iconKey,
                    icon: icon,
                    margin: EdgeInsets.only(right: 5),
                  ),
                ),
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Center(child: Text(buttonLabel)),
                  ),
                ),
              ],
            ))),
      ),
    ]);
  }
}

class ConfigOP {
  final String op;
  final String? icon;
  ConfigOP({required this.op, required this.icon});
}

/// The op of the sign-in through the web console ("Sign in with NeoDesk").
/// Exact and case-sensitive, as the server matches it; any other name is an
/// outside identity provider.
const kNeoDeskOp = 'NeoDesk';

/// Splits the server's sign-in options (UserModel.queryOidcLoginOptions)
/// into the web console's own sign-in and the other providers, which keep
/// the server's order. Entries without a name are left out.
({ConfigOP? neodesk, List<ConfigOP> others}) splitLoginOptions(
    List<dynamic> options) {
  ConfigOP? neodesk;
  final others = <ConfigOP>[];
  for (final e in options) {
    if (e is! Map) continue;
    final name = e['name'];
    if (name is! String || name.isEmpty) continue;
    final icon = e['icon'];
    final config = ConfigOP(op: name, icon: icon is String ? icon : null);
    if (name == kNeoDeskOp) {
      neodesk ??= config;
    } else {
      others.add(config);
    }
  }
  return (neodesk: neodesk, others: others);
}

/// The waiting line of a running sign-in: for the web console, that it
/// waits for the Allow in the browser; for the other providers the
/// backend's state as before.
String oidcStateMessageKey(String op, String stateMsg) {
  if (op == kNeoDeskOp &&
      (stateMsg == _waitingAccountAuth || stateMsg == _requestingAccountAuth)) {
    return 'nd-sign-in-browser-waiting';
  }
  return stateMsg;
}

/// "Sign in with NeoDesk": the full-width primary button of the sign-in
/// through the web console, with the NeoDesk app icon (the mark on its dark
/// tile, lead/brand/app-icon.svg unchanged). The tile keeps the mark
/// visible on every accent, also the light blue of the dark theme and a
/// server's own accent.
class NdNeoDeskSignInButton extends StatelessWidget {
  const NdNeoDeskSignInButton({super.key, required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return NdButton.primary(
      label: translate('nd-sign-in-with-neodesk'),
      onPressed: onPressed,
      block: true,
      leading: SvgPicture.asset(
        'assets/nd-app-icon.svg',
        key: const ValueKey('nd-neodesk-mark'),
        width: 22,
        height: 22,
      ),
    );
  }
}

class _OidcAuthController {
  final RxString curOP = ''.obs;
  Future<void> _pendingOperation = Future<void>.value();
  int _authAttempt = 0;
  bool _closed = false;
  final _cancelInProgress = false.obs;

  bool _isCurrent(int authAttempt, String op) {
    return !_closed && authAttempt == _authAttempt && curOP.value == op;
  }

  Future<bool> start(String op) {
    if (!canStart()) {
      return Future<bool>.value(false);
    }
    final authAttempt = ++_authAttempt;
    curOP.value = op;
    // Web auth must start during the original user gesture so popups are allowed.
    if (isWeb) {
      return _startWeb(authAttempt, op);
    }
    final completer = Completer<bool>();
    _pendingOperation = _pendingOperation.then((_) async {
      if (!_isCurrent(authAttempt, op)) {
        completer.complete(false);
        return;
      }
      try {
        await bind.mainAccountAuthCancel();
        if (!_isCurrent(authAttempt, op)) {
          completer.complete(false);
          return;
        }
        await bind.mainAccountAuth(op: op, rememberMe: true);
        completer.complete(_isCurrent(authAttempt, op));
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  Future<bool> _startWeb(int authAttempt, String op) async {
    await bind.mainAccountAuth(op: op, rememberMe: true);
    return _isCurrent(authAttempt, op);
  }

  bool canStart() {
    return !_closed && !_cancelInProgress.value;
  }

  Future<bool> cancelCurrent(String op) {
    if (!canStart() || curOP.value != op) {
      return Future<bool>.value(false);
    }
    final authAttempt = ++_authAttempt;
    final completer = Completer<bool>();
    _cancelInProgress.value = true;
    _pendingOperation = _pendingOperation.then((_) async {
      try {
        await bind.mainAccountAuthCancel();
        completer.complete(_isCurrent(authAttempt, op));
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      } finally {
        _cancelInProgress.value = false;
      }
    });
    return completer.future;
  }

  Future<void> _cancelBackend() async {
    try {
      await bind.mainAccountAuthCancel();
    } catch (error, stackTrace) {
      debugPrint('Failed to cancel account authentication $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> close() async {
    if (_closed) {
      return;
    }
    final hasActiveOidcAuth =
        curOP.value.isNotEmpty && curOP.value != 'rustdesk';
    _closed = true;
    _authAttempt++;
    curOP.value = '';
    if (hasActiveOidcAuth) {
      await _cancelBackend();
    }
    await _pendingOperation;
    if (hasActiveOidcAuth) {
      await _cancelBackend();
    }
  }
}

class WidgetOP extends StatefulWidget {
  final ConfigOP config;
  final RxString curOP;
  final Function(Map<String, dynamic>) cbLogin;
  final Future<bool> Function(String) startAuth;
  final Future<bool> Function(String) cancelAuth;
  final bool Function() canStartAuth;
  const WidgetOP({
    Key? key,
    required this.config,
    required this.curOP,
    required this.cbLogin,
    required this.startAuth,
    required this.cancelAuth,
    required this.canStartAuth,
  }) : super(key: key);

  @override
  State<StatefulWidget> createState() {
    return _WidgetOPState();
  }
}

class _WidgetOPState extends State<WidgetOP> {
  Timer? _updateTimer;
  bool _isAuthStatusQueryInFlight = false;
  int _authAttempt = 0;
  String _stateMsg = '';
  String _failedMsg = '';
  String _url = '';

  @override
  void dispose() {
    super.dispose();
    _updateTimer?.cancel();
  }

  _beginQueryState(int authAttempt) {
    _updateTimer?.cancel();
    unawaited(_runAuthStatusQuery(() => _updateState(authAttempt)));
    _updateTimer = Timer.periodic(Duration(seconds: 1), (timer) {
      unawaited(_runAuthStatusQuery(() => _updateState(authAttempt)));
    });
  }

  Future<void> _runAuthStatusQuery(Future<void> Function() query) async {
    if (_isAuthStatusQueryInFlight) {
      return;
    }
    _isAuthStatusQueryInFlight = true;
    try {
      await query();
    } finally {
      _isAuthStatusQueryInFlight = false;
    }
  }

  Future<void> _launchAuthUrl(String url) async {
    try {
      final launched = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        debugPrint('Failed to open OIDC authentication URL');
      }
    } catch (error, stackTrace) {
      debugPrint(
          'Failed to open OIDC authentication URL (${error.runtimeType})');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> _copyAuthUrl(String url) async {
    try {
      await Clipboard.setData(ClipboardData(text: url));
      showToast(
        translate('Copied'),
      );
    } catch (error, stackTrace) {
      debugPrint(
          'Failed to copy OIDC authentication URL (${error.runtimeType})');
      debugPrintStack(stackTrace: stackTrace);
      showToast(translate('Failed'));
    }
  }

  void _runCurrentAuthUrlAction(
    int authAttempt,
    String authUrl,
    Future<void> Function(String) action,
  ) {
    if (!mounted ||
        authAttempt != _authAttempt ||
        widget.curOP.value != widget.config.op ||
        authUrl.isEmpty ||
        _url != authUrl) {
      return;
    }
    unawaited(action(authUrl));
  }

  void _invalidateAuthAttempt() {
    _authAttempt++;
    _url = '';
  }

  bool _isCurrentAuthAttempt(int authAttempt) {
    return mounted &&
        authAttempt == _authAttempt &&
        widget.curOP.value == widget.config.op;
  }

  Future<void> _handleAuthFailure(
    int authAttempt,
    Object error,
    String operation,
  ) async {
    debugPrint('Failed to $operation $error');
    if (!_isCurrentAuthAttempt(authAttempt)) {
      return;
    }
    _updateTimer?.cancel();
    setState(() => _failedMsg = 'Failed');
    try {
      final canceled = await widget.cancelAuth(widget.config.op);
      if (!canceled || !_isCurrentAuthAttempt(authAttempt)) {
        return;
      }
    } catch (cancelError, stackTrace) {
      debugPrint('Failed to cancel account authentication $cancelError');
      debugPrintStack(stackTrace: stackTrace);
      return;
    }
    setState(() {
      _invalidateAuthAttempt();
      widget.curOP.value = '';
    });
  }

  Future<void> _updateState(int authAttempt) {
    if (!mounted ||
        authAttempt != _authAttempt ||
        widget.curOP.value != widget.config.op) {
      _updateTimer?.cancel();
      return Future<void>.value();
    }
    return bind.mainAccountAuthResult().then<void>((result) {
      if (!mounted ||
          authAttempt != _authAttempt ||
          widget.curOP.value != widget.config.op ||
          result.isEmpty) {
        return;
      }
      final resultMap = jsonDecode(result);
      if (resultMap == null) {
        return;
      }
      final String backendStateMsg = resultMap['state_msg'];
      String failedMsg = resultMap['failed_msg'];
      final String? url = resultMap['url'];
      final stateMsg = backendStateMsg == _requestingAccountAuth &&
              (url == null || url.isEmpty)
          ? _waitingAccountAuth
          : backendStateMsg;
      final bool urlLaunched = (resultMap['url_launched'] as bool?) ?? false;
      final authBody = resultMap['auth_body'];
      if (authBody != null) {
        _updateTimer?.cancel();
        _invalidateAuthAttempt();
        widget.curOP.value = '';
        widget.cbLogin(authBody as Map<String, dynamic>);
        return;
      }
      final stateChanged = _stateMsg != stateMsg || _failedMsg != failedMsg;
      final newUrl = _url.isEmpty && url != null && url.isNotEmpty ? url : null;
      if (!stateChanged && newUrl == null) {
        return;
      }
      setState(() {
        _stateMsg = stateMsg;
        _failedMsg = failedMsg;
        if (newUrl != null) {
          _url = newUrl;
        }
        if (failedMsg.isNotEmpty) {
          _invalidateAuthAttempt();
          widget.curOP.value = '';
          _updateTimer?.cancel();
        }
      });
      if (newUrl != null && failedMsg.isEmpty && !urlLaunched) {
        unawaited(_launchAuthUrl(newUrl));
      }
    }).catchError(
      (e) => _handleAuthFailure(
        authAttempt,
        e,
        'query account authentication',
      ),
    );
  }

  int _resetState() {
    _updateTimer?.cancel();
    setState(() {
      _invalidateAuthAttempt();
      _stateMsg = _waitingAccountAuth;
      _failedMsg = '';
    });
    return _authAttempt;
  }

  /// Cancel in the waiting state: stops the wait, the button can start a
  /// new one.
  Future<void> _cancelWaiting() async {
    final authAttempt = _authAttempt;
    if (!_isCurrentAuthAttempt(authAttempt)) {
      return;
    }
    try {
      final canceled = await widget.cancelAuth(widget.config.op);
      if (!canceled || !_isCurrentAuthAttempt(authAttempt)) {
        return;
      }
    } catch (error, stackTrace) {
      debugPrint('Failed to cancel account authentication $error');
      debugPrintStack(stackTrace: stackTrace);
      return;
    }
    _updateTimer?.cancel();
    setState(() {
      _invalidateAuthAttempt();
      _stateMsg = '';
      _failedMsg = '';
      widget.curOP.value = '';
    });
  }

  Future<void> _onTap() async {
    if (!widget.canStartAuth()) {
      return;
    }
    final authAttempt = _resetState();
    try {
      final started = await widget.startAuth(widget.config.op);
      if (!started) {
        return;
      }
    } catch (e) {
      await _handleAuthFailure(
        authAttempt,
        e,
        'start account authentication',
      );
      return;
    }
    if (!mounted ||
        authAttempt != _authAttempt ||
        widget.curOP.value != widget.config.op) {
      return;
    }
    _beginQueryState(authAttempt);
  }

  @override
  Widget build(BuildContext context) {
    final isNeoDesk = widget.config.op == kNeoDeskOp;
    return Column(
      crossAxisAlignment: isNeoDesk
          ? CrossAxisAlignment.stretch
          : CrossAxisAlignment.center,
      children: [
        if (isNeoDesk)
          Obx(() => NdNeoDeskSignInButton(
                onPressed:
                    widget.curOP.value == 'rustdesk' || !widget.canStartAuth()
                        ? null
                        : _onTap,
              ))
        else
          ButtonOP(
            op: widget.config.op,
            curOP: widget.curOP,
            icon: widget.config.icon,
            primaryColor: str2color(widget.config.op, 0x7f),
            height: 36,
            canStartAuth: widget.canStartAuth,
            onTap: _onTap,
          ),
        Obx(() {
          if (widget.curOP.isNotEmpty &&
              widget.curOP.value != widget.config.op) {
            _failedMsg = '';
          }
          final authAttempt = _authAttempt;
          final authUrl = _url;
          return Offstage(
            offstage:
                _failedMsg.isEmpty && widget.curOP.value != widget.config.op,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (_stateMsg.isNotEmpty && _failedMsg.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: OidcAuthStatus(
                      message: translate(
                          oidcStateMessageKey(widget.config.op, _stateMsg)),
                      browserFallbackPrompt: translate(
                        "Browser didn't open? Use the url below to sign in.",
                      ),
                      authUrl: authUrl,
                      copyLabel: translate('Copy to clipboard'),
                      onCopy: authUrl.isEmpty
                          ? null
                          : () => _runCurrentAuthUrlAction(
                                authAttempt,
                                authUrl,
                                _copyAuthUrl,
                              ),
                    ),
                  ),
                if (isNeoDesk &&
                    _stateMsg.isNotEmpty &&
                    _failedMsg.isEmpty &&
                    widget.curOP.value == widget.config.op)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: NdButton(
                      key: const ValueKey('nd-sign-in-browser-cancel'),
                      label: translate('Cancel'),
                      size: NdButtonSize.sm,
                      onPressed: () => unawaited(_cancelWaiting()),
                    ),
                  ),
                if (_failedMsg.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Builder(builder: (context) {
                      final errorColor = Theme.of(context).colorScheme.error;
                      final bgColor = Theme.of(context)
                          .colorScheme
                          .errorContainer
                          .withOpacity(0.3);
                      return Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8.0, vertical: 6.0),
                        decoration: BoxDecoration(
                          color: bgColor,
                          borderRadius: BorderRadius.circular(4.0),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(NdIcons.error, color: errorColor, size: 16),
                            const SizedBox(width: 6),
                            Flexible(
                              child: SelectableText(
                                translate(_failedMsg),
                                style:
                                    DefaultTextStyle.of(context).style.copyWith(
                                          fontSize: 13,
                                          color: errorColor,
                                        ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ),
              ],
            ),
          );
        }),
      ],
    );
  }
}

class LoginWidgetOP extends StatelessWidget {
  final List<ConfigOP> ops;
  final RxString curOP;
  final Function(Map<String, dynamic>) cbLogin;
  final Future<bool> Function(String) startAuth;
  final Future<bool> Function(String) cancelAuth;
  final bool Function() canStartAuth;

  LoginWidgetOP({
    Key? key,
    required this.ops,
    required this.curOP,
    required this.cbLogin,
    required this.startAuth,
    required this.cancelAuth,
    required this.canStartAuth,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    var children = ops
        .map((op) => [
              WidgetOP(
                config: op,
                curOP: curOP,
                cbLogin: cbLogin,
                startAuth: startAuth,
                cancelAuth: cancelAuth,
                canStartAuth: canStartAuth,
              ),
              const Divider(
                indent: 5,
                endIndent: 5,
              )
            ])
        .expand((i) => i)
        .toList();
    if (children.isNotEmpty) {
      children.removeLast();
    }
    return SingleChildScrollView(
        child: Container(
            width: 200,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: children,
            )));
  }
}

/// The sign-in dialog: Username and Password with the labels above, the
/// error under the field it belongs to, Cancel and Sign in at the end.
/// [above] holds the sign-in through the web console ("Sign in with
/// NeoDesk"), set apart from the fields by "or"; [below] holds the other
/// sign-in buttons. Enter in Username moves to Password, Enter in Password
/// signs in.
class NdLoginDialog extends StatefulWidget {
  const NdLoginDialog({
    super.key,
    required this.username,
    required this.password,
    required this.onSignIn,
    required this.onCancel,
    this.usernameError,
    this.passwordError,
    this.busy = false,
    this.userFocusNode,
    this.above,
    this.below,
  });

  final TextEditingController username;
  final TextEditingController password;
  final VoidCallback onSignIn;
  final VoidCallback onCancel;
  final String? usernameError;
  final String? passwordError;

  /// A sign-in is running: Sign in is off and a bar runs under the fields.
  final bool busy;
  final FocusNode? userFocusNode;
  final Widget? above;
  final Widget? below;

  @override
  State<NdLoginDialog> createState() => _NdLoginDialogState();
}

class _NdLoginDialogState extends State<NdLoginDialog> {
  final _passwordFocus = FocusNode();
  bool _hidden = true;

  @override
  void dispose() {
    _passwordFocus.dispose();
    super.dispose();
  }

  void _submit() {
    if (!widget.busy) widget.onSignIn();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.nd;
    return NdDialog(
      title: translate('nd-sign-in'),
      width: 420,
      onClose: widget.onCancel,
      closeTooltip: translate('Close'),
      children: [
        if (widget.above != null) ...[
          widget.above!,
          Center(
            key: const ValueKey('nd-sign-in-or'),
            child: Text(translate('or'),
                style: context.ndText.small.copyWith(color: c.textMuted)),
          ),
        ],
        NdField(
          label: translate('Username'),
          controller: widget.username,
          focusNode: widget.userFocusNode,
          error: widget.usernameError,
          onSubmitted: (_) => _passwordFocus.requestFocus(),
        ),
        NdField(
          label: translate('Password'),
          controller: widget.password,
          focusNode: _passwordFocus,
          obscureText: _hidden,
          error: widget.passwordError,
          onSubmitted: (_) => _submit(),
          trailing: NdIconButton(
            icon: _hidden ? NdIcons.view : NdIcons.hide,
            tooltip:
                translate(_hidden ? 'nd-show-password' : 'nd-hide-password'),
            size: 28,
            onPressed: () => setState(() => _hidden = !_hidden),
          ),
        ),
        if (widget.busy)
          LinearProgressIndicator(
              minHeight: 2, color: c.accent, backgroundColor: c.rule),
        if (widget.below != null) widget.below!,
      ],
      actions: [
        NdButton(label: translate('Cancel'), onPressed: widget.onCancel),
        NdButton.primary(
            label: translate('nd-sign-in'),
            onPressed: widget.busy ? null : _submit),
      ],
    );
  }
}

const kAuthReqTypeOidc = 'oidc/';

Future<bool?>? _activeLoginDialog;

// call this directly
Future<bool?> loginDialog() {
  final activeDialog = _activeLoginDialog;
  if (activeDialog != null) {
    return activeDialog;
  }
  final dialog = _openLoginDialogOnce();
  _activeLoginDialog = dialog;
  return dialog;
}

Future<bool?> _openLoginDialogOnce() async {
  try {
    return await _openLoginDialog();
  } finally {
    _activeLoginDialog = null;
  }
}

Future<bool?> _openLoginDialog() async {
  var username =
      TextEditingController(text: UserModel.getLocalUserInfo()?['name'] ?? '');
  var password = TextEditingController();
  final userFocusNode = FocusNode()..requestFocus();
  Timer(Duration(milliseconds: 100), () => userFocusNode..requestFocus());

  String? usernameMsg;
  String? passwordMsg;
  var isInProgress = false;
  final oidcAuth = _OidcAuthController();
  final curOP = oidcAuth.curOP;
  var listening = false;

  final loginOptions = [].obs;
  final loginOptionsError = Rxn<Object>();
  final loginOptionsInProgress = false.obs;
  fetchLoginOptions() async {
    loginOptionsInProgress.value = true;
    try {
      loginOptions.value = await UserModel.queryOidcLoginOptions();
      loginOptionsError.value = null;
    } catch (e) {
      debugPrint("queryOidcLoginOptions failed: $e");
      loginOptionsError.value = e;
    } finally {
      loginOptionsInProgress.value = false;
    }
  }

  Future.delayed(Duration.zero, fetchLoginOptions);

  final res = await showNdDialog<bool>((close, setState) =>
      Builder(builder: (context) {
        // Typing clears the field's error. Added once, not on every build.
        if (!listening) {
          listening = true;
          username.addListener(() {
            if (usernameMsg != null) {
              setState(() => usernameMsg = null);
            }
          });
          password.addListener(() {
            if (passwordMsg != null) {
              setState(() => passwordMsg = null);
            }
          });
        }

        onDialogCancel() {
          isInProgress = false;
          close(false);
        }

        handleLoginResponse(LoginResponse resp, bool storeIfAccessToken,
            void Function([bool?])? close) async {
          switch (resp.type) {
            case HttpType.kAuthResTypeToken:
              if (resp.access_token != null) {
                if (storeIfAccessToken) {
                  await bind.mainSetLocalOption(
                      key: 'access_token', value: resp.access_token!);
                  await bind.mainSetLocalOption(
                      key: 'user_info', value: jsonEncode(resp.user ?? {}));
                }
                if (close != null) {
                  close(true);
                }
                return;
              }
              break;
            case HttpType.kAuthResTypeEmailCheck:
              bool? isEmailVerification;
              if (resp.tfa_type == null ||
                  resp.tfa_type == HttpType.kAuthResTypeEmailCheck) {
                isEmailVerification = true;
              } else if (resp.tfa_type == HttpType.kAuthResTypeTfaCheck) {
                isEmailVerification = false;
              } else {
                passwordMsg = "Failed, bad tfa type from server";
              }
              if (isEmailVerification != null) {
                if (isMobile) {
                  if (close != null) close(null);
                  verificationCodeDialog(
                      resp.user, resp.secret, isEmailVerification);
                } else {
                  setState(() => isInProgress = false);
                  // Workaround for web, close the dialog first, then show the verification code dialog.
                  // Otherwise, the text field will keep selecting the text and we can't input the code.
                  // Not sure why this happens.
                  if (isWeb && close != null) close(null);
                  final res = await verificationCodeDialog(
                      resp.user, resp.secret, isEmailVerification);
                  if (res == true) {
                    if (!isWeb && close != null) close(false);
                    return;
                  }
                }
              }
              break;
            default:
              passwordMsg = "Failed, bad response from server";
              break;
          }
        }

        onLogin() async {
          if (curOP.value.isNotEmpty || isInProgress) {
            return;
          }
          // validate
          if (username.text.isEmpty) {
            setState(() => usernameMsg = translate('Username missed'));
            return;
          }
          if (password.text.isEmpty) {
            setState(() => passwordMsg = translate('Password missed'));
            return;
          }
          curOP.value = 'rustdesk';
          setState(() => isInProgress = true);
          try {
            final resp = await gFFI.userModel.login(LoginRequest(
                username: username.text,
                password: password.text,
                id: await bind.mainGetMyId(),
                uuid: await bind.mainGetUuid(),
                autoLogin: true,
                type: HttpType.kAuthReqTypeAccount));
            await handleLoginResponse(resp, true, close);
          } on RequestException catch (err) {
            passwordMsg = translate(err.cause);
          } catch (err) {
            passwordMsg = "Unknown Error: $err";
          }
          curOP.value = '';
          setState(() => isInProgress = false);
        }

        oidcLoginBody(Map<String, dynamic> authBody) async {
          LoginResponse? resp;
          try {
            // access_token is already stored in the rust side.
            resp = gFFI.userModel.getLoginResponseFromAuthBody(authBody);
          } catch (e) {
            debugPrint('Failed to parse oidc login body: "$authBody"');
          }
          close(true);

          if (resp != null) {
            handleLoginResponse(resp, false, null);
          }
        }

        // "Sign in with NeoDesk" at the top when the server offers it.
        Widget? neodeskAuthWidget() {
          if (loginOptionsError.value != null) return null;
          final neodesk = splitLoginOptions(loginOptions).neodesk;
          if (neodesk == null) return null;
          return WidgetOP(
            key: const ValueKey('nd-neodesk-op'),
            config: neodesk,
            curOP: curOP,
            startAuth: oidcAuth.start,
            cancelAuth: oidcAuth.cancelCurrent,
            canStartAuth: oidcAuth.canStart,
            cbLogin: oidcLoginBody,
          );
        }

        thirdAuthWidget() => Obx(() {
              final error = loginOptionsError.value;
              final inProgress = loginOptionsInProgress.value;
              if (error != null) {
                return Column(
                  children: [
                    const SizedBox(height: 8.0),
                    // NOT use Offstage to wrap LinearProgressIndicator
                    if (inProgress) const LinearProgressIndicator(),
                    if (!inProgress && error is! RequestException)
                      Text(
                        translate('network_error_tip'),
                        style: const TextStyle(fontSize: 12),
                        textAlign: TextAlign.center,
                      ),
                    TextButton(
                      style: TextButton.styleFrom(
                        foregroundColor: Theme.of(context).colorScheme.primary,
                      ),
                      onPressed: inProgress ? null : fetchLoginOptions,
                      child: Text(translate('Retry')),
                    ),
                    if (!inProgress)
                      SelectableText(
                        error.toString(),
                        style:
                            TextStyle(fontSize: 11, color: context.nd.danger),
                        textAlign: TextAlign.center,
                      ),
                  ],
                );
              }
              final others = splitLoginOptions(loginOptions).others;
              return Offstage(
                offstage: others.isEmpty,
                child: Column(
                  children: [
                    const SizedBox(
                      height: 8.0,
                    ),
                    Center(
                        child: Text(
                      translate('or'),
                      style: context.ndText.small
                          .copyWith(color: context.nd.textMuted),
                    )),
                    const SizedBox(
                      height: 8.0,
                    ),
                    LoginWidgetOP(
                      ops: others,
                      curOP: curOP,
                      startAuth: oidcAuth.start,
                      cancelAuth: oidcAuth.cancelCurrent,
                      canStartAuth: oidcAuth.canStart,
                      cbLogin: oidcLoginBody,
                    ),
                  ],
                ),
              );
            });

        // Padding keeps the dialog off the window edges on a narrow screen.
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Obx(() => NdLoginDialog(
                username: username,
                password: password,
                usernameError: usernameMsg,
                passwordError: passwordMsg,
                busy: isInProgress || curOP.value.isNotEmpty,
                userFocusNode: userFocusNode,
                onSignIn: onLogin,
                onCancel: onDialogCancel,
                above: neodeskAuthWidget(),
                below: thirdAuthWidget(),
              )),
        );
      })).whenComplete(oidcAuth.close);

  if (res != null) {
    await UserModel.updateOtherModels();
  }

  return res;
}

Future<bool?> verificationCodeDialog(
    UserPayload? user, String? secret, bool isEmailVerification) async {
  var autoLogin = true;
  var isInProgress = false;
  String? errorText;

  final code = TextEditingController();

  final res = await gFFI.dialogManager.show<bool>((setState, close, context) {
    void onVerify() async {
      setState(() => isInProgress = true);

      try {
        final resp = await gFFI.userModel.login(LoginRequest(
            verificationCode: code.text,
            tfaCode: isEmailVerification ? null : code.text,
            secret: secret,
            username: user?.name,
            id: await bind.mainGetMyId(),
            uuid: await bind.mainGetUuid(),
            autoLogin: autoLogin,
            type: HttpType.kAuthReqTypeEmailCode));

        switch (resp.type) {
          case HttpType.kAuthResTypeToken:
            if (resp.access_token != null) {
              await bind.mainSetLocalOption(
                  key: 'access_token', value: resp.access_token!);
              close(true);
              return;
            }
            break;
          default:
            errorText = "Failed, bad response from server";
            break;
        }
      } on RequestException catch (err) {
        errorText = translate(err.cause);
      } catch (err) {
        errorText = "Unknown Error: $err";
      }

      setState(() => isInProgress = false);
    }

    final codeField = isEmailVerification
        ? DialogEmailCodeField(
            controller: code,
            errorText: errorText,
            readyCallback: onVerify,
            onChanged: () => errorText = null,
          )
        : Dialog2FaField(
            controller: code,
            errorText: errorText,
            readyCallback: onVerify,
            onChanged: () => errorText = null,
          );

    getOnSubmit() => codeField.isReady ? onVerify : null;

    return CustomAlertDialog(
        title: Text(translate("Verification code")),
        contentBoxConstraints: BoxConstraints(maxWidth: 300),
        content: Column(
          children: [
            Offstage(
                offstage: !isEmailVerification || user?.email == null,
                child: TextField(
                  decoration: InputDecoration(
                      labelText: "Email", prefixIcon: Icon(NdIcons.mail)),
                  readOnly: true,
                  controller: TextEditingController(text: user?.email),
                ).workaroundFreezeLinuxMint()),
            isEmailVerification ? const SizedBox(height: 8) : const Offstage(),
            codeField,
            /*
            CheckboxListTile(
              contentPadding: const EdgeInsets.all(0),
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              title: Row(children: [
                Expanded(child: Text(translate("Trust this device")))
              ]),
              value: trustThisDevice,
              onChanged: (v) {
                if (v == null) return;
                setState(() => trustThisDevice = !trustThisDevice);
              },
            ),
            */
            // NOT use Offstage to wrap LinearProgressIndicator
            if (isInProgress) const LinearProgressIndicator(),
          ],
        ),
        onCancel: close,
        onSubmit: getOnSubmit(),
        actions: [
          dialogButton("Cancel", onPressed: close, isOutline: true),
          dialogButton("Verify", onPressed: getOnSubmit()),
        ]);
  });
  // For verification code, desktop update other models in login dialog, mobile need to close login dialog first,
  // otherwise the soft keyboard will jump out on each key press, so mobile update in verification code dialog.
  if (isMobile && res == true) {
    await UserModel.updateOtherModels();
  }

  return res;
}

void logOutConfirmDialog() {
  gFFI.dialogManager.show((setState, close, context) {
    submit() {
      close();
      gFFI.userModel.logOut();
    }

    return CustomAlertDialog(
      content: Text(translate("logout_tip")),
      actions: [
        dialogButton(translate("Cancel"), onPressed: close, isOutline: true),
        dialogButton(translate("OK"), onPressed: submit),
      ],
      onSubmit: submit,
      onCancel: close,
    );
  });
}
