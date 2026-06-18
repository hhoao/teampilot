import 'dart:async';

import 'package:flutter/material.dart';
import 'package:teampilot/theme/app_icon_sizes.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../cubits/identity_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/team_config.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/workspace_surface_layers.dart';
import '../../utils/app_keys.dart';
import 'home_workspace_global_section.dart';
import 'home_workspace_library_view.dart';
import 'home_workspace_new_team_dialog.dart';

/// Left rail of the workspace home: "My Teams" list plus global management
/// shortcuts, mirroring the Apifox sidebar. Team selection drives the global
/// [IdentityCubit]; global shortcuts swap the right pane via [onSelectGlobalView].
class HomeWorkspaceSidebar extends StatefulWidget {
  const HomeWorkspaceSidebar({
    this.activeGlobalView,
    this.activeLibraryView,
    this.allProjectsActive = false,
    this.onSelectAllProjects,
    this.onSelectGlobalView,
    this.onSelectLibraryView,
    this.onSelectTeam,
    super.key,
  });

  /// Currently shown global section, or null when a team is shown.
  final HomeWorkspaceGlobalView? activeGlobalView;
  final HomeWorkspaceLibraryView? activeLibraryView;
  final bool allProjectsActive;
  final VoidCallback? onSelectAllProjects;
  final ValueChanged<HomeWorkspaceGlobalView>? onSelectGlobalView;
  final ValueChanged<HomeWorkspaceLibraryView>? onSelectLibraryView;
  final ValueChanged<String>? onSelectTeam;

  static const double width = 420;

  @override
  State<HomeWorkspaceSidebar> createState() => _HomeWorkspaceSidebarState();
}

class _HomeWorkspaceSidebarState extends State<HomeWorkspaceSidebar> {
  bool _teamsExpanded = true;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final teamCubit = context.watch<IdentityCubit>();
    final teams = teamCubit.state.teams;
    final selected = teamCubit.state.selectedTeam;
    final onTeam = widget.onSelectTeam;
    final onAllProjects = widget.onSelectAllProjects;
    final onGlobal = widget.onSelectGlobalView;
    final onLibrary = widget.onSelectLibraryView;
    final activeGlobalView = widget.activeGlobalView;
    final activeLibraryView = widget.activeLibraryView;
    final allProjectsActive = widget.allProjectsActive;

