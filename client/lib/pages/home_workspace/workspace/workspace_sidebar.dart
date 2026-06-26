import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:teampilot/theme/app_icon_sizes.dart';

import '../../../cubits/chat_cubit.dart';
import '../../../cubits/cli_presets_cubit.dart';
import '../../../cubits/launch_profile_cubit.dart';
import '../../../cubits/worktree_cubit.dart';
import '../../../l10n/l10n_extensions.dart';
import '../../../models/workspace.dart';
import '../../../models/app_session.dart';
import '../../../models/cli_preset.dart';
import '../../../models/personal_profile.dart';
import '../../../models/team_config.dart';
import '../../../models/workspace_topology.dart';
import '../../../services/cli/registry/cli_tool_registry_scope.dart';
import '../../../services/git/git_worktree_service.dart';
import '../../../services/storage/app_storage.dart';
import '../../../services/storage/workspace_layout.dart';
import '../../../services/workspace/workspace_tools_scope.dart';
import '../../../utils/session_worktree_grouping.dart';
import '../../../utils/workspace_path_utils.dart';
import '../../../widgets/app_toast/app_toast.dart';
import '../../../theme/app_toast_theme.dart';
import 'mixed_workspace_personal_launch_banner.dart';
import 'worktree_create_dialog.dart';
import 'worktree_group_section.dart';
import '../../../theme/app_text_styles.dart';
import '../../../utils/app_keys.dart';
import '../../../utils/app_session_sort.dart';
import '../../../utils/debounce/debounce.dart';
import '../../../utils/workspace_sidebar_sessions.dart';
import '../../../widgets/app_icon_button.dart';
import '../../../widgets/cli/cli_brand_icon.dart';
import '../../../widgets/menu/sidebar_action_menu.dart';
import 'config/cli_presets_manage_dialog.dart';
import '../../../widgets/dropdown/app_dropdown_decoration.dart';
import '../../../widgets/dropdown/app_dropdown_field.dart';
import '../../../widgets/sidebar_session_tile.dart';
import 'workspace_search_dialog.dart';
import 'workspace_session_actions.dart';

/// Shared resize limits for [WorkspaceSidebar].
class WorkspaceSidebarLayout {
  const WorkspaceSidebarLayout._();

  static const double defaultWidth = 280;
  static const double minWidth = 220;
  static const double maxWidth = 480;
}

/// Workspace conversation sidebar (personal and team workbenches).
class WorkspaceSidebar extends StatefulWidget {
  const WorkspaceSidebar({
    required this.workspace,
    required this.isPersonalWorkspace,
    required this.profileId,
    required this.sessionTeamFilter,
    super.key,
  });

  final Workspace workspace;
  final bool isPersonalWorkspace;

  /// The launch identity the workspace was opened against ([LaunchProfile.id]).
  final String profileId;
  final String sessionTeamFilter;

  @override
  State<WorkspaceSidebar> createState() =>
      _WorkspaceSidebarState();
}

