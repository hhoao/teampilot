import 'dart:async';

import 'package:flutter/material.dart';
import 'package:teampilot/theme/app_icon_sizes.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../cubits/chat_cubit.dart';
import '../../cubits/launch_profile_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/workspace.dart';
import '../../models/app_session.dart';
import '../../models/launch_profile_ref.dart';
import '../../models/personal_profile.dart';
import '../../models/team_config.dart';
import '../../models/launch_profile_kind.dart';
import '../../models/launch_profile.dart';
import '../../repositories/session_repository.dart';
import '../../services/home_workspace/workspace_launch_prefs_store.dart';
import '../../theme/app_text_styles.dart';
import '../../utils/launch_profile_resolver.dart';
import '../../utils/launch_profile_display_name.dart';
import '../../utils/home_workspace_display.dart';
import '../../utils/workspace_display_name.dart';
import '../../widgets/menu/sidebar_action_menu.dart';
import 'home_launch_workspace_dialog.dart';
import 'home_new_workspace_dialog.dart';
import 'workspace_card.dart';
import 'workspace_list_tile.dart';
import 'workspace_sort.dart';
import 'launch_workspace_team_order.dart';

/// Route for [workspace] under [identity].
String workspaceLaunchRoute(String workspaceId, LaunchProfileRef identity) =>
    '/home-v2/workspace/$workspaceId?as=${identity.encode()}';

/// When a remembered, well-formed choice exists for [workspace], the route to
/// open it directly (skipping the dialog); otherwise null (show the dialog).
String? rememberedLaunchRoute(Workspace workspace, WorkspaceLaunchPref? pref) {
  if (pref == null || !pref.remember) return null;
  final id = LaunchProfileRef.decode(pref.lastIdentity);
  if (id == null) return null;
  return workspaceLaunchRoute(workspace.workspaceId, id);
}

Future<void> openWorkspace(
  BuildContext context,
  Workspace workspace, {
  required List<AppSession> sessions,
}) async {
  final store = WorkspaceLaunchPrefsStore();
  final pref = await store.prefsFor(workspace.workspaceId);
  if (!context.mounted) return;

  final l10n = context.l10n;
  final remembered = rememberedLaunchRoute(workspace, pref);
  if (remembered != null) {
    context.go(remembered);
    return;
  }

  final identityCubit = context.read<LaunchProfileCubit>();
  final identities = identityCubit.state.identities;
  final personals = identities.whereType<PersonalProfile>().toList();
  final teams = identities.whereType<TeamProfile>().toList();
  final orderedTeamIds = orderTeamIdsByRecentUse(
    workspaceId: workspace.workspaceId,
    teamIds: teams.map((t) => t.id).toList(),
    sessions: sessions,
  );
  final teamById = {for (final t in teams) t.id: t};
  final options = <LaunchWorkspaceIdentityOption>[
    for (final personal in personals)
      LaunchWorkspaceIdentityOption(
        id: personal.id,
        name: launchProfileDisplayName(l10n, personal),
        isTeam: false,
      ),
    for (final id in orderedTeamIds)
      if (teamById[id] != null)
        LaunchWorkspaceIdentityOption(
          id: id,
          name: launchProfileDisplayName(l10n, teamById[id]!),
          isTeam: true,
        ),
  ];
  final choice = await showHomeLaunchWorkspaceDialog(
    context,
    workspaceName: workspace.effectiveDisplay,
    identities: options,
    preselected: pref != null
        ? LaunchProfileRef.decode(pref.lastIdentity)
        : resolveWorkspaceLaunchProfileRef(
            workspace,
            identityCubit.byId,
          ),
  );
  if (choice == null || !context.mounted) return;
  if (choice.remember) {
    await context.read<ChatCubit>().updateWorkspaceMetadata(
      context.read<SessionRepository>(),
      workspace.workspaceId,
      defaultProfileId: choice.identity.profileId,
    );
  }
  await store.save(
    workspace.workspaceId,
    WorkspaceLaunchPref(
      lastIdentity: choice.identity.encode(),
      remember: choice.remember,
    ),
  );
  if (!context.mounted) return;
  context.go(workspaceLaunchRoute(workspace.workspaceId, choice.identity));
}

class WorkspacesTab extends StatelessWidget {
  const WorkspacesTab({super.key, 
    required this.workspaces,
    required this.sessions,
    required this.gridView,
    required this.onToggleView,
    required this.workspaceSort,
    required this.onWorkspaceSortChanged,
    required this.favoriteWorkspaceIds,
    required this.onToggleWorkspaceFavorite,
  });