    return Container(
      width: HomeWorkspaceSidebar.width,
      decoration: BoxDecoration(
        color: cs.workspaceCard,
        border: Border(
          right: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.6)),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(32, 48, 24, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ShortcutRow(
            icon: Icons.star_outline_rounded,
            label: l10n.homeWorkspaceMyFavorites,
            active: activeLibraryView == HomeWorkspaceLibraryView.favorites,
            onTap: () => onLibrary?.call(HomeWorkspaceLibraryView.favorites),
          ),
          const SizedBox(height: 4),
          _ShortcutRow(
            icon: Icons.history_rounded,
            label: l10n.homeWorkspaceRecentVisits,
            active: activeLibraryView == HomeWorkspaceLibraryView.recent,
            onTap: () => onLibrary?.call(HomeWorkspaceLibraryView.recent),
          ),
          const SizedBox(height: 12),
          Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.5)),
          const SizedBox(height: 8),
          _ShortcutRow(
            icon: Icons.folder_copy_outlined,
            label: l10n.homeWorkspaceAllProjects,
            active: allProjectsActive,
            onTap: () => onAllProjects?.call(),
          ),
          const SizedBox(height: 12),
          Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.5)),
          const SizedBox(height: 8),
          _SectionHeader(
            icon: Icons.groups_2_outlined,
            label: l10n.homeWorkspaceMyTeams,
            expanded: _teamsExpanded,
            onToggle: () => setState(() => _teamsExpanded = !_teamsExpanded),
          ),
          Expanded(
            child: CustomScrollView(
              slivers: [
                if (_teamsExpanded && teams.isNotEmpty)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(0, 8, 0, 0),
                    sliver: SliverReorderableList(
                      itemCount: teams.length,
                      onReorder: (oldIndex, newIndex) {
                        unawaited(teamCubit.reorderTeams(oldIndex, newIndex));
                      },
                      itemBuilder: (context, index) {
                        final team = teams[index];
                        return _TeamRow(
                          key: ValueKey(team.id),
                          index: index,
                          team: team,
                          selected:
                              !allProjectsActive &&
                              activeGlobalView == null &&
                              activeLibraryView == null &&
                              team.id == selected?.id,
                          onTap: () => onTeam?.call(team.id),
                        );
                      },
                    ),
                  ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(0, 0, 0, 8),
                  sliver: SliverToBoxAdapter(
                    child: AnimatedSize(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      alignment: Alignment.topCenter,
                      child: _teamsExpanded
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (teams.isEmpty) const SizedBox(height: 8),
                                _NewTeamRow(
                                  label: l10n.homeWorkspaceNewTeam,
                                  onTap: () => showHomeWorkspaceNewTeamDialog(
                                    context,
                                    teamCubit,
                                  ),
                                ),
                                const SizedBox(height: 10),
                              ],
                            )
                          : const SizedBox(width: double.infinity),
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(0, 0, 0, 8),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 8),
                        Divider(
                          height: 1,
                          color: cs.outlineVariant.withValues(alpha: 0.5),
                        ),
                        const SizedBox(height: 8),
                        _ShortcutRow(
                          icon: Icons.travel_explore_outlined,
                          label: l10n.teamHubNav,
                          active:
                              activeGlobalView ==
                              HomeWorkspaceGlobalView.teamHub,
                          onTap: () =>
                              onGlobal?.call(HomeWorkspaceGlobalView.teamHub),
                        ),
                        const SizedBox(height: 8),
                        Divider(
                          height: 1,
                          color: cs.outlineVariant.withValues(alpha: 0.5),
                        ),
                        const SizedBox(height: 8),
                        _ShortcutRow(
                          icon: Icons.extension_outlined,
                          label: l10n.teamSkillsNav,
                          active:
                              activeGlobalView ==
                              HomeWorkspaceGlobalView.skills,
                          onTap: () =>
                              onGlobal?.call(HomeWorkspaceGlobalView.skills),
                        ),
                        const SizedBox(height: 4),
                        _ShortcutRow(
                          icon: Icons.widgets_outlined,
                          label: l10n.teamPluginsNav,
                          active:
                              activeGlobalView ==
                              HomeWorkspaceGlobalView.plugins,
                          onTap: () =>
                              onGlobal?.call(HomeWorkspaceGlobalView.plugins),
                        ),
                        const SizedBox(height: 4),
                        _ShortcutRow(
                          icon: Icons.hub_outlined,
                          label: l10n.teamMcpNav,
                          active:
                              activeGlobalView == HomeWorkspaceGlobalView.mcp,
                          onTap: () =>
                              onGlobal?.call(HomeWorkspaceGlobalView.mcp),
                        ),
                        const SizedBox(height: 4),
                        _ShortcutRow(
                          icon: Icons.power_outlined,
                          label: l10n.teamExtensionsNav,
                          active:
                              activeGlobalView ==
                              HomeWorkspaceGlobalView.extensions,
                          onTap: () => onGlobal?.call(
                            HomeWorkspaceGlobalView.extensions,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.5)),
          _ProvidersButton(
            key: AppKeys.homeWorkspaceProvidersButton,
            label: l10n.homeWorkspaceProviders,
            active: activeGlobalView == HomeWorkspaceGlobalView.providers,
            onTap: () => onGlobal?.call(HomeWorkspaceGlobalView.providers),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.label,
    required this.expanded,
    required this.onToggle,
  });

  final IconData icon;
  final String label;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = AppTextStyles.of(context);
    return InkWell(
      onTap: onToggle,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 6, 10),
        child: Row(
          children: [
            Icon(icon, size: context.appIconSizes.md, color: cs.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(child: Text(label, style: styles.prominent)),
            AnimatedRotation(
              turns: expanded ? 0 : -0.25,
              duration: const Duration(milliseconds: 180),
              child: Icon(
                Icons.expand_more_rounded,
                size: context.appIconSizes.md,
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TeamRow extends StatefulWidget {
  const _TeamRow({
    super.key,
    required this.index,
    required this.team,
    required this.selected,
    required this.onTap,
  });

  final int index;
  final TeamIdentity team;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_TeamRow> createState() => _TeamRowState();
}

class _TeamRowState extends State<_TeamRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = AppTextStyles.of(context);
    final selected = widget.selected;

    final Color background = selected
        ? cs.primary.withValues(alpha: 0.14)
        : _hovered
        ? cs.onSurface.withValues(alpha: 0.05)
        : Colors.transparent;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            ReorderableDragStartListener(
              index: widget.index,
              child: MouseRegion(
                cursor: _hovered
                    ? SystemMouseCursors.grab
                    : SystemMouseCursors.basic,
                child: SizedBox(
                  width: 28,
                  height: 40,
                  child: AnimatedOpacity(
                    opacity: _hovered ? 0.65 : 0,
                    duration: const Duration(milliseconds: 120),
                    curve: Curves.easeOut,
                    child: Icon(
                      Icons.drag_indicator_rounded,
                      size: 18,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: widget.onTap,
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(12, 10, 11, 10),
                    decoration: BoxDecoration(
                      color: background,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      widget.team.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: styles.prominent.copyWith(
                        color: selected ? cs.primary : cs.onSurface,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NewTeamRow extends StatelessWidget {
  const _NewTeamRow({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = AppTextStyles.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
        child: Row(
          children: [
            Icon(Icons.add_rounded, size: context.appIconSizes.md, color: cs.primary),
            const SizedBox(width: 8),
            Text(label, style: styles.prominent.copyWith(color: cs.primary)),
          ],
        ),
      ),
    );
  }
}

class _ShortcutRow extends StatefulWidget {
  const _ShortcutRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;

  @override
  State<_ShortcutRow> createState() => _ShortcutRowState();
}

class _ShortcutRowState extends State<_ShortcutRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = AppTextStyles.of(context);
    final active = widget.active;
    final Color fg = active ? cs.primary : cs.onSurface;
    final Color background = active
        ? cs.primary.withValues(alpha: 0.14)
        : _hovered
        ? cs.onSurface.withValues(alpha: 0.05)
        : Colors.transparent;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 1),
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(
                widget.icon,
                size: context.appIconSizes.md,
                color: active ? cs.primary : cs.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Text(
                widget.label,
                style: styles.prominent.copyWith(
                  color: fg,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProvidersButton extends StatelessWidget {
  const _ProvidersButton({
    required this.label,
    required this.onTap,
    this.active = false,
    super.key,
  });

  final String label;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = AppTextStyles.of(context);
    final Color fg = active ? cs.primary : cs.onSurface;
    final Color background = active
        ? cs.primary.withValues(alpha: 0.14)
        : cs.surfaceContainer;
    final Color borderColor = active
        ? cs.primary.withValues(alpha: 0.45)
        : cs.outlineVariant.withValues(alpha: 0.7);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.memory_outlined,
              size: context.appIconSizes.md,
              color: active ? cs.primary : cs.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: styles.body.copyWith(
                color: fg,
                fontWeight: active ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