class _WorkspaceSidebarState
    extends State<WorkspaceSidebar> {
  bool get _isPersonal => widget.isPersonalWorkspace;

  AppSessionSort _sessionSort = AppSessionSort.manual;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final sessionSnapshot = context.select<ChatCubit, WorkspaceSidebarSessions>(
      (c) => WorkspaceSidebarSessions.forWorkspace(
        allSessions: c.state.sessions,
        workspace: widget.workspace,
        sessionTeamFilter: widget.sessionTeamFilter,
      ),
    );
    final sortedSessions =
        sortAppSessions(sessionSnapshot.sessions, sort: _sessionSort);
    final wtView = context.select<WorktreeCubit, WorktreeSidebarView>(
      (c) => WorktreeSidebarView.from(c.state),
    );
    final personalLaunchBlocked = personalIdentityBlockedForWorkspace(
      isPersonal: _isPersonal,
      folders: widget.workspace.folders,
    );
    final toolsContext = WorkspaceToolsScope.maybeOf(context)?.tools?.context;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (personalLaunchBlocked)
            const MixedWorkspacePersonalLaunchBanner(),
          if (_isPersonal && !personalLaunchBlocked) ...[
            _PresetDropdown(
              workspaceId: widget.workspace.workspaceId,
              profileId: widget.profileId,
            ),
            const SizedBox(height: 12),
          ],
          _SidebarActionTile(
            key: AppKeys.newChatSidebarTile,
            icon: Icons.edit_outlined,
            label: l10n.homeWorkspaceNewConversation,
            enabled: !personalLaunchBlocked,
            disabledTooltip: l10n.mixedWorkspaceRequiresTeamLaunch,
            onTap: throttledAsync(
              'workspace_sidebar_new_chat',
              () => _startNewConversation(context),
            ),
          ),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 0, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.homeWorkspaceConversationsSection,
                    style: AppTextStyles.of(context).bodySmall.copyWith(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                _SessionSortButton(
                  sort: _sessionSort,
                  onChanged: (s) => setState(() => _sessionSort = s),
                ),
                const SizedBox(width: 2),
                AppIconButton(
                  icon: Icons.search_rounded,
                  compact: true, size: AppIconButton.kCompactSize,
                  tooltip: l10n.workspaceSearchTitle,
                  onTap: throttledTap(
                    'workspace_sidebar_search',
                    () => unawaited(
                      showWorkspaceSearchDialog(
                        context,
                        workspace: widget.workspace,
                        isPersonal: widget.isPersonalWorkspace,
                        sessionTeamFilter: widget.sessionTeamFilter,
                        personalLaunchBlocked: personalLaunchBlocked,
                      ),
                    ),
                  ),
                ),
                if (toolsContext != null &&
                    worktreeManagementEnabled(toolsContext)) ...[
                  const SizedBox(width: 2),
                  AppIconButton(
                    icon: Icons.refresh_rounded,
                    compact: true, size: AppIconButton.kCompactSize,
                    tooltip: l10n.worktreeRefreshTooltip,
                    onTap: throttledTap(
                      'workspace_sidebar_refresh_worktrees',
                      () => unawaited(
                        context.read<WorktreeCubit>().load(widget.workspace.firstFolderPath),
                      ),
                    ),
                  ),
                  const SizedBox(width: 2),
                  AppIconButton(
                    icon: Icons.account_tree_outlined,
                    compact: true, size: AppIconButton.kCompactSize,
                    tooltip: l10n.worktreeNewWorktreeTooltip,
                    onTap: throttledTap(
                      'workspace_sidebar_new_worktree',
                      () => unawaited(_createWorktree(context)),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: _buildBody(
              context,
              sortedSessions,
              wtView,
              personalLaunchBlocked: personalLaunchBlocked,
            ),
          ),
        ],
      ),
    );
  }

  /// Flat session list when the repo has only its main worktree; otherwise a
  /// collapsible worktree-grouped list. The "+ new worktree" header action is
  /// always available regardless of this branch.
  Widget _buildBody(
    BuildContext context,
    List<AppSession> sortedSessions,
    WorktreeSidebarView wtView, {
    required bool personalLaunchBlocked,
  }) {
    final l10n = context.l10n;
    switch (wtView.sessionListLayout) {
      case WorktreeSessionListLayout.indeterminate:
        return const _SessionListSkeleton();
      case WorktreeSessionListLayout.flat:
        return sortedSessions.isEmpty
            ? _EmptyConversations(label: l10n.homeWorkspaceNoConversations)
            : _buildSessionList(context, sortedSessions);
      case WorktreeSessionListLayout.grouped:
        final groups = groupSessionsByWorktree(
          worktrees: wtView.worktrees,
          sessions: sortedSessions,
        );
        return ListView.builder(
          padding: EdgeInsets.zero,
          itemCount: groups.length,
          itemBuilder: (context, index) {
            final group = groups[index];
            return WorktreeGroupSection(
              key: ValueKey('wt-group-${worktreeGroupCollapseKey(group)}'),
              group: group,
              workspace: widget.workspace,
              isPersonal: widget.isPersonalWorkspace,
              profileId: widget.profileId,
              sessionTeamFilter: widget.sessionTeamFilter,
              personalLaunchBlocked: personalLaunchBlocked,
              collapsed:
                  wtView.collapsed.contains(worktreeGroupCollapseKey(group)),
              isCurrent: group.worktree != null &&
                  workspacePathsEqual(
                    group.worktree!.path,
                    wtView.currentWorktreePath,
                  ),
            );
          },
        );
    }
  }

  Future<void> _createWorktree(BuildContext context) async {
    final cubit = context.read<WorktreeCubit>();
    final l10n = context.l10n;
    final tools = WorkspaceToolsScope.of(context).tools;
    if (tools == null) return;
    final repoPath = widget.workspace.firstFolderPath;
    final layout = WorkspaceLayout(teampilotRoot: AppStorage.paths.basePath);
    final result = await showWorktreeCreateDialog(
      context,
      repoName: _basename(repoPath),
      repoPath: repoPath,
      layout: layout.worktreePathFor,
      branchLoader: branchListLoaderFor(tools.context),
      showStartConversationOption: !personalIdentityBlockedForWorkspace(
        isPersonal: widget.isPersonalWorkspace,
        folders: widget.workspace.folders,
      ),
    );
    if (result == null) return;
    try {
      await GitWorktreeService.forContext(tools.context).add(
        repoPath,
        result.worktreePath,
        branch: result.branch,
        baseRef: result.baseRef,
        existingBranch: result.existingBranch,
      );
      await cubit.load(repoPath);
      cubit.setCurrentWorktree(result.worktreePath);
      if (result.startConversation && context.mounted) {
        await createSessionInWorktree(
          context,
          widget.workspace,
          isPersonal: widget.isPersonalWorkspace,
          worktreePath: result.worktreePath,
          sessionTeamId: widget.sessionTeamFilter,
          personalIdentityId: widget.profileId,
        );
      }
    } on Object catch (error) {
      if (!context.mounted) return;
      AppToast.show(
        context,
        message: l10n.worktreeCreateFailed(error.toString()),
        variant: AppToastVariant.error,
      );
    }
  }

  static String _basename(String path) {
    final parts = path.replaceAll(r'\', '/').split('/')
      ..removeWhere((e) => e.isEmpty);
    return parts.isEmpty ? path : parts.last;
  }

  Widget _buildSessionList(
    BuildContext context,
    List<AppSession> sessions,
  ) {
    // Drag-to-reorder is only meaningful in manual order; the auto-sorted modes
    // use a plain (crash-safe) ListView so frequent re-sorts never reparent
    // [ReorderableListView]'s keyed items under the workbench's LayoutBuilders.
    if (_sessionSort != AppSessionSort.manual) {
      return ListView.builder(
        padding: EdgeInsets.zero,
        itemCount: sessions.length,
        itemBuilder: (context, index) =>
            _sessionTile(context, sessions[index]),
      );
    }
    return ReorderableListView.builder(
      padding: EdgeInsets.zero,
      buildDefaultDragHandles: false,
      itemCount: sessions.length,
      onReorder: (oldIndex, newIndex) {
        var target = newIndex;
        if (target > oldIndex) target -= 1;
        if (target == oldIndex) return;
        final reordered = List<AppSession>.of(sessions);
        final moved = reordered.removeAt(oldIndex);
        reordered.insert(target, moved);
        unawaited(
          context.read<ChatCubit>().reorderSessions(
            [for (final s in reordered) s.sessionId],
          ),
        );
      },
      itemBuilder: (context, index) =>
          _sessionTile(context, sessions[index], index: index),
    );
  }

  Widget _sessionTile(
    BuildContext context,
    AppSession session, {
    int index = -1,
  }) {
    return SidebarSessionTile(
      key: ValueKey('workspace-sidebar-session-${session.sessionId}'),
      session: session,
      index: index,
      tapThrottleKeyPrefix: 'workspace_sidebar_session',
      onTap: () {
        if (personalIdentityBlockedForWorkspace(
          isPersonal: widget.isPersonalWorkspace,
          folders: widget.workspace.folders,
        )) {
          showPersonalLaunchBlockedToast(context);
          return;
        }
        unawaited(
          openWorkspaceSessionTab(
            context,
            widget.workspace,
            session,
            isPersonal: widget.isPersonalWorkspace,
          ),
        );
      },
    );
  }

  Future<void> _startNewConversation(
    BuildContext context, {
    CliTool? cli,
  }) async {
    await createAndOpenWorkspaceConversation(
      context,
      widget.workspace,
      isPersonal: widget.isPersonalWorkspace,
      sessionTeamId: widget.sessionTeamFilter,
      personalIdentityId: widget.profileId,
      cli: cli,
    );
  }
}