  final List<Workspace> workspaces;
  final List<AppSession> sessions;
  final bool gridView;
  final ValueChanged<bool> onToggleView;
  final WorkspaceSort workspaceSort;
  final ValueChanged<WorkspaceSort> onWorkspaceSortChanged;
  final Set<String> favoriteWorkspaceIds;
  final Future<void> Function(String workspaceId) onToggleWorkspaceFavorite;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        WorkspacesToolbar(
          gridView: gridView,
          onToggleView: onToggleView,
          workspaceSort: workspaceSort,
          onWorkspaceSortChanged: onWorkspaceSortChanged,
        ),
        const SizedBox(height: 16),
        Expanded(
          child: workspaces.isEmpty
              ? const HomeEmptyWorkspaces()
              : WorkspaceCollection(
                  workspaces: workspaces,
                  sessions: sessions,
                  gridView: gridView,
                  workspaceSort: workspaceSort,
                  favoriteWorkspaceIds: favoriteWorkspaceIds,
                  onToggleWorkspaceFavorite: onToggleWorkspaceFavorite,
                ),
        ),
      ],
    );
  }
}

class WorkspacesToolbar extends StatelessWidget {
  const WorkspacesToolbar({super.key, 
    required this.gridView,
    required this.onToggleView,
    required this.workspaceSort,
    required this.onWorkspaceSortChanged,
  });

