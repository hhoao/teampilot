import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:teampilot/theme/app_icon_sizes.dart';

import '../../../cubits/chat_cubit.dart';
import '../../../cubits/cli_presets_cubit.dart';
import '../../../cubits/identity_cubit.dart';
import '../../../l10n/l10n_extensions.dart';
import '../../../models/app_project.dart';
import '../../../models/app_session.dart';
import '../../../models/cli_preset.dart';
import '../../../models/personal_identity.dart';
import '../../../models/team_config.dart';
import '../../../services/cli/registry/cli_tool_registry_scope.dart';
import '../../../theme/app_text_styles.dart';
import '../../../utils/app_keys.dart';
import '../../../utils/app_session_sort.dart';
import '../../../utils/debounce/debounce.dart';
import '../../../utils/project_sessions.dart';
import '../../../widgets/app_icon_button.dart';
import '../../../widgets/cli/cli_brand_icon.dart';
import '../../../widgets/menu/sidebar_action_menu.dart';
import 'config/cli_presets_manage_dialog.dart';
import '../../../widgets/dropdown/app_dropdown_decoration.dart';
import '../../../widgets/dropdown/app_dropdown_field.dart';
import '../../../widgets/sidebar_session_tile.dart';
import 'project_search_dialog.dart';
import 'project_session_actions.dart';

/// Shared resize limits for [HomeWorkspaceProjectSidebar].
class HomeWorkspaceProjectSidebarLayout {
  const HomeWorkspaceProjectSidebarLayout._();

  static const double defaultWidth = 280;
  static const double minWidth = 220;
  static const double maxWidth = 480;
}

/// Project conversation sidebar (personal and team workbenches).
class HomeWorkspaceProjectSidebar extends StatefulWidget {
  const HomeWorkspaceProjectSidebar({
    required this.project,
    required this.isPersonalProject,
    required this.identityId,
    required this.sessionTeamFilter,
    super.key,
  });

  final AppProject project;
  final bool isPersonalProject;

  /// The launch identity the project was opened against ([Identity.id]).
  final String identityId;
  final String sessionTeamFilter;

  @override
  State<HomeWorkspaceProjectSidebar> createState() =>
      _HomeWorkspaceProjectSidebarState();
}

class _HomeWorkspaceProjectSidebarState
    extends State<HomeWorkspaceProjectSidebar> {
  static const _emptySessions = <AppSession>[];

  bool get _isPersonal => widget.isPersonalProject;

  AppSessionSort _sessionSort = AppSessionSort.manual;

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final rawSessions = context.select<ChatCubit, List<AppSession>>((c) {
      final grouped = groupSessionsByProjectId(c.state.sessions);
      final bucket = grouped[widget.project.projectId];
      if (bucket == null || bucket.isEmpty) {
        return sessionsForProject(widget.project, _emptySessions)
            .where((s) => s.sessionTeam.trim() == widget.sessionTeamFilter)
            .toList();
      }
      return sessionsForProject(widget.project, bucket)
          .where((s) => s.sessionTeam.trim() == widget.sessionTeamFilter)
          .toList();
    });
    final sortedSessions = sortAppSessions(rawSessions, sort: _sessionSort);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_isPersonal) ...[
            _PresetDropdown(
              projectId: widget.project.projectId,
              identityId: widget.identityId,
            ),
            const SizedBox(height: 12),
          ],
          _SidebarActionTile(
            key: AppKeys.newChatSidebarTile,
            icon: Icons.edit_outlined,
            label: l10n.homeWorkspaceNewConversation,
            onTap: throttledAsync(
              'project_sidebar_new_chat',
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
                  tooltip: l10n.projectSearchTitle,
                  onTap: throttledTap(
                    'project_sidebar_search',
                    () => unawaited(
                      showProjectSearchDialog(
                        context,
                        project: widget.project,
                        isPersonal: widget.isPersonalProject,
                        sessionTeamFilter: widget.sessionTeamFilter,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: sortedSessions.isEmpty
                ? _EmptyConversations(label: l10n.homeWorkspaceNoConversations)
                : _buildSessionList(context, sortedSessions),
          ),
        ],
      ),
    );
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
      key: ValueKey('project-sidebar-session-${session.sessionId}'),
      session: session,
      index: index,
      tapThrottleKeyPrefix: 'project_sidebar_session',
      onTap: () => unawaited(
        openProjectSessionTab(
          context,
          widget.project,
          session,
          isPersonal: widget.isPersonalProject,
        ),
      ),
    );
  }

  Future<void> _startNewConversation(
    BuildContext context, {
    CliTool? cli,
  }) async {
    await createAndOpenProjectConversation(
      context,
      widget.project,
      isPersonal: widget.isPersonalProject,
      sessionTeamId: widget.sessionTeamFilter,
      personalIdentityId: widget.identityId,
      cli: cli,
    );
  }
}

class _PresetDropdown extends StatefulWidget {
  const _PresetDropdown({required this.projectId, required this.identityId});

  final String projectId;
  final String identityId;

  @override
  State<_PresetDropdown> createState() => _PresetDropdownState();
}

class _PresetDropdownState extends State<_PresetDropdown> {
  bool _didAutoActivate = false;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final presetsState = context.watch<CliPresetsCubit>().state;
    final identityCubit = context.watch<IdentityCubit>();
    final opened = identityCubit.state.byId(widget.identityId);
    final personal =
        opened is PersonalIdentity ? opened : identityCubit.activePersonal;

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
          label: Text(l10n.projectCliAddPresetTitle),
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
            .read<IdentityCubit>()
            .setPersonalPreset(widget.identityId, presets.first.id);
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
              key: ValueKey('project-sidebar-preset-${widget.projectId}-$initialId'),
              items: presetNames,
              initialItem: initialId,
              decoration: AppDropdownDecorations.themed(context),
              onChanged: (value) {
                if (value == null) return;
                context
                    .read<IdentityCubit>()
                    .setPersonalPreset(widget.identityId, value);
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
            tooltip: l10n.projectCliPresetsManageTitle,
            onTap: throttledTap(
              'project_sidebar_presets_manage',
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
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  State<_SidebarActionTile> createState() => _SidebarActionTileState();
}

class _SidebarActionTileState extends State<_SidebarActionTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = AppTextStyles.of(context);
    final background = _hovered
        ? cs.onSurface.withValues(alpha: 0.05)
        : Colors.transparent;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: widget.onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            child: Row(
              children: [
                Icon(widget.icon, size: context.appIconSizes.md, color: cs.onSurface),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.label,
                    style: styles.prominent.copyWith(
                      color: cs.onSurface,
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
