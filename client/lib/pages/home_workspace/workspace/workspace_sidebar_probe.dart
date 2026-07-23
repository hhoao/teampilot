import 'package:flutter/material.dart';

/// Keys for widget tests that assert sidebar rebuild isolation.
@visibleForTesting
class WorkspaceSidebarKeys {
  const WorkspaceSidebarKeys._();

  static const conversationListProbe = Key(
    'workspace-sidebar-conversation-list-probe',
  );
  static const runningHostProbe = Key('workspace-sidebar-running-host-probe');
}

/// Counts [build] invocations for rebuild-isolation widget tests.
@visibleForTesting
class SidebarRebuildProbe extends StatefulWidget {
  const SidebarRebuildProbe({required this.child, super.key});

  final Widget child;

  @override
  State<SidebarRebuildProbe> createState() => SidebarRebuildProbeState();
}

@visibleForTesting
class SidebarRebuildProbeState extends State<SidebarRebuildProbe> {
  int buildCount = 0;

  @override
  Widget build(BuildContext context) {
    buildCount++;
    return widget.child;
  }
}
