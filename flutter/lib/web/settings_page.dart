import 'package:flutter/material.dart';
import 'package:flutter_hbb/desktop/pages/desktop_setting_page.dart';
import 'package:flutter_hbb/common/widgets/nd/nd_icons.dart';

class WebSettingsPage extends StatelessWidget {
  const WebSettingsPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return _buildDesktopButton(context);
  }

  Widget _buildDesktopButton(BuildContext context) {
    return IconButton(
      icon: const Icon(NdIcons.moreVert),
      onPressed: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (BuildContext context) =>
                DesktopSettingPage(initialTabkey: SettingsTabKey.general),
          ),
        );
      },
    );
  }
}
