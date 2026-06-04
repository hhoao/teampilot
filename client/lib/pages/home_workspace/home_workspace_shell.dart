import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../cubits/chat_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/app_project.dart';
import '../../theme/workspace_surface_layers.dart';
import 'home_workspace_title_bar.dart';

/// Persistent chrome for the workspace-home route family. Owns the open project
/// tabs (kept until explicitly closed) and renders the title bar once above the
/// routed [child] (home view or a project view).
class HomeWorkspaceShell extends StatefulWidget {
  const HomeWorkspaceShell({
    required this.location,
    required this.child,
    super.key,
  });

  /// Current router location (e.g. `/home-v2` or `/home-v2/project/<id>`).
  final String location;
  final Widget child;

  @override
  State<HomeWorkspaceShell> createState() => _HomeWorkspaceShellState();
}

class _HomeWorkspaceShellState extends State<HomeWorkspaceShell> {
  /// Open project ids in tab order; persists across navigation.
  List<String> _openIds = const [];

  @override
  void initState() {
    super.initState();
    _ensureOpen(_projectIdFromLocation(widget.location));
  }

  @override
  void didUpdateWidget(covariant HomeWorkspaceShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.location != widget.location) {
      final id = _projectIdFromLocation(widget.location);
      if (id != null && !_openIds.contains(id)) {
        setState(() => _openIds = [..._openIds, id]);
      }
    }
  }

  void _ensureOpen(String? id) {
    if (id != null && !_openIds.contains(id)) {
      _openIds = [..._openIds, id];
    }
  }

  static String? _projectIdFromLocation(String location) {
    final segments = Uri.parse(location).pathSegments;
    if (segments.length >= 3 &&
        segments[0] == 'home-v2' &&
        segments[1] == 'project') {
      return segments[2];
    }
    return null;
  }

  void _selectTab(String id) => context.go('/home-v2/project/$id');

  void _goHome() => context.go('/home-v2');

  Future<void> _closeTab(String id) async {
    if (!_openIds.contains(id)) return;
    // Closing a project tab always terminates that project's running sessions;
    // confirm first when there are any so the user can cancel.
    final chat = context.read<ChatCubit>();
    final running = chat.openTabCountForProject(id);
    if (running > 0) {
      final confirmed = await _confirmCloseWithSessions(running);
      if (confirmed != true || !mounted) return;
      chat.closeTabsForProject(id);
    }
    final idx = _openIds.indexOf(id);
    if (idx < 0) return;
    final wasActive = id == _projectIdFromLocation(widget.location);
    final next = [..._openIds]..removeAt(idx);
    setState(() => _openIds = next);
    if (wasActive) {
      if (next.isEmpty) {
        _goHome();
      } else {
        _selectTab(next[idx.clamp(0, next.length - 1)]);
      }
    }
  }

  Future<bool?> _confirmCloseWithSessions(int running) {
    final l10n = context.l10n;
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.homeWorkspaceCloseProjectTitle),
        content: Text(l10n.homeWorkspaceCloseProjectMessage(running)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.homeWorkspaceCloseProjectConfirm),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final projects = context.select<ChatCubit, List<AppProject>>(
      (c) => c.state.projects,
    );
    final activeId = _projectIdFromLocation(widget.location);
    // Show every open project tab across all teams (IDE-style open editors).
    // Selecting a tab switches the active team to the project's team via
    // HomeWorkspaceProjectPage, so the sidebar/content stay in sync.
    final tabs = <HomeProjectTab>[
      for (final id in _openIds)
        if (_resolve(projects, id) case final p?)
          HomeProjectTab(id: id, name: p.effectiveDisplay),
    ];

    return Scaffold(
      backgroundColor: cs.workspacePage,
      body: Column(
        children: [
          HomeWorkspaceTitleBar(
            tabs: tabs,
            activeProjectId: activeId,
            onHomeTap: _goHome,
            onSelectTab: _selectTab,
            onCloseTab: _closeTab,
          ),
          Expanded(
            child: SafeArea(top: false, child: widget.child),
          ),
        ],
      ),
    );
  }

  static AppProject? _resolve(List<AppProject> projects, String id) {
    for (final p in projects) {
      if (p.projectId == id) return p;
    }
    return null;
  }
}
