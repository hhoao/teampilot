import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../l10n/l10n_extensions.dart';
import '../../models/layout_preferences.dart';
import '../../theme/workspace_surface_layers.dart';
import '../../theme/app_typography_scale.dart';
import '../../utils/ui/app_keys.dart';
import 'home_workspace_global_section.dart';
import 'home_workspace_library_view.dart';

/// Left rail of the workspace home: library shortcuts plus global management
/// entries, mirroring the Apifox sidebar. Global shortcuts swap the right pane
/// via [onSelectGlobalView] / [onSelectLibraryView].
class HomeSidebar extends StatelessWidget {
  const HomeSidebar({
    this.activeGlobalView,
    this.activeLibraryView,
    this.allWorkspacesActive = false,
    this.onSelectAllWorkspaces,
    this.onSelectGlobalView,
    this.onSelectLibraryView,
    super.key,
  });

  /// Currently shown global section, or null when a workspace identity is shown.
  final HomeGlobalView? activeGlobalView;
  final HomeLibraryView? activeLibraryView;
  final bool allWorkspacesActive;
  final VoidCallback? onSelectAllWorkspaces;
  final ValueChanged<HomeGlobalView>? onSelectGlobalView;
  final ValueChanged<HomeLibraryView>? onSelectLibraryView;

  static const double width = LayoutPreferences.defaultHomeSidebarWidth;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final onAllWorkspaces = onSelectAllWorkspaces;
    final onGlobal = onSelectGlobalView;
    final onLibrary = onSelectLibraryView;
    final isMobileDrawer = TpSidebarScope.maybeOf(context)?.isMobile ?? false;

    return Container(
      decoration: BoxDecoration(
        color: cs.workspaceCard,
        border: Border(
          right: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.6)),
        ),
      ),
      padding: isMobileDrawer
          ? const EdgeInsets.fromLTRB(16, 24, 16, 12)
          : const EdgeInsets.fromLTRB(32, 48, 24, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ShortcutRow(
            icon: Icons.schedule_rounded,
            label: l10n.automationsTitle,
            active: activeGlobalView == HomeGlobalView.automations,
            onTap: () => onGlobal?.call(HomeGlobalView.automations),
          ),
          const SizedBox(height: 4),
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
          Expanded(
            child: _HomeSidebarNavScroll(
              activeGlobalView: activeGlobalView,
              onGlobal: onGlobal,
            ),
          ),
          Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.5)),
          // Bell + settings live in HomeTitleBar on mobile; footer is providers only.
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

class _HomeSidebarNavScroll extends StatelessWidget {
  const _HomeSidebarNavScroll({
    required this.activeGlobalView,
    required this.onGlobal,
  });

