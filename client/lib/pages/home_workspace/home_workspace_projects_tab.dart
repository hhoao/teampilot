import 'dart:async';

import 'package:flutter/material.dart';
import 'package:teampilot/theme/app_icon_sizes.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../cubits/chat_cubit.dart';
import '../../cubits/identity_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/app_project.dart';
import '../../models/app_session.dart';
import '../../models/launch_identity.dart';
import '../../models/personal_identity.dart';
import '../../models/team_config.dart';
import '../../models/identity_kind.dart';
import '../../models/identity.dart';
import '../../repositories/session_repository.dart';
import '../../services/home_workspace/home_workspace_project_launch_prefs_store.dart';
import '../../theme/app_text_styles.dart';
import '../../utils/launch_identity_resolver.dart';
import '../../utils/home_workspace_project_display.dart';
import '../../utils/project_display_name.dart';
import '../../widgets/menu/sidebar_action_menu.dart';
import 'home_workspace_launch_project_dialog.dart';
import 'home_workspace_new_project_dialog.dart';
import 'home_workspace_project_card.dart';
import 'home_workspace_project_list_tile.dart';
import 'home_workspace_project_sort.dart';
import 'launch_project_team_order.dart';

/// Route for [project] under [identity].
String projectLaunchRoute(String projectId, LaunchIdentity identity) =>
    '/home-v2/project/$projectId?as=${identity.encode()}';

/// When a remembered, well-formed choice exists for [project], the route to
/// open it directly (skipping the dialog); otherwise null (show the dialog).
String? rememberedLaunchRoute(AppProject project, ProjectLaunchPref? pref) {
  if (pref == null || !pref.remember) return null;
  final id = LaunchIdentity.decode(pref.lastIdentity);
  if (id == null) return null;
  return projectLaunchRoute(project.projectId, id);
}

Future<void> openHomeWorkspaceProject(
  BuildContext context,
  AppProject project, {
  required List<AppSession> sessions,
}) async {
  final store = HomeWorkspaceProjectLaunchPrefsStore();
  final pref = await store.prefsFor(project.projectId);
  if (!context.mounted) return;

  final remembered = rememberedLaunchRoute(project, pref);
  if (remembered != null) {
    context.go(remembered);
    return;
  }

  final identityCubit = context.read<IdentityCubit>();
  final identities = identityCubit.state.identities;
  final personals = identities.whereType<PersonalIdentity>().toList();
  final teams = identities.whereType<TeamIdentity>().toList();
  final orderedTeamIds = orderTeamIdsByRecentUse(
    projectId: project.projectId,
    teamIds: teams.map((t) => t.id).toList(),
    sessions: sessions,
  );
  final teamById = {for (final t in teams) t.id: t};
  final options = <LaunchProjectIdentityOption>[
    for (final personal in personals)
      LaunchProjectIdentityOption(
        id: personal.id,
        name: personal.display,
        isTeam: false,
      ),
    for (final id in orderedTeamIds)
      if (teamById[id] != null)
        LaunchProjectIdentityOption(
          id: id,
          name: teamById[id]!.name,
          isTeam: true,
        ),
  ];
  final choice = await showHomeWorkspaceLaunchProjectDialog(
    context,
    projectName: project.effectiveDisplay,
    identities: options,
    preselected: pref != null
        ? LaunchIdentity.decode(pref.lastIdentity)
        : resolveProjectLaunchIdentity(
            project,
            identityCubit.byId,
          ),
  );
  if (choice == null || !context.mounted) return;
  if (choice.remember) {
    await context.read<ChatCubit>().updateProjectMetadata(
      context.read<SessionRepository>(),
      project.projectId,
      defaultIdentityId: choice.identity.identityId,
    );
  }
  await store.save(
    project.projectId,
    ProjectLaunchPref(
      lastIdentity: choice.identity.encode(),
      remember: choice.remember,
    ),
  );
  if (!context.mounted) return;
  context.go(projectLaunchRoute(project.projectId, choice.identity));
}

class HomeWorkspaceProjectsTab extends StatelessWidget {
  const HomeWorkspaceProjectsTab({super.key, 
    required this.projects,
    required this.sessions,
    required this.gridView,
    required this.onToggleView,
    required this.projectSort,
    required this.onProjectSortChanged,
    required this.favoriteProjectIds,
    required this.onToggleProjectFavorite,
  });

  final List<AppProject> projects;
  final List<AppSession> sessions;
  final bool gridView;
  final ValueChanged<bool> onToggleView;
  final HomeWorkspaceProjectSort projectSort;
  final ValueChanged<HomeWorkspaceProjectSort> onProjectSortChanged;
  final Set<String> favoriteProjectIds;
  final Future<void> Function(String projectId) onToggleProjectFavorite;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HomeWorkspaceProjectsToolbar(
          gridView: gridView,
          onToggleView: onToggleView,
          projectSort: projectSort,
          onProjectSortChanged: onProjectSortChanged,
        ),
        const SizedBox(height: 16),
        Expanded(
          child: projects.isEmpty
              ? const HomeWorkspaceEmptyProjects()
              : HomeWorkspaceProjectCollection(
                  projects: projects,
                  sessions: sessions,
                  gridView: gridView,
                  projectSort: projectSort,
                  favoriteProjectIds: favoriteProjectIds,
                  onToggleProjectFavorite: onToggleProjectFavorite,
                ),
        ),
      ],
    );
  }
}

