import 'package:flutter/material.dart';
import 'package:teampilot/theme/app_icon_sizes.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../cubits/chat_cubit.dart';
import '../../cubits/team_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/app_project.dart';
import '../../models/app_session.dart';
import '../../repositories/session_repository.dart';
import '../../theme/app_text_styles.dart';
import 'home_workspace_new_project_dialog.dart';
import 'home_workspace_project_card.dart';

class HomeWorkspaceProjectsTab extends StatelessWidget {
  const HomeWorkspaceProjectsTab({
    required this.projects,
    required this.sessions,
    required this.gridView,
    required this.onToggleView,
    required this.favoriteProjectIds,
    required this.onToggleProjectFavorite,
    this.personalScope = false,
  });

  final List<AppProject> projects;
  final List<AppSession> sessions;
  final bool gridView;
  final ValueChanged<bool> onToggleView;
  final Set<String> favoriteProjectIds;
  final Future<void> Function(String projectId) onToggleProjectFavorite;
  final bool personalScope;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HomeWorkspaceProjectsToolbar(
          gridView: gridView,
          onToggleView: onToggleView,
          personalScope: personalScope,
        ),
        const SizedBox(height: 16),
        Expanded(
          child: projects.isEmpty
              ? const HomeWorkspaceEmptyProjects()
              : HomeWorkspaceProjectGrid(
                  projects: projects,
                  sessions: sessions,
                  favoriteProjectIds: favoriteProjectIds,
                  onToggleProjectFavorite: onToggleProjectFavorite,
                ),
        ),
      ],
    );
  }
}

class HomeWorkspaceProjectsToolbar extends StatelessWidget {
  const HomeWorkspaceProjectsToolbar({
    required this.gridView,
    required this.onToggleView,
    this.personalScope = false,
  });

  final bool gridView;
  final ValueChanged<bool> onToggleView;
  final bool personalScope;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Row(
      children: [
        HomeWorkspaceProjectsViewToggle(
          gridView: gridView,
          onToggleView: onToggleView,
        ),
        const SizedBox(width: 8),
        HomeWorkspaceProjectsIconChip(
          icon: Icons.sort_rounded,
          onTap: () => _comingSoon(context),
        ),
        const Spacer(),
        Flexible(
          child: Align(
            alignment: Alignment.centerRight,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              reverse: true,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  HomeWorkspaceProjectsOutlinedAction(
                    icon: Icons.file_download_outlined,
                    label: l10n.homeWorkspaceImportProject,
                    onTap: () => _comingSoon(context),
                  ),
                  const SizedBox(width: 10),
                  HomeWorkspaceProjectsPrimaryAction(
                    icon: Icons.add_rounded,
                    label: l10n.newProject,
                    onTap: () => showHomeWorkspaceNewProjectDialog(
                      context,
                      chatCubit: context.read<ChatCubit>(),
                      repository: context.read<SessionRepository>(),
                      teamCubit: personalScope
                          ? null
                          : context.read<TeamCubit>(),
                      sessionTeamId: personalScope ? '' : null,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _comingSoon(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.homeWorkspaceComingSoon)),
    );
  }
}

class HomeWorkspaceProjectsViewToggle extends StatelessWidget {
  const HomeWorkspaceProjectsViewToggle({
    required this.gridView,
    required this.onToggleView,
  });

  final bool gridView;
  final ValueChanged<bool> onToggleView;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.7)),
      ),
      padding: const EdgeInsets.all(2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          HomeWorkspaceProjectsToggleCell(
            icon: Icons.grid_view_rounded,
            active: gridView,
            onTap: () => onToggleView(true),
          ),
          HomeWorkspaceProjectsToggleCell(
            icon: Icons.format_list_bulleted_rounded,
            active: !gridView,
            onTap: () => onToggleView(false),
          ),
        ],
      ),
    );
  }
}

class HomeWorkspaceProjectsToggleCell extends StatelessWidget {
  const HomeWorkspaceProjectsToggleCell({
    required this.icon,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: active
              ? cs.primary.withValues(alpha: 0.16)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(
          icon,
          size: AppIconSizes.md,
          color: active ? cs.primary : cs.onSurfaceVariant,
        ),
      ),
    );
  }
}

class HomeWorkspaceProjectsIconChip extends StatelessWidget {
  const HomeWorkspaceProjectsIconChip({
    required this.icon,
    required this.onTap,
  });

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(7),
        decoration: BoxDecoration(
          color: cs.surfaceContainer,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.7)),
        ),
        child: Icon(icon, size: AppIconSizes.md, color: cs.onSurfaceVariant),
      ),
    );
  }
}

class HomeWorkspaceProjectsOutlinedAction extends StatelessWidget {
  const HomeWorkspaceProjectsOutlinedAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = AppTextStyles.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        decoration: BoxDecoration(
          color: cs.surfaceContainer,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.8)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: AppIconSizes.md, color: cs.onSurfaceVariant),
            const SizedBox(width: 7),
            Text(label, style: styles.body.copyWith(color: cs.onSurface)),
          ],
        ),
      ),
    );
  }
}

class HomeWorkspaceProjectsPrimaryAction extends StatelessWidget {
  const HomeWorkspaceProjectsPrimaryAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = AppTextStyles.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        decoration: BoxDecoration(
          color: cs.primary,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: AppIconSizes.md, color: cs.onPrimary),
            const SizedBox(width: 7),
            Text(label, style: styles.body.copyWith(color: cs.onPrimary)),
          ],
        ),
      ),
    );
  }
}

class HomeWorkspaceProjectGrid extends StatelessWidget {
  const HomeWorkspaceProjectGrid({
    required this.projects,
    required this.sessions,
    required this.favoriteProjectIds,
    required this.onToggleProjectFavorite,
  });

  final List<AppProject> projects;
  final List<AppSession> sessions;
  final Set<String> favoriteProjectIds;
  final Future<void> Function(String projectId) onToggleProjectFavorite;

  @override
  Widget build(BuildContext context) {
    final sorted = List<AppProject>.from(projects)
      ..sort((a, b) {
        final af = favoriteProjectIds.contains(a.projectId);
        final bf = favoriteProjectIds.contains(b.projectId);
        if (af != bf) return af ? -1 : 1;
        return b.updatedAt.compareTo(a.updatedAt);
      });

    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 460,
        mainAxisExtent: 244,
        crossAxisSpacing: 20,
        mainAxisSpacing: 20,
      ),
      itemCount: sorted.length,
      itemBuilder: (context, index) {
        final project = sorted[index];
        final count = sessions
            .where((s) => s.projectId == project.projectId)
            .length;
        return HomeWorkspaceProjectCard(
          project: project,
          sessionCount: count,
          favorited: favoriteProjectIds.contains(project.projectId),
          onToggleFavorite: () => onToggleProjectFavorite(project.projectId),
          onTap: () => context.go('/home-v2/project/${project.projectId}'),
        );
      },
    );
  }
}

class HomeWorkspaceEmptyProjects extends StatelessWidget {
  const HomeWorkspaceEmptyProjects();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = AppTextStyles.of(context);
    final l10n = context.l10n;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.folder_open_outlined,
            size: AppIconSizes.md,
            color: cs.onSurfaceVariant.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 14),
          Text(
            l10n.homeWorkspaceEmptyProjects,
            style: styles.body.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.homeWorkspaceEmptyProjectsHint,
            style: styles.bodySmall.copyWith(
              color: cs.onSurfaceVariant.withValues(alpha: 0.75),
            ),
          ),
        ],
      ),
    );
  }
}