  final HomeGlobalView? activeGlobalView;
  final ValueChanged<HomeGlobalView>? onGlobal;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final onGlobal = this.onGlobal;
    final activeGlobalView = this.activeGlobalView;

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        _ShortcutRow(
          icon: Icons.groups_2_outlined,
          label: l10n.myTeamsNav,
          active: activeGlobalView == HomeGlobalView.myTeams,
          onTap: () => onGlobal?.call(HomeGlobalView.myTeams),
        ),
        const SizedBox(height: 4),
        _ShortcutRow(
          icon: Icons.badge_outlined,
          label: l10n.myExpertsNav,
          active: activeGlobalView == HomeGlobalView.myExperts,
          onTap: () => onGlobal?.call(HomeGlobalView.myExperts),
        ),
        const SizedBox(height: 8),
        Divider(
          height: 1,
          color: cs.outlineVariant.withValues(alpha: 0.5),
        ),
        const SizedBox(height: 8),
        _ShortcutRow(
          icon: Icons.travel_explore_outlined,
          label: l10n.teamHubNav,
          active: activeGlobalView == HomeGlobalView.teamHub,
          onTap: () => onGlobal?.call(HomeGlobalView.teamHub),
        ),
        const SizedBox(height: 4),
        _ShortcutRow(
          icon: Icons.psychology_outlined,
          label: l10n.expertHubNav,
          active: activeGlobalView == HomeGlobalView.expertHub,
          onTap: () => onGlobal?.call(HomeGlobalView.expertHub),
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
          active: activeGlobalView == HomeGlobalView.skills,
          onTap: () => onGlobal?.call(HomeGlobalView.skills),
        ),
        const SizedBox(height: 4),
        _ShortcutRow(
          icon: Icons.widgets_outlined,
          label: l10n.teamPluginsNav,
          active: activeGlobalView == HomeGlobalView.plugins,
          onTap: () => onGlobal?.call(HomeGlobalView.plugins),
        ),
        const SizedBox(height: 4),
        _ShortcutRow(
          icon: Icons.hub_outlined,
          label: l10n.teamMcpNav,
          active: activeGlobalView == HomeGlobalView.mcp,
          onTap: () => onGlobal?.call(HomeGlobalView.mcp),
        ),
        const SizedBox(height: 4),
        _ShortcutRow(
          icon: Icons.power_outlined,
          label: l10n.teamExtensionsNav,
          active: activeGlobalView == HomeGlobalView.extensions,
          onTap: () => onGlobal?.call(HomeGlobalView.extensions),
        ),
        const SizedBox(height: 4),
        _ShortcutRow(
          icon: Icons.bolt_outlined,
          label: l10n.teamHooksNav,
          active: activeGlobalView == HomeGlobalView.hooks,
          onTap: () => onGlobal?.call(HomeGlobalView.hooks),
        ),
      ],
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
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);
    final active = widget.active;
    final Color fg = active ? cs.primary : cs.onSurface;
    final idleFill = active ? cs.primary.withValues(alpha: 0.14) : null;
    final hoverFill = active
        ? cs.primary.withValues(alpha: 0.14)
        : cs.onSurface.withValues(alpha: 0.05);

    final labelStyle = active
        ? styles.lgSemiboldColored(fg)
        : styles.lgColored(fg);
    final iconSize = context.tpIconSizeForText(
      labelStyle,
      textBaseAtScale1: AppTypographyScale.bodyLargeBase,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: RepaintBoundary(
        child: TpHover(
        onTap: widget.onTap,
        backgroundColor: idleFill,
        hoverColor: hoverFill,
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
        child: Row(
          children: [
            Icon(
              widget.icon,
              size: iconSize,
              color: active ? cs.primary : cs.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                widget.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: labelStyle,
              ),
            ),
          ],
        ),
        ),
      ),
    );
  }
}

class _ProvidersButton extends StatefulWidget {
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
  State<_ProvidersButton> createState() => _ProvidersButtonState();
}

class _ProvidersButtonState extends State<_ProvidersButton> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);
    final active = widget.active;
    final Color fg = active ? cs.primary : cs.onSurface;
    final restingBg = active
        ? cs.primary.withValues(alpha: 0.14)
        : cs.surfaceContainer;
    final hoverTint = cs.onSurface.withValues(alpha: 0.06);
    final Color borderColor = active
        ? cs.primary.withValues(alpha: 0.45)
        : _hovered
        ? cs.primary.withValues(alpha: 0.35)
        : cs.outlineVariant.withValues(alpha: 0.7);

    final labelStyle = (active ? styles.mdSemibold : styles.md).copyWith(
      color: fg,
    );
    final iconSize = context.tpIconSizeForText(
      labelStyle,
      textBaseAtScale1: AppTypographyScale.bodyMediumBase,
    );

    return TpHover(
      onTap: widget.onTap,
      backgroundColor: restingBg,
      hoverColor: Color.alphaBlend(hoverTint, restingBg),
      onHoverChanged: (hovered) => setState(() => _hovered = hovered),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.memory_outlined,
              size: iconSize,
              color: active ? cs.primary : cs.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Text(
              widget.label,
              style: labelStyle,
            ),
          ],
        ),
      ),
    );
  }
}