class HomeWorkspaceProjectsToolbar extends StatelessWidget {
  const HomeWorkspaceProjectsToolbar({super.key, 
    required this.gridView,
    required this.onToggleView,
    required this.projectSort,
    required this.onProjectSortChanged,
  });

  final bool gridView;
  final ValueChanged<bool> onToggleView;
  final HomeWorkspaceProjectSort projectSort;
  final ValueChanged<HomeWorkspaceProjectSort> onProjectSortChanged;

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
        HomeWorkspaceProjectsSortButton(
          projectSort: projectSort,
          onProjectSortChanged: onProjectSortChanged,
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
                  const SizedBox(width: 10),
                  HomeWorkspaceProjectsPrimaryAction(
                    icon: Icons.add_rounded,
                    label: l10n.newProject,
                    onTap: () => showHomeWorkspaceNewProjectDialog(
                      context,
                      chatCubit: context.read<ChatCubit>(),
                      repository: context.read<SessionRepository>(),
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
}

class HomeWorkspaceProjectsSortButton extends StatelessWidget {
  const HomeWorkspaceProjectsSortButton({super.key, 
    required this.projectSort,
    required this.onProjectSortChanged,
  });

  final HomeWorkspaceProjectSort projectSort;
  final ValueChanged<HomeWorkspaceProjectSort> onProjectSortChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return SidebarActionMenuIconAnchor(
      minWidth: 220,
      triggerBuilder: (context, controller) {
        return HomeWorkspaceProjectsIconChip(
          icon: Icons.sort_rounded,
          tooltip: l10n.homeWorkspaceProjectSort,
          onTap: () {
            if (controller.isOpen) {
              controller.close();
            } else {
              controller.open();
            }
          },
        );
      },
      buildMenuChildren: (context, controller) {
        return [
          for (final sort in HomeWorkspaceProjectSort.values)
            SidebarActionMenuItem(
              icon: _iconForSort(sort),
              label: sort.label(l10n),
              trailing: projectSort == sort
                  ? Icon(
                      Icons.check,
                      size: context.appIconSizes.md,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.7),
                    )
                  : null,
              menuController: controller,
              onTap: () => onProjectSortChanged(sort),
            ),
        ];
      },
    );
  }

  static IconData _iconForSort(HomeWorkspaceProjectSort sort) =>
      switch (sort) {
        HomeWorkspaceProjectSort.recentlyUpdated => Icons.update_rounded,
        HomeWorkspaceProjectSort.nameAsc => Icons.sort_by_alpha_rounded,
        HomeWorkspaceProjectSort.nameDesc => Icons.sort_by_alpha_rounded,
        HomeWorkspaceProjectSort.createdDesc => Icons.event_rounded,
        HomeWorkspaceProjectSort.sessionCountDesc =>
          Icons.forum_outlined,
      };
}

class HomeWorkspaceProjectsViewToggle extends StatelessWidget {
  const HomeWorkspaceProjectsViewToggle({super.key, 
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
  const HomeWorkspaceProjectsToggleCell({super.key, 
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
          size: context.appIconSizes.md,
          color: active ? cs.primary : cs.onSurfaceVariant,
        ),
      ),
    );
  }
}

class HomeWorkspaceProjectsIconChip extends StatelessWidget {
  const HomeWorkspaceProjectsIconChip({super.key, 
    required this.icon,
    required this.onTap,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final chip = InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(7),
        decoration: BoxDecoration(
          color: cs.surfaceContainer,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.7)),
        ),
        child: Icon(icon, size: context.appIconSizes.md, color: cs.onSurfaceVariant),
      ),
    );
    if (tooltip == null || tooltip!.isEmpty) return chip;
    return Tooltip(message: tooltip, child: chip);
  }
}

class HomeWorkspaceProjectsPrimaryAction extends StatelessWidget {
  const HomeWorkspaceProjectsPrimaryAction({super.key, 
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
            Icon(icon, size: context.appIconSizes.md, color: cs.onPrimary),
            const SizedBox(width: 7),
            Text(label, style: styles.body.copyWith(color: cs.onPrimary)),
          ],
        ),
      ),
    );
  }
}

class HomeWorkspaceProjectCollection extends StatefulWidget {
  const HomeWorkspaceProjectCollection({super.key, 
    required this.projects,
    required this.sessions,
    required this.gridView,
    required this.projectSort,
    required this.favoriteProjectIds,
    required this.onToggleProjectFavorite,
    this.preserveOrder = false,
  });

