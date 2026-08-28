import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/chat_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/workspace.dart';
import '../../utils/session/home_sessions_paint_view.dart';
import '../../services/home_workspace/workspace_display_prefs_store.dart';
import '../../services/home_workspace/workspace_favorites_store.dart';
import '../../theme/workspace_surface_layers.dart';
import '../../widgets/settings/workspace_pane_header.dart';
import 'workspace_sort.dart';
import 'workspaces_tab.dart';

/// Right-hand pane listing every workspace (no team filter).
class HomeAllWorkspacesPane extends StatefulWidget {
  const HomeAllWorkspacesPane({super.key});

  @override
  State<HomeAllWorkspacesPane> createState() => _HomeAllWorkspacesPaneState();
}

class _HomeAllWorkspacesPaneState extends State<HomeAllWorkspacesPane> {
  final _workspaceFavoritesStore = WorkspaceFavoritesStore();
  final _displayPrefsStore = WorkspaceDisplayPrefsStore();
  Set<String> _favoriteWorkspaceIds = {};
  var _gridView = true;
  var _workspaceSort = WorkspaceSort.recentlyUpdated;

  @override
  void initState() {
    super.initState();
    unawaited(_loadWorkspaceFavorites());
    unawaited(_loadDisplayPrefs());
  }

  Future<void> _loadWorkspaceFavorites() async {
    final ids = await _workspaceFavoritesStore.load();
    if (!mounted) return;
    setState(() => _favoriteWorkspaceIds = ids);
  }

  Future<void> _loadDisplayPrefs() async {
    final prefs = await _displayPrefsStore.load();
    if (!mounted) return;
    setState(() {
      _gridView = prefs.gridView;
      _workspaceSort = prefs.sort;
    });
  }

  Future<void> _setGridView(bool gridView) async {
    setState(() => _gridView = gridView);
    await _displayPrefsStore.save(
      WorkspaceDisplayPrefs(gridView: gridView, sort: _workspaceSort),
    );
  }

  Future<void> _setWorkspaceSort(WorkspaceSort sort) async {
    setState(() => _workspaceSort = sort);
    await _displayPrefsStore.save(
      WorkspaceDisplayPrefs(gridView: _gridView, sort: sort),
    );
  }

  Future<void> _toggleWorkspaceFavorite(String workspaceId) async {
    final nowOn = await _workspaceFavoritesStore.toggle(workspaceId);
    if (!mounted) return;
    setState(() {
      final next = {..._favoriteWorkspaceIds};
      if (nowOn) {
        next.add(workspaceId);
      } else {
        next.remove(workspaceId);
      }
      _favoriteWorkspaceIds = next;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final workspaces = context.select<ChatCubit, List<Workspace>>(
      (c) => c.state.workspaces,
    );
    final sessions = watchHomeLibrarySessions(context);

    return ColoredBox(
      color: cs.workspaceCard,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          WorkspacePaneHeader(title: l10n.homeWorkspaceAllWorkspaces),
          Expanded(
            child:
                WorkspacesTab(
                      workspaces: workspaces,
                      sessions: sessions,
                      gridView: _gridView,
                      onToggleView: _setGridView,
                      workspaceSort: _workspaceSort,
                      onWorkspaceSortChanged: _setWorkspaceSort,
                      favoriteWorkspaceIds: _favoriteWorkspaceIds,
                      onToggleWorkspaceFavorite: _toggleWorkspaceFavorite,
                    )
                    .animate(key: const ValueKey('home-all-workspaces'))
                    .fadeIn(duration: 180.ms, curve: Curves.easeOut)
                    .slideX(
                      begin: 0.025,
                      end: 0,
                      duration: 220.ms,
                      curve: Curves.easeOutCubic,
                    ),
          ),
        ],
      ),
    );
  }
}
