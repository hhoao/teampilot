import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/chat_cubit.dart';
import '../../models/workspace.dart';
import '../../models/workspace_tab_ref.dart';
import '../../widgets/file_editor_panel.dart';
import 'home_workspace_route.dart';
import 'home_workspace_page.dart';
import 'workspace/workspace_page.dart';

/// Keeps the home page and every open workspace tab mounted (Orca-style).
///
/// GoRouter still drives the URL, but this stack — not the routed [child] —
/// owns the widget tree so switching workspace tabs does not dispose
/// [WorkspacePage] → [RightToolsPanel] → file-tree scroll/filter state.
class HomeWorkspaceBodyStack extends StatelessWidget {
  const HomeWorkspaceBodyStack({
    required this.location,
    required this.openTabs,
    super.key,
  });

  final String location;
  final List<WorkspaceTabRef> openTabs;

  @override
  Widget build(BuildContext context) {
    final workspaces = context.select<ChatCubit, List<Workspace>>(
      (c) => c.state.workspaces,
    );
    final activeTab = WorkspaceTabRef.fromLocation(location);
    final children = <Widget>[
      HomePage(
        key: const ValueKey('home-v2-body'),
        initialSection: HomeWorkspaceRoute.homeTeamSection(location),
        initialMemberId: HomeWorkspaceRoute.homeMemberId(location),
        initialGlobalView: HomeWorkspaceRoute.homeGlobalView(location),
      ),
      for (final tab in openTabs)
        if (_resolve(workspaces, tab.workspaceId) != null)
          TickerMode(
            key: ValueKey('workspace-ticker-${tab.tabKey}'),
            enabled: activeTab?.tabKey == tab.tabKey,
            child: WorkspacePage(
              key: ValueKey('workspace-body-${tab.tabKey}'),
              workspaceId: tab.workspaceId,
              tabKey: tab.tabKey,
              identity: tab.identity,
              view: activeTab?.tabKey == tab.tabKey
                  ? HomeWorkspaceRoute.view(location)
                  : null,
              configSection: activeTab?.tabKey == tab.tabKey
                  ? HomeWorkspaceRoute.workspaceConfigSection(location)
                  : null,
              routeActive: activeTab?.tabKey == tab.tabKey,
            ),
          ),
    ];

    var index = 0;
    if (activeTab != null) {
      final wsIndex = openTabs.indexWhere((t) => t.tabKey == activeTab.tabKey);
      if (wsIndex >= 0) {
        index = wsIndex + 1;
      }
    }

    // The floating file editor is hosted once, above the workspace-tab stack —
    // never inside a per-tab ChatWorkbench. EditorCubit (controller + per-file
    // GlobalKey) is app-global, so mounting it in every kept-alive tab would
    // raise "Duplicate GlobalKey" / reparent it across tabs' LayoutBuilders.
    // Show it only when a workspace tab is foreground and on its conversations
    // view (not the home page or a manage/config view).
    final showEditor =
        activeTab != null && HomeWorkspaceRoute.view(location) != 'manage';

    return Stack(
      fit: StackFit.expand,
      children: [
        IndexedStack(
          index: index,
          sizing: StackFit.expand,
          children: children,
        ),
        if (showEditor) const WorkspaceFloatingEditor(),
      ],
    );
  }

  static Workspace? _resolve(List<Workspace> workspaces, String id) {
    for (final workspace in workspaces) {
      if (workspace.workspaceId == id) return workspace;
    }
    return null;
  }
}