  final bool gridView;
  final ValueChanged<bool> onToggleView;
  final WorkspaceSort workspaceSort;
  final ValueChanged<WorkspaceSort> onWorkspaceSortChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Row(
      children: [
        WorkspacesViewToggle(
          gridView: gridView,
          onToggleView: onToggleView,
        ),
        const SizedBox(width: 8),
        WorkspacesSortButton(
          workspaceSort: workspaceSort,
          onWorkspaceSortChanged: onWorkspaceSortChanged,
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
                  WorkspacesPrimaryAction(
                    icon: Icons.add_rounded,
                    label: l10n.newWorkspace,
                    onTap: () => showHomeNewWorkspaceDialog(
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

class WorkspacesSortButton extends StatelessWidget {
  const WorkspacesSortButton({super.key, 
    required this.workspaceSort,
    required this.onWorkspaceSortChanged,
  });

  final WorkspaceSort workspaceSort;
  final ValueChanged<WorkspaceSort> onWorkspaceSortChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return SidebarActionMenuIconAnchor(
      minWidth: 220,
      triggerBuilder: (context, controller) {
        return WorkspacesIconChip(
          icon: Icons.sort_rounded,
          tooltip: l10n.homeWorkspaceWorkspaceSort,
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
          for (final sort in WorkspaceSort.values)
            SidebarActionMenuItem(
              icon: _iconForSort(sort),
              label: sort.label(l10n),
              trailing: workspaceSort == sort
                  ? Icon(
                      Icons.check,
                      size: context.appIconSizes.md,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.7),
                    )
                  : null,
              menuController: controller,
              onTap: () => onWorkspaceSortChanged(sort),
            ),
        ];
      },
    );
  }

  static IconData _iconForSort(WorkspaceSort sort) =>
      switch (sort) {
        WorkspaceSort.recentlyUpdated => Icons.update_rounded,
        WorkspaceSort.nameAsc => Icons.sort_by_alpha_rounded,
        WorkspaceSort.nameDesc => Icons.sort_by_alpha_rounded,
        WorkspaceSort.createdDesc => Icons.event_rounded,
        WorkspaceSort.sessionCountDesc =>
          Icons.forum_outlined,
      };
}

class WorkspacesViewToggle extends StatelessWidget {
  const WorkspacesViewToggle({super.key, 
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
          WorkspacesToggleCell(
            icon: Icons.grid_view_rounded,
            active: gridView,
            onTap: () => onToggleView(true),
          ),
          WorkspacesToggleCell(
            icon: Icons.format_list_bulleted_rounded,
            active: !gridView,
            onTap: () => onToggleView(false),
          ),
        ],
      ),
    );
  }
}

class WorkspacesToggleCell extends StatelessWidget {
  const WorkspacesToggleCell({super.key, 
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

class WorkspacesIconChip extends StatelessWidget {
  const WorkspacesIconChip({super.key, 
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

class WorkspacesPrimaryAction extends StatelessWidget {
  const WorkspacesPrimaryAction({super.key, 
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

class WorkspaceCollection extends StatefulWidget {
  const WorkspaceCollection({super.key, 
    required this.workspaces,
    required this.sessions,
    required this.gridView,
    required this.workspaceSort,
    required this.favoriteWorkspaceIds,
    required this.onToggleWorkspaceFavorite,
    this.preserveOrder = false,
  });

  final List<Workspace> workspaces;
  final List<AppSession> sessions;
  final bool gridView;
  final WorkspaceSort workspaceSort;
  final Set<String> favoriteWorkspaceIds;
  final Future<void> Function(String workspaceId) onToggleWorkspaceFavorite;
  final bool preserveOrder;

  @override
  State<WorkspaceCollection> createState() =>
      _WorkspaceCollectionState();
}

class _WorkspaceCollectionState
    extends State<WorkspaceCollection> {
  WorkspaceDisplay? _cached;
  List<Workspace>? _lastWorkspaces;
  List<AppSession>? _lastSessions;
  WorkspaceSort? _lastSort;
  Set<String>? _lastFavorites;
  bool? _lastPreserveOrder;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    // Cache fields updated in build; inputs are widget props only.
    final display = computeWorkspaceDisplay(
      workspaces: widget.workspaces,
      sessions: widget.sessions,
      sort: widget.workspaceSort,
      favoriteWorkspaceIds: widget.favoriteWorkspaceIds,
      displayName: (workspace) => workspace.localizedName(l10n),
      preserveOrder: widget.preserveOrder,
      cached: _cached,
      lastWorkspaces: _lastWorkspaces,
      lastSessions: _lastSessions,
      lastSort: _lastSort,
      lastFavorites: _lastFavorites,
      lastPreserveOrder: _lastPreserveOrder,
    );
    _cached = display;
    _lastWorkspaces = widget.workspaces;
    _lastSessions = widget.sessions;
    _lastSort = widget.workspaceSort;
    _lastFavorites = widget.favoriteWorkspaceIds;
    _lastPreserveOrder = widget.preserveOrder;

    if (widget.gridView) {
      return WorkspaceGrid(
        workspaces: display.sortedWorkspaces,
        sessionCounts: display.sessionCounts,
        favoriteWorkspaceIds: widget.favoriteWorkspaceIds,
        onToggleWorkspaceFavorite: widget.onToggleWorkspaceFavorite,
        sessions: widget.sessions,
      );
    }

    return WorkspaceList(
      workspaces: display.sortedWorkspaces,
      sessionCounts: display.sessionCounts,
      favoriteWorkspaceIds: widget.favoriteWorkspaceIds,
      onToggleWorkspaceFavorite: widget.onToggleWorkspaceFavorite,
      sessions: widget.sessions,
    );
  }
}

class WorkspaceGrid extends StatelessWidget {
  const WorkspaceGrid({super.key, 
    required this.workspaces,
    required this.sessionCounts,
    required this.favoriteWorkspaceIds,
    required this.onToggleWorkspaceFavorite,
    required this.sessions,
  });

  final List<Workspace> workspaces;
  final Map<String, int> sessionCounts;
  final Set<String> favoriteWorkspaceIds;
  final Future<void> Function(String workspaceId) onToggleWorkspaceFavorite;
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
      itemCount: workspaces.length,
      itemBuilder: (context, index) {
        final workspace = workspaces[index];
        final count = sessionCounts[workspace.workspaceId] ?? 0;
        return WorkspaceCard(
          key: ValueKey('workspace-card-${workspace.workspaceId}'),
          workspace: workspace,
          sessionCount: count,
          favorited: favoriteWorkspaceIds.contains(workspace.workspaceId),
          onToggleFavorite: () => onToggleWorkspaceFavorite(workspace.workspaceId),
          onTap: () => unawaited(
            openWorkspace(
              context,
              workspace,
              sessions: sessions,
            ),
          ),
        );
      },
    );
  }
}

class WorkspaceList extends StatelessWidget {
  const WorkspaceList({super.key, 
    required this.workspaces,
    required this.sessionCounts,
    required this.favoriteWorkspaceIds,
    required this.onToggleWorkspaceFavorite,
    required this.sessions,
  });

  final List<Workspace> workspaces;
  final Map<String, int> sessionCounts;
  final Set<String> favoriteWorkspaceIds;
  final Future<void> Function(String workspaceId) onToggleWorkspaceFavorite;
  final List<AppSession> sessions;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      itemCount: workspaces.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final workspace = workspaces[index];
        final count = sessionCounts[workspace.workspaceId] ?? 0;
        return WorkspaceListTile(
          key: ValueKey('workspace-list-tile-${workspace.workspaceId}'),
          workspace: workspace,
          sessionCount: count,
          favorited: favoriteWorkspaceIds.contains(workspace.workspaceId),
          onToggleFavorite: () => onToggleWorkspaceFavorite(workspace.workspaceId),
          onTap: () => unawaited(
            openWorkspace(
              context,
              workspace,
              sessions: sessions,
            ),
          ),
        );
      },
    );
  }
}

class HomeEmptyWorkspaces extends StatelessWidget {
  const HomeEmptyWorkspaces({super.key});

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
            l10n.homeWorkspaceEmptyWorkspaces,
            style: styles.body.copyWith(color: cs.onSurfaceVariant),
          ),
          Text(
            l10n.homeWorkspaceEmptyWorkspacesHint,
            style: styles.bodySmall.copyWith(
              color: cs.onSurfaceVariant.withValues(alpha: 0.75),
            ),
          ),
        ],
      ),
    );
  }
}
