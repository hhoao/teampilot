import 'dart:async';

import 'package:flutter/material.dart';
import 'package:teampilot/theme/app_icon_sizes.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../cubits/launch_profile_cubit.dart';
import '../../cubits/team/launch_profile_selectors.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/launch_profile_kind.dart';
import '../../services/storage/launch_profile_provisioner.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/workspace_surface_layers.dart';
import '../../utils/app_keys.dart';
import 'home_workspace_global_section.dart';
import 'home_workspace_library_view.dart';
import 'home_workspace_new_team_dialog.dart';

const double _kIdentityDragGutterWidth = 28;
const double _kIdentityGutterGap = 4;
const double _kIdentityContentPaddingLeft = 12;

/// Left rail of the workspace home: workspace identities plus global management
/// shortcuts, mirroring the Apifox sidebar. LaunchProfile selection drives the
/// right pane; global shortcuts swap it via [onSelectGlobalView].
class HomeSidebar extends StatefulWidget {
  const HomeSidebar({
    this.activeGlobalView,
    this.activeLibraryView,
    this.allWorkspacesActive = false,
    this.selectedIdentityId,
    this.onSelectAllWorkspaces,
    this.onSelectGlobalView,
    this.onSelectLibraryView,
    this.onSelectIdentity,
    super.key,
  });

  /// Currently shown global section, or null when a workspace identity is shown.
  final HomeGlobalView? activeGlobalView;
  final HomeLibraryView? activeLibraryView;
  final bool allWorkspacesActive;
  final String? selectedIdentityId;
  final VoidCallback? onSelectAllWorkspaces;
  final ValueChanged<HomeGlobalView>? onSelectGlobalView;
  final ValueChanged<HomeLibraryView>? onSelectLibraryView;
  final ValueChanged<String>? onSelectIdentity;

  static const double width = 420;

  @override
  State<HomeSidebar> createState() => _HomeSidebarState();
}

class _HomeSidebarState extends State<HomeSidebar> {
  bool _teamsExpanded = true;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final identityCubit = context.read<LaunchProfileCubit>();
    final identities = context.select<LaunchProfileCubit, HomeSidebarIdentitySnapshot>(
      (c) => LaunchProfileSelectors.sidebarIdentities(c.state),
    );
    final personals = identities.personals;
    final teams = identities.teams;
    final selectedIdentityId = widget.selectedIdentityId;
    final onIdentity = widget.onSelectIdentity;
    final onAllWorkspaces = widget.onSelectAllWorkspaces;
    final onGlobal = widget.onSelectGlobalView;
    final onLibrary = widget.onSelectLibraryView;
    final activeGlobalView = widget.activeGlobalView;
    final activeLibraryView = widget.activeLibraryView;
    final allWorkspacesActive = widget.allWorkspacesActive;

