import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../cubits/chat_cubit.dart';
import '../../cubits/launch_profile_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/app_session.dart';
import '../../models/launch_profile.dart';
import '../../models/launch_profile_ref.dart';
import '../../models/workspace.dart';
import '../../models/workspace_tab_ref.dart';
import '../../services/home_workspace/home_recent_workspaces_store.dart';
import '../../services/home_workspace/workspace_display_prefs_store.dart';
import '../../services/home_workspace/workspace_favorites_store.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/workspace_surface_layers.dart';
import 'home_workspace_library_view.dart';
import 'open_workspace_tab_actions.dart';
import 'workspace_card.dart';
import 'workspace_sort.dart';
import 'workspaces_tab.dart';

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
  List<WorkspaceTabRef> _recentTabs = const [];
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
    final recent = await _recentStore.loadOrderedTabs();
    final prefs = await _displayPrefsStore.load();
    if (!mounted) return;
    setState(() {
      _favoriteWorkspaceIds = favorites;
      _recentTabs = recent;
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
    final identities = context.select<LaunchProfileCubit, List<LaunchProfile>>(
      (c) => c.state.identities,
    );

    final workspaces = isFavorites
        ? [
            for (final p in allWorkspaces)
              if (_favoriteWorkspaceIds.contains(p.workspaceId)) p,
          ]
        : const <Workspace>[];

    final recentEntries = isFavorites
        ? const <({Workspace workspace, WorkspaceTabRef tab})>[]
        : [
            for (final tab in _recentTabs)
              if (_findWorkspace(allWorkspaces, tab.workspaceId)
                  case final workspace?)
                (workspace: workspace, tab: tab),
          ];

    final isEmpty = isFavorites ? workspaces.isEmpty : recentEntries.isEmpty;

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
            child: isEmpty
                ? _LibraryEmptyState(
                    icon: isFavorites
                        ? Icons.star_outline_rounded
                        : Icons.history_rounded,
                    label: l10n.homeWorkspaceNoData,
                  )
                : isFavorites
                    ? WorkspaceCollection(
                        workspaces: workspaces,
                        sessions: sessions,
                        gridView: true,
                        workspaceSort: _workspaceSort,
                        favoriteWorkspaceIds: _favoriteWorkspaceIds,
                        onToggleWorkspaceFavorite: _toggleWorkspaceFavorite,
                        preserveOrder: false,
                      )
                    : _RecentWorkspaceGrid(
                        entries: recentEntries,
                        sessions: sessions,
                        identities: identities,
                        favoriteWorkspaceIds: _favoriteWorkspaceIds,
                        onToggleWorkspaceFavorite: _toggleWorkspaceFavorite,
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

class _RecentWorkspaceGrid extends StatelessWidget {
  const _RecentWorkspaceGrid({
    required this.entries,
    required this.sessions,
    required this.identities,
    required this.favoriteWorkspaceIds,
    required this.onToggleWorkspaceFavorite,
  });

  final List<({Workspace workspace, WorkspaceTabRef tab})> entries;
  final List<AppSession> sessions;
  final List<LaunchProfile> identities;
  final Set<String> favoriteWorkspaceIds;
  final Future<void> Function(String workspaceId) onToggleWorkspaceFavorite;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final sessionCounts = <String, int>{};
    for (final s in sessions) {
      final id = s.workspaceId;
      if (id.isEmpty) continue;
      sessionCounts[id] = (sessionCounts[id] ?? 0) + 1;
    }

    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 460,
        mainAxisExtent: 244,
        crossAxisSpacing: 20,
        mainAxisSpacing: 20,
      ),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        final workspace = entry.workspace;
        final tab = entry.tab;
        return WorkspaceCard(
          key: ValueKey('recent-${tab.tabKey}'),
          workspace: workspace,
          sessionCount: sessionCounts[workspace.workspaceId] ?? 0,
          favorited: favoriteWorkspaceIds.contains(workspace.workspaceId),
          onToggleFavorite: () => onToggleWorkspaceFavorite(workspace.workspaceId),
          displayNameOverride: workspaceTabDisplayLabel(
            l10n: l10n,
            workspace: workspace,
            identity: tab.identity,
            identities: identities,
            alwaysShowIdentity: true,
          ),
          tabIdentity: tab.identity,
          onTap: () => context.go(tab.route),
          sessions: sessions,
        );
      },
    );
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
