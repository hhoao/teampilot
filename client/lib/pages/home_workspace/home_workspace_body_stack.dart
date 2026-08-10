import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/chat_cubit.dart';
import '../../cubits/workspace_landing_context_cubit.dart';
import '../../models/workspace.dart';
import '../../models/workspace_tab_ref.dart';
import 'home_route_active_scope.dart';
import 'home_workspace_route.dart';
import 'home_workspace_page.dart';
import 'workspace/workspace_page.dart';
import 'workspace/workspace_route_active_scope.dart';
import 'workspace/workspace_tab_deferred_mount.dart';

/// Home page plus one kept-alive [WorkspacePage] per open title-bar tab.
/// Inactive tabs stay mounted under [TpKeepAliveLayer] (skip layout/paint) with
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

    return Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(
          child: Stack(
            fit: StackFit.expand,
            children: [
              _HomeBodyLayer(
                active: activeTab == null,
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
    required this.active,
    required this.child,
  });

  final bool active;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return HomeRouteActiveScope(
      routeActive: active,
      child: TpKeepAliveLayer(
        active: active,
        child: ExcludeSemantics(
          excluding: !active,
          child: TickerMode(
            enabled: active,
            child: IgnorePointer(ignoring: !active, child: child),
          ),
        ),
      ),
    );
  }
}

/// One kept-alive workspace tab. Heavy [WorkspacePage] mounts one frame after
/// the tab becomes active via [WorkspaceTabDeferredMount] (empty card chrome
/// first). Inactive tabs stay under [TpKeepAliveLayer] with [TickerMode] off.
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
    final workspace = context.select<ChatCubit, Workspace?>((c) {
      for (final candidate in c.state.workspaces) {
        if (candidate.workspaceId == tab.workspaceId) return candidate;
      }
      return null;
    });
    if (workspace == null) return const SizedBox.shrink();

    final isActive = activeTabKey == tab.tabKey;
    final view = isActive ? HomeWorkspaceRoute.view(location) : null;
    final configSection = isActive
        ? HomeWorkspaceRoute.workspaceConfigSection(location)
        : null;

    return WorkspaceRouteActiveScope(
      routeActive: isActive,
      view: view,
      configSection: configSection,
      child: RepaintBoundary(
        child: TpKeepAliveLayer(
          active: isActive,
          child: ExcludeSemantics(
            excluding: !isActive,
            child: TickerMode(
              enabled: isActive,
              child: IgnorePointer(
                ignoring: !isActive,
                child: WorkspaceTabDeferredMount(
                  active: isActive,
                  builder: (_) => BlocProvider(
                    create: (_) => WorkspaceLandingContextCubit(
                      workspaceId: tab.workspaceId,
                    )..initialize(workspace),
                    child: WorkspacePage(
                      key: ValueKey('workspace-body-${tab.tabKey}'),
                      workspaceId: tab.workspaceId,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