    return Container(
      width: HomeSidebar.width,
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
            active: activeLibraryView == HomeLibraryView.favorites,
            onTap: () => onLibrary?.call(HomeLibraryView.favorites),
          ),
          const SizedBox(height: 4),
          _ShortcutRow(
            icon: Icons.history_rounded,
            label: l10n.homeWorkspaceRecentVisits,
            active: activeLibraryView == HomeLibraryView.recent,
            onTap: () => onLibrary?.call(HomeLibraryView.recent),
          ),
          const SizedBox(height: 12),
          Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.5)),
          const SizedBox(height: 8),
          _ShortcutRow(
            icon: Icons.folder_copy_outlined,
            label: l10n.homeWorkspaceAllWorkspaces,
            active: allWorkspacesActive,
            onTap: () => onAllWorkspaces?.call(),
          ),
          const SizedBox(height: 12),
          Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.5)),
          const SizedBox(height: 8),
          _SectionHeader(
            icon: Icons.workspaces_outlined,
            label: l10n.homeWorkspaceMyTeams,
            expanded: _teamsExpanded,
            onToggle: () => setState(() => _teamsExpanded = !_teamsExpanded),
          ),
          Expanded(
            child: CustomScrollView(
              slivers: [
                if (_teamsExpanded && personals.isNotEmpty)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(0, 8, 0, 0),
                    sliver: SliverReorderableList(
                      itemCount: personals.length,
                      onReorder: (oldIndex, newIndex) {
                        unawaited(
                          identityCubit.reorderPersonals(oldIndex, newIndex),
                        );
                      },
                      itemBuilder: (context, index) {
                        final personal = personals[index];
                        return _IdentityRow(
                          key: ValueKey(personal.id),
                          index: index,
                          name: _sidebarDisplayName(l10n, personal),
                          isTeam: false,
                          selected:
                              !allWorkspacesActive &&
                              activeGlobalView == null &&
                              activeLibraryView == null &&
                              personal.id == selectedIdentityId,
                          onTap: () => onIdentity?.call(personal.id),
                        );
                      },
                    ),
                  ),
                if (_teamsExpanded && teams.isNotEmpty)
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(0, personals.isEmpty ? 8 : 0, 0, 0),
                    sliver: SliverReorderableList(
                      itemCount: teams.length,
                      onReorder: (oldIndex, newIndex) {
                        unawaited(identityCubit.reorderTeams(oldIndex, newIndex));
                      },
                      itemBuilder: (context, index) {
                        final team = teams[index];
                        return _IdentityRow(
                          key: ValueKey(team.id),
                          index: index,
                          name: _sidebarDisplayName(l10n, team),
                          isTeam: true,
                          selected:
                              !allWorkspacesActive &&
                              activeGlobalView == null &&
                              activeLibraryView == null &&
                              team.id == selectedIdentityId,
                          onTap: () => onIdentity?.call(team.id),
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
                                if (personals.isEmpty && teams.isEmpty)
                                  const SizedBox(height: 8),
                                _NewTeamRow(
                                  label: l10n.homeWorkspaceNewTeam,
                                  onTap: () => showHomeNewTeamDialog(
                                    context,
                                    identityCubit,
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
                              HomeGlobalView.teamHub,
                          onTap: () =>
                              onGlobal?.call(HomeGlobalView.teamHub),
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
                              HomeGlobalView.skills,
                          onTap: () =>
                              onGlobal?.call(HomeGlobalView.skills),
                        ),
                        const SizedBox(height: 4),
                        _ShortcutRow(
                          icon: Icons.widgets_outlined,
                          label: l10n.teamPluginsNav,
                          active:
                              activeGlobalView ==
                              HomeGlobalView.plugins,
                          onTap: () =>
                              onGlobal?.call(HomeGlobalView.plugins),
                        ),
                        const SizedBox(height: 4),
                        _ShortcutRow(
                          icon: Icons.hub_outlined,
                          label: l10n.teamMcpNav,
                          active:
                              activeGlobalView == HomeGlobalView.mcp,
                          onTap: () =>
                              onGlobal?.call(HomeGlobalView.mcp),
                        ),
                        const SizedBox(height: 4),
                        _ShortcutRow(
                          icon: Icons.power_outlined,
                          label: l10n.teamExtensionsNav,
                          active:
                              activeGlobalView ==
                              HomeGlobalView.extensions,
                          onTap: () => onGlobal?.call(
                            HomeGlobalView.extensions,
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
            active: activeGlobalView == HomeGlobalView.providers,
            onTap: () => onGlobal?.call(HomeGlobalView.providers),
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

class _IdentityRow extends StatefulWidget {
  const _IdentityRow({
    super.key,
    required this.index,
    required this.name,
    required this.isTeam,
    required this.selected,
    required this.onTap,
  });

  final int index;
  final String name;
  final bool isTeam;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_IdentityRow> createState() => _IdentityRowState();
}

class _IdentityRowState extends State<_IdentityRow> {
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
                  width: _kIdentityDragGutterWidth,
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
            const SizedBox(width: _kIdentityGutterGap),
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
                    child: Row(
                      children: [
                        Icon(
                          widget.isTeam
                              ? Icons.groups_2_outlined
                              : Icons.person_outline_rounded,
                          size: context.appIconSizes.md,
                          color: selected ? cs.primary : cs.onSurfaceVariant,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            widget.name,
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
                      ],
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
        padding: EdgeInsets.fromLTRB(
          _kIdentityDragGutterWidth +
              _kIdentityGutterGap +
              _kIdentityContentPaddingLeft,
          10,
          11,
          10,
        ),
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

    return RepaintBoundary(
      child: MouseRegion(
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

String _sidebarDisplayName(
  AppLocalizations l10n,
  IdentitySidebarEntry entry,
) {
  if (entry.kind == LaunchProfileKind.personal &&
      entry.id == LaunchProfileProvisioner.defaultPersonalId) {
    return l10n.homeWorkspaceDefaultPersonalWorkspaceName;
  }
  if (entry.kind == LaunchProfileKind.team &&
      entry.id == LaunchProfileProvisioner.defaultTeamId) {
    return l10n.homeWorkspaceDefaultTeamName;
  }
  return entry.display;
}
