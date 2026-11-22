import 'package:flutter/material.dart';
import 'package:flutter_hbb/common/theme/bd_theme.dart';

class DesktopTitleBar extends StatelessWidget {
  final Widget? child;

  const DesktopTitleBar({Key? key, this.child}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: context.bd.titlebar),
      child: Row(
        children: [
          Expanded(
            child: child ?? Offstage(),
          )
        ],
      ),
    );
  }
}