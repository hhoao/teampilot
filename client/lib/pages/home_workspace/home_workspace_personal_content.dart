import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/chat_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/app_project.dart';
import '../../models/app_session.dart';
import '../../services/home_workspace/home_workspace_project_favorites_store.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/workspace_surface_layers.dart';
import 'home_workspace_projects_tab.dart';

/// Right-hand pane for the personal workspace: heading plus a project grid
/// filtered to `teamId == ''`.
class HomeWorkspacePersonalContent extends StatefulWidget {
  const HomeWorkspacePersonalContent({super.key});

  @override
  State<HomeWorkspacePersonalContent> createState() =>
      _HomeWorkspacePersonalContentState();
}

class _HomeWorkspacePersonalContentState
    extends State<HomeWorkspacePersonalContent> {
  final _projectFavoritesStore = HomeWorkspaceProjectFavoritesStore();
  Set<String> _favoriteProjectIds = {};
  var _gridView = true;

  @override
  void initState() {
    super.initState();
    unawaited(_loadProjectFavorites());
  }

  Future<void> _loadProjectFavorites() async {
    final ids = await _projectFavoritesStore.load();
    if (!mounted) return;
    setState(() => _favoriteProjectIds = ids);
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
    final styles = AppTextStyles.of(context);

    final projects = context.select<ChatCubit, List<AppProject>>(
      (c) => c.state.projects.where((p) => p.teamId.isEmpty).toList(),
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
            l10n.homeWorkspacePersonal,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(color: cs.onSurface),
          ),
          const SizedBox(height: 6),
          Text(
            l10n.homeWorkspacePersonalSubtitle,
            style: styles.body.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.5)),
          const SizedBox(height: 16),
          Expanded(
            child: HomeWorkspaceProjectsTab(
              projects: projects,
              sessions: sessions,
              gridView: _gridView,
              onToggleView: (grid) => setState(() => _gridView = grid),
              favoriteProjectIds: _favoriteProjectIds,
              onToggleProjectFavorite: _toggleProjectFavorite,
              personalScope: true,
            )
                .animate(key: const ValueKey('home-personal-projects'))
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
