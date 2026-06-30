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
                child: _HomePageLayer(location: location),
              ),
              for (final tab in openTabs)
                _WorkspaceTabSlot(
                  key: ValueKey('workspace-tab-slot-${tab.tabKey}'),
                  tab: tab,
                  activeTabKey: activeTab?.tabKey,
                  location: location,
                ),
            ],
          ),
        ),
        if (showEditor) const WorkspaceFloatingEditor(),
      ],
    );
  }
}

class _HomePageLayer extends StatelessWidget {
  const _HomePageLayer({required this.location});

  final String location;

  @override
  Widget build(BuildContext context) {
    return HomePage(
      key: const ValueKey('home-v2-body'),
      initialSection: HomeWorkspaceRoute.homeTeamSection(location),
      initialMemberId: HomeWorkspaceRoute.homeMemberId(location),
      initialGlobalView: HomeWorkspaceRoute.homeGlobalView(location),
    );
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
    required this.activeTabKey,
    required this.location,
    super.key,
  });

  final WorkspaceTabRef tab;
  final String? activeTabKey;
  final String location;

  @override
  Widget build(BuildContext context) {
    final workspace = context.select<ChatCubit, Workspace?>(
      (c) {
        for (final candidate in c.state.workspaces) {
          if (candidate.workspaceId == tab.workspaceId) return candidate;
        }
        return null;
      },
    );
    if (workspace == null) return const SizedBox.shrink();

    final isActive = activeTabKey == tab.tabKey;
    final view =
        isActive ? HomeWorkspaceRoute.view(location) : null;
    final configSection = isActive
        ? HomeWorkspaceRoute.workspaceConfigSection(location)
        : null;

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
