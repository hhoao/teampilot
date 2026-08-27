import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

/// Keep-alive stack of conversation workbench vs workspace-manage.
///
/// On narrow layouts this must be the [MobileWorkspaceDrawerHost] *child* so
/// the hamburger drawer stays a sibling overlay above manage.
class WorkspaceManageOverlayStack extends StatelessWidget {
  const WorkspaceManageOverlayStack({
    required this.showManage,
    required this.conversations,
    required this.manage,
    super.key,
  });

  final bool showManage;
  final Widget conversations;
  final Widget manage;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        TpKeepAliveLayer(
          active: !showManage,
          child: TickerMode(
            enabled: !showManage,
            child: IgnorePointer(ignoring: showManage, child: conversations),
          ),
        ),
        TpKeepAliveLayer(
          active: showManage,
          child: TickerMode(
            enabled: showManage,
            child: IgnorePointer(ignoring: !showManage, child: manage),
          ),
        ),
      ],
    );
  }
}
