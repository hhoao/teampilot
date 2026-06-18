import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../cubits/chat_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/app_workspace.dart';
import '../../models/app_session.dart';
import '../../services/home_workspace/home_workspace_workspace_display_prefs_store.dart';
import '../../services/home_workspace/home_workspace_workspace_favorites_store.dart';
import '../../services/home_workspace/home_workspace_recent_workspaces_store.dart';
import 'home_workspace_workspace_sort.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/workspace_surface_layers.dart';
import 'home_workspace_library_view.dart';
import 'home_workspace_workspaces_tab.dart';

/// Favorites or recently visited workspaces in the workspace home right pane.
class HomeLibrarySection extends StatefulWidget {
  const HomeLibrarySection({required this.view, super.key});

  final HomeLibraryView view;

  @override
  State<HomeLibrarySection> createState() =>
      _HomeLibrarySectionState();
}

class _HomeLibrarySectionState extends State<HomeLibrarySection> {
  final _favoritesStore = WorkspaceFavoritesStore();
  final _recentStore = HomeRecentWorkspacesStore();
  final _displayPrefsStore = WorkspaceDisplayPrefsStore();
  Set<String> _favoriteWorkspaceIds = {};
  List<String> _recentWorkspaceIds = [];
  var _workspaceSort = WorkspaceSort.recentlyUpdated;

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
  }

  @override
  void didUpdateWidget(covariant HomeLibrarySection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.view != widget.view) {
      unawaited(_reload());
    }
  }

  Future<void> _reload() async {
    final favorites = await _favoritesStore.load();
    final recent = await _recentStore.loadOrderedIds();
    final prefs = await _displayPrefsStore.load();
    if (!mounted) return;
    setState(() {
      _favoriteWorkspaceIds = favorites;
      _recentWorkspaceIds = recent;
      _workspaceSort = prefs.sort;
    });
  }

  Future<void> _toggleWorkspaceFavorite(String workspaceId) async {
    await _favoritesStore.toggle(workspaceId);
    if (!mounted) return;
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = AppTextStyles.of(context);
    final l10n = context.l10n;
    final isFavorites = widget.view == HomeLibraryView.favorites;

    final title = isFavorites
        ? l10n.homeWorkspaceMyFavorites
        : l10n.homeWorkspaceRecentVisits;

    final allWorkspaces = context.select<ChatCubit, List<Workspace>>(
      (c) => c.state.workspaces,
    );
    final sessions = context.select<ChatCubit, List<AppSession>>(
      (c) => c.state.sessions,
    );

    final workspaces = isFavorites
        ? [
            for (final p in allWorkspaces)
              if (_favoriteWorkspaceIds.contains(p.workspaceId)) p,
          ]
        : [
            for (final id in _recentWorkspaceIds)
              if (_findWorkspace(allWorkspaces, id) case final p?) p,
          ];

    return ColoredBox(
      color: cs.workspaceCard,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: styles.prominent.copyWith(
              color: cs.onSurface,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: workspaces.isEmpty
                ? _LibraryEmptyState(
                    icon: isFavorites
                        ? Icons.star_outline_rounded
                        : Icons.history_rounded,
                    label: l10n.homeWorkspaceNoData,
                  )
                : WorkspaceCollection(
                    workspaces: workspaces,
                    sessions: sessions,
                    gridView: true,
                    workspaceSort: _workspaceSort,
                    favoriteWorkspaceIds: _favoriteWorkspaceIds,
                    onToggleWorkspaceFavorite: _toggleWorkspaceFavorite,
                    preserveOrder: !isFavorites,
                  ),
          ),
        ],
      ),
    );
  }

  static Workspace? _findWorkspace(List<Workspace> workspaces, String id) {
    for (final p in workspaces) {
      if (p.workspaceId == id) return p;
    }
    return null;
  }
}

class _LibraryEmptyState extends StatelessWidget {
  const _LibraryEmptyState({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = AppTextStyles.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 40,
            color: cs.onSurfaceVariant.withValues(alpha: 0.55),
          ),
          const SizedBox(height: 12),
          Text(
            label,
            style: styles.body.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
