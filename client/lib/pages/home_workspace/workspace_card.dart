import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:teampilot/theme/app_icon_sizes.dart';

import '../../l10n/l10n_extensions.dart';
import '../../models/app_session.dart';
import '../../models/workspace.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/workspace_surface_layers.dart';
import '../../utils/workspace_display_name.dart';
import '../../widgets/app_icon_button.dart';
import '../../widgets/workspace_icon.dart';
import '../../widgets/menu/sidebar_action_menu.dart';
import 'open_workspace_tab_actions.dart';
import 'workspace_actions.dart';
import 'workspace_card_meta_row.dart';
import 'workspace_card_session_bar.dart';

/// A single workspace tile in the workspace home grid: icon, name, session count,
/// and hover actions (new tab, favorite, overflow menu).
class WorkspaceCard extends StatefulWidget {
  const WorkspaceCard({
    required this.workspace,
    required this.sessionCount,
    required this.favorited,
    required this.onToggleFavorite,
    this.onTap,
    this.displayNameOverride,
    this.showSessionContextIcon = false,
    this.sessions = const [],
    super.key,
  });

  final Workspace workspace;
  final int sessionCount;
  final bool favorited;
  final Future<void> Function() onToggleFavorite;
  final VoidCallback? onTap;
  final String? displayNameOverride;
  final bool showSessionContextIcon;
  final List<AppSession> sessions;

  @override
  State<WorkspaceCard> createState() => _WorkspaceCardState();
}

class _WorkspaceCardState extends State<WorkspaceCard> {
  var _menuOpen = false;

  void _openInNewTab() {
    unawaited(openWorkspace(context, widget.workspace));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = AppTextStyles.of(context);
    final l10n = context.l10n;
    final workspace = widget.workspace;
    final displayName =
        widget.displayNameOverride ?? workspace.localizedName(l10n);

    return _WorkspaceCardHoverShell(
      menuOpen: _menuOpen,
      onTap: widget.onTap,
      onSecondaryTapUp: (details) => unawaited(_showContextMenu(details)),
      showFavoriteBadge: widget.favorited,
      actions: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppIconButton(
            icon: Icons.open_in_new_rounded,
            tooltip: l10n.homeWorkspaceOpenWorkspaceInNewTab,
            size: AppIconButton.kCompactSize,
            compact: true,
            onTap: _openInNewTab,
          ),
          AppIconButton(
            icon: widget.favorited
                ? Icons.star_rounded
                : Icons.star_outline_rounded,
            color: widget.favorited ? cs.primary : null,
            tooltip: widget.favorited
                ? l10n.homeWorkspaceUnfavoriteWorkspace
                : l10n.homeWorkspaceFavoriteWorkspace,
            size: AppIconButton.kCompactSize,
            compact: true,
            onTap: () => unawaited(widget.onToggleFavorite()),
          ),
          SizedBox(
            width: AppIconButton.kCompactSize,
            height: AppIconButton.kCompactSize,
            child: SidebarActionMenuIconAnchor(
              icon: Icon(
                Icons.more_horiz,
                size: context.appIconSizes.sm,
              ),
              onOpen: () => setState(() => _menuOpen = true),
              onClose: () => setState(() => _menuOpen = false),
              buildMenuChildren: (context, controller) => [
                SidebarActionMenuItem(
                  icon: Icons.drive_file_rename_outline,
                  label: l10n.homeWorkspaceRenameWorkspace,
                  menuController: controller,
                  onTap: () => unawaited(
                    showRenameWorkspaceDialog(
                      context,
                      workspace,
                    ),
                  ),
                ),
                SidebarActionMenuItem(
                  icon: Icons.copy_all_outlined,
                  label: l10n.homeWorkspaceCloneWorkspace,
                  menuController: controller,
                  onTap: () => unawaited(
                    cloneWorkspace(context, workspace),
                  ),
                ),
                SidebarActionMenuItem(
                  icon: Icons.delete_outline,
                  label: l10n.deleteWorkspace,
                  destructive: true,
                  menuController: controller,
                  onTap: () => unawaited(
                    confirmDeleteWorkspace(
                      context,
                      workspace,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          WorkspaceIcon.fromWorkspace(workspace),
          const SizedBox(height: 20),
          Text(
            displayName,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: styles.prominent.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          WorkspaceCardMetaRow(
            workspace: workspace,
            showTopologyChip: !widget.showSessionContextIcon,
          ),
          const Spacer(),
          WorkspaceCardSessionBar(
            sessionCount: widget.sessionCount,
            sessionCountLabel: l10n.homeWorkspaceSessionsLabel,
            workspace: workspace,
            showContextIcon: widget.showSessionContextIcon,
          ),
        ],
      ),
    );
  }

  Future<void> _showContextMenu(TapUpDetails details) async {
    final l10n = context.l10n;
    final selected = await showSidebarActionMenuFromSpecsAtTap<String>(
      context: context,
      tapDetails: TapDownDetails(globalPosition: details.globalPosition),
      specs: [
        SidebarActionMenuSpec.item(
          value: 'newTab',
          icon: Icons.open_in_new_rounded,
          label: l10n.homeWorkspaceOpenWorkspaceInNewTab,
        ),
      ],
    );
    if (!mounted || selected == null) return;
    if (selected == 'newTab') _openInNewTab();
  }
}

class _WorkspaceCardHoverShell extends StatefulWidget {
  const _WorkspaceCardHoverShell({
    required this.child,
    required this.actions,
    required this.onTap,
    required this.onSecondaryTapUp,
    required this.menuOpen,
    required this.showFavoriteBadge,
  });

  final Widget child;
  final Widget actions;
  final VoidCallback? onTap;
  final void Function(TapUpDetails details) onSecondaryTapUp;
  final bool menuOpen;
  final bool showFavoriteBadge;

  @override
  State<_WorkspaceCardHoverShell> createState() =>
      _WorkspaceCardHoverShellState();
}

class _WorkspaceCardHoverShellState extends State<_WorkspaceCardHoverShell> {
  var _hovered = false;

  bool get _showActions =>
      _hovered || widget.menuOpen || Platform.isAndroid;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onSecondaryTapUp: widget.onSecondaryTapUp,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          padding: const EdgeInsets.all(26),
          decoration: workspaceCardDecoration(
            cs,
            radius: 14,
            borderAlpha: _hovered ? 1 : 0.7,
          ).copyWith(
            color: cs.workspaceInset,
            border: Border.all(
              color: _hovered
                  ? cs.primary.withValues(alpha: 0.5)
                  : cs.outlineVariant.withValues(alpha: 0.7),
            ),
          ),
          child: Stack(
            children: [
              widget.child,
              if (_showActions)
                Positioned(
                  top: 0,
                  right: 0,
                  child: widget.actions,
                ),
              if (widget.showFavoriteBadge && !_showActions)
                Positioned(
                  top: 0,
                  right: 0,
                  child: Icon(
                    Icons.star_rounded,
                    size: context.appIconSizes.sm,
                    color: cs.primary.withValues(alpha: 0.85),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
