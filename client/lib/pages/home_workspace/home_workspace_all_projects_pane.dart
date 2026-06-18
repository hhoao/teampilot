import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/chat_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/app_project.dart';
import '../../models/app_session.dart';
import '../../services/home_workspace/home_workspace_project_display_prefs_store.dart';
import '../../services/home_workspace/home_workspace_project_favorites_store.dart';
import '../../theme/workspace_surface_layers.dart';
import 'home_workspace_project_sort.dart';
import 'home_workspace_projects_tab.dart';

/// Right-hand pane listing every project (no team filter).
class HomeWorkspaceAllProjectsPane extends StatefulWidget {
  const HomeWorkspaceAllProjectsPane({super.key});

  @override
  State<HomeWorkspaceAllProjectsPane> createState() =>
      _HomeWorkspaceAllProjectsPaneState();
}

class _HomeWorkspaceAllProjectsPaneState
    extends State<HomeWorkspaceAllProjectsPane> {
  final _projectFavoritesStore = HomeWorkspaceProjectFavoritesStore();
  final _displayPrefsStore = HomeWorkspaceProjectDisplayPrefsStore();
  Set<String> _favoriteProjectIds = {};
  var _gridView = true;
  var _projectSort = HomeWorkspaceProjectSort.recentlyUpdated;

  @override
  void initState() {
    super.initState();
    unawaited(_loadProjectFavorites());
    unawaited(_loadDisplayPrefs());
  }

  Future<void> _loadProjectFavorites() async {
    final ids = await _projectFavoritesStore.load();
    if (!mounted) return;
    setState(() => _favoriteProjectIds = ids);
  }

  Future<void> _loadDisplayPrefs() async {
    final prefs = await _displayPrefsStore.load();
    if (!mounted) return;
    setState(() {
      _gridView = prefs.gridView;
      _projectSort = prefs.sort;
    });
  }

  Future<void> _setGridView(bool gridView) async {
    setState(() => _gridView = gridView);
    await _displayPrefsStore.save(
      HomeWorkspaceProjectDisplayPrefs(gridView: gridView, sort: _projectSort),
    );
  }

  Future<void> _setProjectSort(HomeWorkspaceProjectSort sort) async {
    setState(() => _projectSort = sort);
    await _displayPrefsStore.save(
      HomeWorkspaceProjectDisplayPrefs(gridView: _gridView, sort: sort),
    );
  }

  Future<void> _toggleProjectFavorite(String projectId) async {
    final nowOn = await _projectFavoritesStore.toggle(projectId);
    if (!mounted) return;
    setState(() {
      final next = {..._favoriteProjectIds};
      if (nowOn) {
        next.add(projectId);
      } else {
        next.remove(projectId);
      }
      _favoriteProjectIds = next;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final projects = context.select<ChatCubit, List<AppProject>>(
      (c) => c.state.projects,
    );
    final sessions = context.select<ChatCubit, List<AppSession>>(
      (c) => c.state.sessions,
    );

    return ColoredBox(
      color: cs.workspaceCard,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.homeWorkspaceAllProjects,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(color: cs.onSurface),
          ),
          const SizedBox(height: 16),
          Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.5)),
          const SizedBox(height: 16),
          Expanded(
            child: HomeWorkspaceProjectsTab(
              projects: projects,
              sessions: sessions,
              gridView: _gridView,
              onToggleView: _setGridView,
              projectSort: _projectSort,
              onProjectSortChanged: _setProjectSort,
              favoriteProjectIds: _favoriteProjectIds,
              onToggleProjectFavorite: _toggleProjectFavorite,
            )
                .animate(key: const ValueKey('home-all-projects'))
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
