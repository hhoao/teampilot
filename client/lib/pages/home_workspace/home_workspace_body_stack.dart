import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/chat_cubit.dart';
import '../../models/workspace.dart';
import '../../models/workspace_tab_ref.dart';
import '../../widgets/file_editor_panel.dart';
import 'home_workspace_route.dart';
import 'home_workspace_page.dart';
import 'workspace/workspace_config_section.dart';
import 'workspace/workspace_page.dart';
import 'workspace/workspace_route_active_scope.dart';

/// Home page plus one kept-alive [WorkspacePage] per open title-bar tab.
/// Inactive tabs stay mounted under [Offstage] (no layout/paint) with
/// [TickerMode] disabled so shell terminals detach and OS file drops stay scoped
/// to the foreground workspace.
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
    final activeTab = WorkspaceTabRef.fromLocation(location);
    final showEditor =
        activeTab != null && HomeWorkspaceRoute.view(location) != 'manage';
    final workspaces = context.select<ChatCubit, List<Workspace>>(
      (c) => c.state.workspaces,
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(
          child: Stack(
            fit: StackFit.expand,
            children: [
              _HomeBodyLayer(
                offstage: activeTab != null,
                enabled: activeTab == null,
                child: HomePage(
                  key: const ValueKey('home-v2-body'),
                  initialSection: HomeWorkspaceRoute.homeTeamSection(location),
                  initialMemberId: HomeWorkspaceRoute.homeMemberId(location),
                  initialGlobalView: HomeWorkspaceRoute.homeGlobalView(location),
                ),
              ),
              for (final tab in openTabs)
                if (_resolve(workspaces, tab.workspaceId) case final workspace?)
                  _WorkspaceTabSlot(
                    key: ValueKey('workspace-tab-slot-${tab.tabKey}'),
                    tab: tab,
                    isActive: activeTab?.tabKey == tab.tabKey,
                    view: activeTab?.tabKey == tab.tabKey
                        ? HomeWorkspaceRoute.view(location)
                        : null,
                    configSection: activeTab?.tabKey == tab.tabKey
                        ? HomeWorkspaceRoute.workspaceConfigSection(location)
                        : null,
                  ),
            ],
          ),
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

class _HomeBodyLayer extends StatelessWidget {
  const _HomeBodyLayer({
    required this.offstage,
    required this.enabled,
    required this.child,
  });

  final bool offstage;
  final bool enabled;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      excluding: offstage,
      child: Offstage(
        offstage: offstage,
        child: TickerMode(
          enabled: enabled,
          child: IgnorePointer(
            ignoring: offstage,
            child: child,
          ),
        ),
      ),
    );
  }
}

/// One kept-alive workspace tab. [WorkspacePage] is a stable child; only the
/// [WorkspaceRouteActiveScope] + visibility wrappers update on tab switches.
class _WorkspaceTabSlot extends StatelessWidget {
  const _WorkspaceTabSlot({
    required this.tab,
    required this.isActive,
    required this.view,
    required this.configSection,
    super.key,
  });

  final WorkspaceTabRef tab;
  final bool isActive;
  final String? view;
  final WorkspaceConfigSection? configSection;

  @override
  Widget build(BuildContext context) {
    return WorkspaceRouteActiveScope(
      routeActive: isActive,
      view: view,
      configSection: configSection,
      child: RepaintBoundary(
        child: ExcludeSemantics(
          excluding: !isActive,
          child: Offstage(
            offstage: !isActive,
            child: TickerMode(
              enabled: isActive,
              child: IgnorePointer(
                ignoring: !isActive,
                child: WorkspacePage(
                  key: ValueKey('workspace-body-${tab.tabKey}'),
                  workspaceId: tab.workspaceId,
                  tabKey: tab.tabKey,
                  identity: tab.identity,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
