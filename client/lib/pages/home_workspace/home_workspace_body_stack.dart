import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/chat_cubit.dart';
import '../../models/workspace.dart';
import '../../models/workspace_tab_ref.dart';
import '../../widgets/file_editor_panel.dart';
import 'home_workspace_route.dart';
import 'home_workspace_page.dart';
import 'workspace/workspace_page.dart';

/// Home page and the **active** workspace tab only. Session/file-tree/terminal
/// state lives in cubits and registries — not in kept-alive widget subtrees.
class HomeWorkspaceBodyStack extends StatelessWidget {
  const HomeWorkspaceBodyStack({
    required this.location,
    super.key,
  });

  final String location;

  @override
  Widget build(BuildContext context) {
    final workspaces = context.select<ChatCubit, List<Workspace>>(
      (c) => c.state.workspaces,
    );
    final activeTab = WorkspaceTabRef.fromLocation(location);
    final showEditor =
        activeTab != null && HomeWorkspaceRoute.view(location) != 'manage';

    Widget body;
    if (activeTab == null) {
      body = HomePage(
        key: const ValueKey('home-v2-body'),
        initialSection: HomeWorkspaceRoute.homeTeamSection(location),
        initialMemberId: HomeWorkspaceRoute.homeMemberId(location),
        initialGlobalView: HomeWorkspaceRoute.homeGlobalView(location),
      );
    } else {
      final workspace = _resolve(workspaces, activeTab.workspaceId);
      body = workspace == null
          ? const SizedBox.shrink()
          : WorkspacePage(
              key: ValueKey('workspace-body-${activeTab.tabKey}'),
              workspaceId: activeTab.workspaceId,
              tabKey: activeTab.tabKey,
              identity: activeTab.identity,
              view: HomeWorkspaceRoute.view(location),
              configSection:
                  HomeWorkspaceRoute.workspaceConfigSection(location),
              routeActive: true,
            );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        body,
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
