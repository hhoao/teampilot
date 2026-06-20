import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/chat_cubit.dart';
import '../../models/launch_profile_ref.dart';
import '../../models/workspace.dart';
import 'home_workspace_page.dart';
import 'home_workspace_route.dart';
import 'workspace/workspace_page.dart';

/// Keeps the home page and every open workspace tab mounted (Orca-style).
///
/// GoRouter still drives the URL, but this stack — not the routed [child] —
/// owns the widget tree so switching workspace tabs does not dispose
/// [WorkspacePage] → [RightToolsPanel] → file-tree scroll/filter state.
class HomeWorkspaceBodyStack extends StatelessWidget {
  const HomeWorkspaceBodyStack({
    required this.location,
    required this.openWorkspaceIds,
    required this.identityForWorkspace,
    super.key,
  });

  final String location;
  final List<String> openWorkspaceIds;
  final LaunchProfileRef Function(String workspaceId) identityForWorkspace;

  @override
  Widget build(BuildContext context) {
    final workspaces = context.select<ChatCubit, List<Workspace>>(
      (c) => c.state.workspaces,
    );
    final activeId = HomeWorkspaceRoute.workspaceId(location);
    final children = <Widget>[
      HomePage(
        key: const ValueKey('home-v2-body'),
        initialSection: HomeWorkspaceRoute.homeTeamSection(location),
        initialMemberId: HomeWorkspaceRoute.homeMemberId(location),
        initialGlobalView: HomeWorkspaceRoute.homeGlobalView(location),
      ),
      for (final id in openWorkspaceIds)
        if (_resolve(workspaces, id) != null)
          TickerMode(
            key: ValueKey('workspace-ticker-$id'),
            enabled: id == activeId,
            child: WorkspacePage(
              key: ValueKey('workspace-body-$id'),
              workspaceId: id,
              identity: identityForWorkspace(id),
              view: activeId == id ? HomeWorkspaceRoute.view(location) : null,
              configSection: activeId == id
                  ? HomeWorkspaceRoute.workspaceConfigSection(location)
                  : null,
              routeActive: id == activeId,
            ),
          ),
    ];

    var index = 0;
    if (activeId != null) {
      final wsIndex = openWorkspaceIds.indexOf(activeId);
      if (wsIndex >= 0) {
        index = wsIndex + 1;
      }
    }

    return IndexedStack(
      index: index.clamp(0, children.length - 1),
      sizing: StackFit.expand,
      children: children,
    );
  }

  static Workspace? _resolve(List<Workspace> workspaces, String id) {
    for (final workspace in workspaces) {
      if (workspace.workspaceId == id) return workspace;
    }
    return null;
  }
}
