// Made-up data of the design mockups (Fernhill IT, Mara Jensen, Tom Becker).

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart' show translate;
import 'package:flutter_hbb/common/widgets/nd/nd.dart';
import 'package:flutter_svg/flutter_svg.dart';

const fernAccent = '#3aa35c';
const fernServer = 'help.fernhill.example';
const fernCompany = 'Fernhill IT';

const _fernSvg =
    '<svg viewBox="0 0 24 24"><path d="M3 21C3 10.5 9.5 3 21 3c0 11.5-7.5 18-18 18z" fill="#3aa35c"/><path d="M5.5 18.5 17 7" stroke="#fff" stroke-width="1.6" stroke-linecap="round"/><path d="M9 15h4.5M11.5 12.5H16M9 15v-4.5M11.5 12.5V8" stroke="#fff" stroke-width="1.4" stroke-linecap="round"/></svg>';

Widget fernLogo() => SvgPicture.string(_fernSvg);

/// The main window's title bar as the app draws it.
Widget mainTitleBar({
  bool settingsOpen = false,
  bool branded = false,
}) {
  return NdTitleBar(
    brand: branded
        ? NdTitleBrand(serverLogo: fernLogo(), serverName: fernCompany)
        : NdTitleBrand(wordmark: !settingsOpen),
    tabs: settingsOpen
        ? [
            NdWindowTab(label: translate('Home'), icon: NdIcons.home),
            NdWindowTab(
                label: translate('Settings'),
                icon: NdIcons.settings,
                selected: true,
                onClose: () {}),
          ]
        : const [],
    actions: settingsOpen
        ? const []
        : [NdTitleBarText(label: translate('Settings'), onTap: () {})],
    controls: NdWindowControls(
        onMinimize: () {}, onMaximize: () {}, onClose: () {}),
  );
}

Widget mainWindow(Widget page,
        {bool settingsOpen = false, bool branded = false}) =>
    NdWindowFrame(
      titleBar: mainTitleBar(settingsOpen: settingsOpen, branded: branded),
      child: page,
    );

/// A dialog over a page, with the scrim.
Widget withDialog(BuildContext context, Widget page, Widget dialog) => Stack(
      children: [
        page,
        Positioned.fill(child: ColoredBox(color: context.nd.scrim)),
        Positioned.fill(child: Center(child: dialog)),
      ],
    );

const mainSize = Size(1100, 720);
