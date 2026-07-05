import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../cubits/chat_cubit.dart';
import '../../../cubits/launch_profile_cubit.dart';
import '../../../cubits/workspace_landing_context_cubit.dart';
import '../../../l10n/l10n_extensions.dart';
import '../../../models/landing_launch_context.dart';
import '../../../models/workspace.dart';
import '../../../models/launch_profile_kind.dart';
import '../../../models/launch_profile.dart';
import '../../../pages/home_workspace/home_workspace_route.dart';
import '../../../theme/workspace_surface_layers.dart';
import '../../../utils/workspace_chrome_profile.dart';
import 'workspace_config_workspace.dart';
import 'workspace_rail.dart';
import 'workspace_section.dart';
import 'workspace_split_pane.dart';
import 'workspace_config_section.dart';
import 'workspace_route_active_scope.dart';

/// Workspace work page with conversations + manage panes.
class WorkspacePage extends StatefulWidget {
  const WorkspacePage({required this.workspaceId, super.key});

  final String workspaceId;

  String get tabKey => workspaceId;

  @override
  State<WorkspacePage> createState() => _WorkspacePageState();
}

class _WorkspacePageState extends State<WorkspacePage> {
  late WorkspaceSection _section = WorkspaceSection.conversations;
  var _visitedManage = false;
  Widget? _frozenPage;
  bool _wasRouteActive = false;
  String? _lastScopeView;
  bool _activationScheduled = false;

  WorkspaceRouteActiveScope? _readScope(BuildContext context) {
    return context.getInheritedWidgetOfExactType<WorkspaceRouteActiveScope>();
  }

