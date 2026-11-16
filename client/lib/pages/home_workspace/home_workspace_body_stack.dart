import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/chat_cubit.dart';
import '../../cubits/workspace_landing_context_cubit.dart';
import '../../models/workspace.dart';
import '../../models/workspace_tab_ref.dart';
import '../team_config/team_config_section.dart';
import 'home_route_active_scope.dart';
import 'home_workspace_global_section.dart';
import 'home_workspace_route.dart';
import 'home_workspace_page.dart';
import 'workspace/workspace_page.dart';
import 'workspace/workspace_config_section.dart';
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

/// Caches the [HomePage] instance by its route-derived inputs. Workspace tab
/// switches rebuild the body stack with a new location, but the home page's
/// inputs are all null while a workspace tab is active — returning the same
/// widget instance skips rebuilding the whole (kept-alive, inactive) home
/// subtree on every switch.
class _HomePageLayer extends StatefulWidget {
  const _HomePageLayer({required this.location});

  final String location;

  @override
  State<_HomePageLayer> createState() => _HomePageLayerState();
}

class _HomePageLayerState extends State<_HomePageLayer> {
  ({TeamConfigSection? section, String? memberId, HomeGlobalView? globalView})?
  _inputs;
  Widget? _page;

  @override
  Widget build(BuildContext context) {
    final inputs = (
      section: HomeWorkspaceRoute.homeTeamSection(widget.location),
      memberId: HomeWorkspaceRoute.homeMemberId(widget.location),
      globalView: HomeWorkspaceRoute.homeGlobalView(widget.location),
    );
    final cached = _page;
    if (cached != null && inputs == _inputs) return cached;
    final page = HomePage(
      key: const ValueKey('home-v2-body'),
      initialSection: inputs.section,
      initialMemberId: inputs.memberId,
      initialGlobalView: inputs.globalView,
    );
    _inputs = inputs;
    _page = page;
    return page;
  }
}

class _HomeBodyLayer extends StatelessWidget {
  const _HomeBodyLayer({required this.active, required this.child});

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
///
/// The built page widget is cached by workspace value: a route change (tab
/// switch) rebuilds this slot with a new location, but returning the same
/// widget instance lets Flutter skip rebuilding the whole kept-alive
/// [WorkspacePage] subtree. Mirrors [_HomePageLayer].
class _WorkspaceTabSlot extends StatefulWidget {
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
  State<_WorkspaceTabSlot> createState() => _WorkspaceTabSlotState();
}

/// Route-derived inputs that determine what the tab slot renders. Background
/// slots force [view] / [configSection] / [session] to null so their inputs
/// stay stable across sibling-tab navigation.
typedef _RouteInputs = ({
  bool active,
  String? view,
  WorkspaceConfigSection? configSection,
  String? session,
});

class _WorkspaceTabSlotState extends State<_WorkspaceTabSlot> {
  Workspace? _pageWorkspace;
  Widget? _page;

  /// Stable activation signal for this tab. Consumers listen to it instead of
  /// registering an inherited dependency, so a background tab is never marked
  /// dirty when a sibling tab activates.
  late final ValueNotifier<bool> _active;

  /// Route-resync signal: activation plus `view` / `configSection` / `session`
  /// changes for the foreground slot. Background slots keep stable inputs.
  late final ValueNotifier<int> _routeRevision;

  _RouteInputs? _publishedInputs;
  bool _publicationScheduled = false;

  bool get _isActive => widget.activeTabKey == widget.tab.tabKey;

  _RouteInputs _routeInputs() {
    final active = _isActive;
    return (
      active: active,
      view: active ? HomeWorkspaceRoute.view(widget.location) : null,
      configSection: active
          ? HomeWorkspaceRoute.workspaceConfigSection(widget.location)
          : null,
      session: active ? HomeWorkspaceRoute.session(widget.location) : null,
    );
  }

  @override
  void initState() {
    super.initState();
    _active = ValueNotifier<bool>(_isActive);
    _routeRevision = ValueNotifier<int>(0);
    _publishedInputs = _routeInputs();
  }

  @override
  void didUpdateWidget(covariant _WorkspaceTabSlot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_routeInputs() != _publishedInputs) _schedulePublication();
  }

  /// Defer the notification: [didUpdateWidget] runs inside the build phase and
  /// listeners call setState. Publishing post-frame also guarantees descendants
  /// read the freshly mounted [WorkspaceRouteActiveScope] via a snapshot read.
  void _schedulePublication() {
    if (_publicationScheduled) return;
    _publicationScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _publicationScheduled = false;
      if (!mounted) return;
      final inputs = _routeInputs();
      if (inputs == _publishedInputs) return;
      _publishedInputs = inputs;
      if (_active.value != inputs.active) _active.value = inputs.active;
      _routeRevision.value++;
    });
  }

  @override
  void dispose() {
    _active.dispose();
    _routeRevision.dispose();
    super.dispose();
  }

  Widget _pageFor(Workspace workspace) {
    final cached = _page;
    if (cached != null && _pageWorkspace == workspace) return cached;
    final page = BlocProvider(
      create: (_) => WorkspaceLandingContextCubit(
        workspaceId: widget.tab.workspaceId,
      )..initialize(workspace),
      child: WorkspacePage(
        key: ValueKey('workspace-body-${widget.tab.tabKey}'),
        workspaceId: widget.tab.workspaceId,
      ),
    );
    _pageWorkspace = workspace;
    _page = page;
    return page;
  }

  @override
  Widget build(BuildContext context) {
    final workspace = context.select<ChatCubit, Workspace?>((c) {
      for (final candidate in c.state.workspaces) {
        if (candidate.workspaceId == widget.tab.workspaceId) return candidate;
      }
      return null;
    });
    if (workspace == null) return const SizedBox.shrink();

    final isActive = widget.activeTabKey == widget.tab.tabKey;
    final view = isActive ? HomeWorkspaceRoute.view(widget.location) : null;
    final configSection = isActive
        ? HomeWorkspaceRoute.workspaceConfigSection(widget.location)
        : null;
    final page = _pageFor(workspace);

    return WorkspaceRouteActiveScope(
      routeActive: isActive,
      view: view,
      configSection: configSection,
      activeListenable: _active,
      routeRevisionListenable: _routeRevision,
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
                  builder: (_) => page,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