  final List<AppProject> projects;
  final List<AppSession> sessions;
  final bool gridView;
  final HomeWorkspaceProjectSort projectSort;
  final Set<String> favoriteProjectIds;
  final Future<void> Function(String projectId) onToggleProjectFavorite;
  final bool preserveOrder;

  @override
  State<HomeWorkspaceProjectCollection> createState() =>
      _HomeWorkspaceProjectCollectionState();
}

class _HomeWorkspaceProjectCollectionState
    extends State<HomeWorkspaceProjectCollection> {
  HomeWorkspaceProjectDisplay? _cached;
  List<AppProject>? _lastProjects;
  List<AppSession>? _lastSessions;
  HomeWorkspaceProjectSort? _lastSort;
  Set<String>? _lastFavorites;
  bool? _lastPreserveOrder;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    // Cache fields updated in build; inputs are widget props only.
    final display = computeHomeWorkspaceProjectDisplay(
      projects: widget.projects,
      sessions: widget.sessions,
      sort: widget.projectSort,
      favoriteProjectIds: widget.favoriteProjectIds,
      displayName: (project) => project.localizedName(l10n),
      preserveOrder: widget.preserveOrder,
      cached: _cached,
      lastProjects: _lastProjects,
      lastSessions: _lastSessions,
      lastSort: _lastSort,
      lastFavorites: _lastFavorites,
      lastPreserveOrder: _lastPreserveOrder,
    );
    _cached = display;
    _lastProjects = widget.projects;
    _lastSessions = widget.sessions;
    _lastSort = widget.projectSort;
    _lastFavorites = widget.favoriteProjectIds;
    _lastPreserveOrder = widget.preserveOrder;

    if (widget.gridView) {
      return HomeWorkspaceProjectGrid(
        projects: display.sortedProjects,
        sessionCounts: display.sessionCounts,
        favoriteProjectIds: widget.favoriteProjectIds,
        onToggleProjectFavorite: widget.onToggleProjectFavorite,
        sessions: widget.sessions,
      );
    }

    return HomeWorkspaceProjectList(
      projects: display.sortedProjects,
      sessionCounts: display.sessionCounts,
      favoriteProjectIds: widget.favoriteProjectIds,
      onToggleProjectFavorite: widget.onToggleProjectFavorite,
      sessions: widget.sessions,
    );
  }
}

class HomeWorkspaceProjectGrid extends StatelessWidget {
  const HomeWorkspaceProjectGrid({super.key, 
    required this.projects,
    required this.sessionCounts,
    required this.favoriteProjectIds,
    required this.onToggleProjectFavorite,
    required this.sessions,
  });

  final List<AppProject> projects;
  final Map<String, int> sessionCounts;
  final Set<String> favoriteProjectIds;
  final Future<void> Function(String projectId) onToggleProjectFavorite;
  final List<AppSession> sessions;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 460,
        mainAxisExtent: 244,
        crossAxisSpacing: 20,
        mainAxisSpacing: 20,
      ),
      itemCount: projects.length,
      itemBuilder: (context, index) {
        final project = projects[index];
        final count = sessionCounts[project.projectId] ?? 0;
        return HomeWorkspaceProjectCard(
          key: ValueKey('project-card-${project.projectId}'),
          project: project,
          sessionCount: count,
          favorited: favoriteProjectIds.contains(project.projectId),
          onToggleFavorite: () => onToggleProjectFavorite(project.projectId),
          onTap: () => unawaited(
            openHomeWorkspaceProject(
              context,
              project,
              sessions: sessions,
            ),
          ),
        );
      },
    );
  }
}

class HomeWorkspaceProjectList extends StatelessWidget {
  const HomeWorkspaceProjectList({super.key, 
    required this.projects,
    required this.sessionCounts,
    required this.favoriteProjectIds,
    required this.onToggleProjectFavorite,
    required this.sessions,
  });

  final List<AppProject> projects;
  final Map<String, int> sessionCounts;
  final Set<String> favoriteProjectIds;
  final Future<void> Function(String projectId) onToggleProjectFavorite;
  final List<AppSession> sessions;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      itemCount: projects.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final project = projects[index];
        final count = sessionCounts[project.projectId] ?? 0;
        return HomeWorkspaceProjectListTile(
          key: ValueKey('project-list-tile-${project.projectId}'),
          project: project,
          sessionCount: count,
          favorited: favoriteProjectIds.contains(project.projectId),
          onToggleFavorite: () => onToggleProjectFavorite(project.projectId),
          onTap: () => unawaited(
            openHomeWorkspaceProject(
              context,
              project,
              sessions: sessions,
            ),
          ),
        );
      },
    );
  }
}

class HomeWorkspaceEmptyProjects extends StatelessWidget {
  const HomeWorkspaceEmptyProjects({super.key});

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
            size: context.appIconSizes.md,
            color: cs.onSurfaceVariant.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 14),
          Text(
            l10n.homeWorkspaceEmptyProjects,
            style: styles.body.copyWith(color: cs.onSurfaceVariant),
          ),
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