  WorkspaceConfigSection _configSection(BuildContext context) =>
      _readScope(context)?.configSection ?? WorkspaceConfigSection.settings;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = _readScope(context);
    final active = scope?.routeActive ?? true;
    final view = scope?.view;
    if (active && !_wasRouteActive) {
      _scheduleActivation();
    }
    if (active &&
        (view != _lastScopeView || (!_wasRouteActive && view == 'manage'))) {
      if (view == 'manage') _visitedManage = true;
      setState(() {
        _section = _sectionFromRoute(view);
        if (_section == WorkspaceSection.manage) _visitedManage = true;
      });
    }
    _wasRouteActive = active;
    _lastScopeView = view;
    _syncProfileFromRoute();
  }

  void _syncProfileFromRoute() {
    final location = GoRouterState.of(context).uri.toString();
    final routeProfile = HomeWorkspaceRoute.profile(location)?.trim() ?? '';
    if (routeProfile.isEmpty) return;
    final cubit = context.read<WorkspaceLandingContextCubit>();
    final current = cubit.state.context.profileId;
    if (current == routeProfile) return;
    final launchProfiles = context.read<LaunchProfileCubit>();
    final profile = launchProfiles.byId(routeProfile);
    if (profile == null) return;
    final next = profile.kind == LaunchProfileKind.personal
        ? LandingLaunchContext(isPersonal: true, personalProfileId: profile.id)
        : LandingLaunchContext(isPersonal: false, teamId: profile.id);
    cubit.update(next);
  }

  WorkspaceSection _sectionFromRoute(String? view) {
    if (view == 'manage') {
      return WorkspaceSection.manage;
    }
    return WorkspaceSection.conversations;
  }

  void _scheduleActivation() {
    if (_activationScheduled) return;
    _activationScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _activationScheduled = false;
      if (!mounted) return;
      if (!(_readScope(context)?.routeActive ?? false)) return;
      _activateRoute();
    });
  }

  void _invalidateFrozenPage() => _frozenPage = null;

  void _activateRoute() {
    context.read<ChatCubit>().activateWorkspaceTab(
      workspaceTabKey: widget.tabKey,
      scopeSessionsToSelectedTeam: false,
    );
    unawaited(
      context.read<ChatCubit>().ensureSessionsForWorkspace(widget.workspaceId),
    );
  }

  void _onSectionChanged(
    WorkspaceSection section,
    Workspace workspace,
    LaunchProfile workspaceIdentity,
  ) {
    setState(() {
      _section = section;
      if (section == WorkspaceSection.manage) {
        _visitedManage = true;
      }
    });

    final params = <String, String>{
      'profile': workspaceIdentity.id,
      if (section == WorkspaceSection.manage) 'view': 'manage',
    };
    final path = Uri(
      path: '/home-v2/workspace/${workspace.workspaceId}',
      queryParameters: params,
    ).toString();
    final current = GoRouterState.of(context).uri.toString();
    if (current == path) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (GoRouterState.of(context).uri.toString() != path) {
        context.go(path);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<WorkspaceRouteActiveScope>();
    final routeActive = scope?.routeActive ?? true;
    final body = routeActive
        ? _buildAndCacheLivePage(context)
        : (_frozenPage ?? const SizedBox.shrink());
    return BlocListener<ChatCubit, ChatState>(
      listenWhen: (previous, next) {
        if (previous.workspaces == next.workspaces) return false;
        return _findWorkspace(previous.workspaces, widget.workspaceId) !=
            _findWorkspace(next.workspaces, widget.workspaceId);
      },
      listener: (context, state) {
        _invalidateFrozenPage();
        if (routeActive && mounted) setState(() {});
      },
      child: body,
    );
  }

  Widget _buildAndCacheLivePage(BuildContext context) {
    final built = _buildLivePage(context);
    _frozenPage = built;
    return built;
  }

  Widget _buildLivePage(BuildContext context) {
    final l10n = context.l10n;

    final workspace = context.select<ChatCubit, Workspace?>(
      (c) => _findWorkspace(c.state.workspaces, widget.workspaceId),
    );

    if (workspace == null) {
      return WorkspacePageCardShell(
        chrome: WorkspacePageChrome.workspace,
        child: _MissingWorkspace(label: l10n.homeWorkspaceEmptyWorkspaces),
      );
    }

    final location = GoRouterState.of(context).uri.toString();
    final routeProfile = HomeWorkspaceRoute.profile(location);
    final workspaceIdentity = resolveWorkspaceChromeProfile(
      context.watch<LaunchProfileCubit>(),
      workspace,
      routeProfileId: routeProfile,
    );
    if (workspaceIdentity == null) {
      return WorkspacePageCardShell(
        chrome: WorkspacePageChrome.workspace,
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    final cardBody = _buildCardBody(workspace: workspace);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        WorkspaceRail(
          section: _section,
          onSectionChanged: (section) =>
              _onSectionChanged(section, workspace, workspaceIdentity),
          onLogoTap: () => context.go('/home-v2'),
        ),
        Expanded(
          child: WorkspacePageCardShell(
            chrome: WorkspacePageChrome.workspace,
            omitLeftPadding: true,
            child: cardBody,
          ),
        ),
      ],
    );
  }

  Widget _buildCardBody({required Workspace workspace}) {
    final showManage = _section == WorkspaceSection.manage;
    return Stack(
      fit: StackFit.expand,
      children: [
        Offstage(
          offstage: showManage,
          child: TickerMode(
            enabled: !showManage,
            child: WorkspaceSplitPane(
              key: ValueKey('conversations-${widget.tabKey}'),
              workspace: workspace,
              tabScopeId: widget.tabKey,
            ),
          ),
        ),
        if (_visitedManage)
          Offstage(
            offstage: !showManage,
            child: TickerMode(
              enabled: showManage,
              child: WorkspaceConfigPanel(
                workspace: workspace,
                section: _configSection(context),
              ),
            ),
          ),
      ],
    );
  }

  static Workspace? _findWorkspace(List<Workspace> workspaces, String id) {
    for (final p in workspaces) {
      if (p.workspaceId == id) return p;
    }
    return null;
  }
}

class _MissingWorkspace extends StatelessWidget {
  const _MissingWorkspace({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Text(label, style: TextStyle(color: cs.onSurfaceVariant)),
    );
  }
}