class _PresetDropdown extends StatefulWidget {
  const _PresetDropdown({required this.workspaceId, required this.profileId});

  final String workspaceId;
  final String profileId;

  @override
  State<_PresetDropdown> createState() => _PresetDropdownState();
}

class _PresetDropdownState extends State<_PresetDropdown> {
  bool _didAutoActivate = false;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final presetsState = context.watch<CliPresetsCubit>().state;
    final identityCubit = context.watch<LaunchProfileCubit>();
    final opened = identityCubit.state.byId(widget.profileId);
    final personal =
        opened is PersonalProfile ? opened : identityCubit.activePersonal;

    if (personal == null || presetsState.status == CliPresetsLoadStatus.loading) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(4, 0, 4, 0),
        child: LinearProgressIndicator(minHeight: 2),
      );
    }

    final presets = presetsState.presets;
    final activePreset = presetsState.presetById(personal.activePresetId ?? '');

    if (presets.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 0),
        child: OutlinedButton.icon(
          onPressed: () {
            showDialog<void>(
              context: context,
              builder: (_) => const CliPresetsManageDialog(),
            );
          },
          icon: const Icon(Icons.add, size: 18),
          label: Text(l10n.workspaceCliAddPresetTitle),
          style: OutlinedButton.styleFrom(
            visualDensity: VisualDensity.compact,
          ),
        ),
      );
    }

    // Auto-activate the first preset when none is active (e.g., after the
    // user adds their first preset).  Without this the dropdown shows a
    // preset as selected while activePresetId stays null, so sessions
    // launch with the default CLI instead of the preset config.
    if (!_didAutoActivate && activePreset == null && presets.isNotEmpty) {
      _didAutoActivate = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        context
            .read<LaunchProfileCubit>()
            .setPersonalPreset(widget.profileId, presets.first.id);
      });
    }

    final presetNames = presets.map((p) => p.id).toList();
    final initialId = activePreset?.id ?? presets.first.id;

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: AppDropdownField<String>(
              key: ValueKey('workspace-sidebar-preset-${widget.workspaceId}-$initialId'),
              items: presetNames,
              initialItem: initialId,
              decoration: AppDropdownDecorations.themed(context),
              onChanged: (value) {
                if (value == null) return;
                context
                    .read<LaunchProfileCubit>()
                    .setPersonalPreset(widget.profileId, value);
              },
              itemBuilder: (context, presetId) {
                final preset = presetsState.presetById(presetId);
                if (preset == null) {
                  return Text(presetId, style: AppTextStyles.of(context).bodySmall);
                }
                return _PresetDropdownItem(preset: preset);
              },
            ),
          ),
          const SizedBox(width: 4),
          AppIconButton(
            icon: Icons.tune_outlined,
            tooltip: l10n.workspaceCliPresetsManageTitle,
            onTap: throttledTap(
              'workspace_sidebar_presets_manage',
              () => unawaited(
                showDialog<void>(
                  context: context,
                  builder: (_) => const CliPresetsManageDialog(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PresetDropdownItem extends StatelessWidget {
  const _PresetDropdownItem({required this.preset});

  final CliPreset preset;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final registry = CliToolRegistryScope.of(context);
    final def = registry.tryGet(preset.cli);
    final cs = Theme.of(context).colorScheme;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CliBrandIcon(
          cli: preset.cli,
          definition: def,
          size: 22,
          borderRadius: 6,
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            preset.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.of(context).prominent.copyWith(color: cs.onSurface),
          ),
        ),
      ],
    );
  }
}

class _SidebarActionTile extends StatefulWidget {
  const _SidebarActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.enabled = true,
    this.disabledTooltip,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool enabled;
  final String? disabledTooltip;

  @override
  State<_SidebarActionTile> createState() => _SidebarActionTileState();
}

class _SidebarActionTileState extends State<_SidebarActionTile> {
  bool _hovered = false;

  bool get _enabled => widget.enabled;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = AppTextStyles.of(context);
    final background = !_enabled
        ? Colors.transparent
        : _hovered
        ? cs.onSurface.withValues(alpha: 0.05)
        : Colors.transparent;
    final foreground = _enabled
        ? cs.onSurface
        : cs.onSurface.withValues(alpha: 0.38);

    final tile = MouseRegion(
      onEnter: _enabled ? (_) => setState(() => _hovered = true) : null,
      onExit: _enabled ? (_) => setState(() => _hovered = false) : null,
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: _enabled ? widget.onTap : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            child: Row(
              children: [
                Icon(widget.icon, size: context.appIconSizes.md, color: foreground),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.label,
                    style: styles.prominent.copyWith(
                      color: foreground,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (!_enabled && widget.disabledTooltip != null) {
      return Tooltip(message: widget.disabledTooltip!, child: tile);
    }
    return tile;
  }
}

class _SessionSortButton extends StatelessWidget {
  const _SessionSortButton({required this.sort, required this.onChanged});

  final AppSessionSort sort;
  final ValueChanged<AppSessionSort> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return SidebarActionMenuIconAnchor(
      size: AppIconButton.kCompactSize,
      triggerBuilder: (context, controller) => AppIconButton(
        icon: Icons.sort_rounded,
        compact: true,
        size: AppIconButton.kCompactSize,
        tooltip: l10n.sessionSortTooltip,
        onTap: () {
          if (controller.isOpen) {
            controller.close();
          } else {
            controller.open();
          }
        },
      ),
      buildMenuChildren: (context, controller) {
        return [
          for (final value in AppSessionSort.values)
            SidebarActionMenuItem(
              icon: _iconForSessionSort(value),
              label: _labelForSessionSort(value, l10n),
              trailing: sort == value
                  ? Icon(
                      Icons.check,
                      size: context.appIconSizes.md,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.7),
                    )
                  : null,
              menuController: controller,
              onTap: () => onChanged(value),
            ),
        ];
      },
    );
  }

  static String _labelForSessionSort(
    AppSessionSort sort,
    AppLocalizations l10n,
  ) =>
      switch (sort) {
        AppSessionSort.manual => l10n.sessionSortManual,
        AppSessionSort.recentlyUpdated => l10n.sessionSortRecentlyUpdated,
        AppSessionSort.createdDesc => l10n.sessionSortCreatedDesc,
      };

  static IconData _iconForSessionSort(AppSessionSort sort) => switch (sort) {
    AppSessionSort.manual => Icons.drag_indicator_rounded,
    AppSessionSort.recentlyUpdated => Icons.update_rounded,
    AppSessionSort.createdDesc => Icons.event_rounded,
  };
}

class _EmptyConversations extends StatelessWidget {
  const _EmptyConversations({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = AppTextStyles.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.forum_outlined,
              size: context.appIconSizes.md,
              color: cs.onSurfaceVariant.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 10),
            Text(
              label,
              textAlign: TextAlign.center,
              style: styles.bodySmall.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

/// Placeholder while the git worktree list for this workspace is still loading.
/// Avoids briefly showing a flat session list that immediately regroups.
class _SessionListSkeleton extends StatelessWidget {
  const _SessionListSkeleton();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fill = cs.onSurface.withValues(alpha: 0.08);
    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: 5,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final widthFactor = switch (index % 3) {
          0 => 0.92,
          1 => 0.74,
          _ => 0.58,
        };
        return LayoutBuilder(
          builder: (context, constraints) {
            return Container(
              height: 34,
              width: constraints.maxWidth * widthFactor,
              decoration: BoxDecoration(
                color: fill,
                borderRadius: BorderRadius.circular(8),
              ),
            );
          },
        );
      },
    );
  }
}
