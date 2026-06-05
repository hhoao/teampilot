import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:teampilot/theme/app_icon_sizes.dart';

import '../../l10n/l10n_extensions.dart';
import '../../models/app_project.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/workspace_surface_layers.dart';
import '../../widgets/app_icon_button.dart';
import '../../widgets/menu/sidebar_action_menu.dart';
import 'home_workspace_project_actions.dart';
import 'home_workspace_tab_scope.dart';

/// A single project tile in the workspace home grid: icon, name, session count,
/// and hover actions (new tab, favorite, overflow menu).
class HomeWorkspaceProjectCard extends StatefulWidget {
  const HomeWorkspaceProjectCard({
    required this.project,
    required this.sessionCount,
    required this.favorited,
    required this.onToggleFavorite,
    this.onTap,
    super.key,
  });

  final AppProject project;
  final int sessionCount;
  final bool favorited;
  final Future<void> Function() onToggleFavorite;
  final VoidCallback? onTap;

  @override
  State<HomeWorkspaceProjectCard> createState() =>
      _HomeWorkspaceProjectCardState();
}

class _HomeWorkspaceProjectCardState extends State<HomeWorkspaceProjectCard> {
  var _hovered = false;
  var _menuOpen = false;

  bool get _showActions => _hovered || _menuOpen || Platform.isAndroid;

  void _openInNewTab() {
    HomeWorkspaceTabScope.openInTab(
      context,
      widget.project.projectId,
      activate: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = AppTextStyles.of(context);
    final l10n = context.l10n;
    final project = widget.project;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          padding: const EdgeInsets.all(26),
          decoration:
              workspaceCardDecoration(
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
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          cs.primary.withValues(alpha: 0.85),
                          cs.tertiary.withValues(alpha: 0.85),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(17),
                    ),
                    child: Icon(
                      Icons.auto_stories_rounded,
                      size: AppIconSizes.md,
                      color: cs.onPrimary,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    project.effectiveDisplay,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: styles.prominent.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${widget.sessionCount} ${l10n.homeWorkspaceSessionsLabel}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: styles.bodySmall.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              if (_showActions)
                Positioned(
                  top: 0,
                  right: 0,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AppIconButton(
                        icon: Icons.open_in_new_rounded,
                        tooltip: l10n.homeWorkspaceOpenProjectInNewTab,
                        size: AppIconButton.kCompactSize,
                        iconSize: AppIconButton.kCompactIconSize,
                        onTap: _openInNewTab,
                      ),
                      AppIconButton(
                        icon: widget.favorited
                            ? Icons.star_rounded
                            : Icons.star_outline_rounded,
                        color: widget.favorited ? cs.primary : null,
                        tooltip: widget.favorited
                            ? l10n.homeWorkspaceUnfavoriteProject
                            : l10n.homeWorkspaceFavoriteProject,
                        size: AppIconButton.kCompactSize,
                        iconSize: AppIconButton.kCompactIconSize,
                        onTap: () => unawaited(widget.onToggleFavorite()),
                      ),
                      SizedBox(
                        width: AppIconButton.kCompactSize,
                        height: AppIconButton.kCompactSize,
                        child: SidebarActionMenuIconAnchor(
                          icon: const Icon(
                            Icons.more_horiz,
                            size: AppIconButton.kCompactIconSize,
                          ),
                          onOpen: () => setState(() => _menuOpen = true),
                          onClose: () => setState(() => _menuOpen = false),
                          buildMenuChildren: (context, controller) => [
                            SidebarActionMenuItem(
                              icon: Icons.drive_file_rename_outline,
                              label: l10n.homeWorkspaceRenameProject,
                              menuController: controller,
                              onTap: () => unawaited(
                                showRenameHomeWorkspaceProjectDialog(
                                  context,
                                  project,
                                ),
                              ),
                            ),
                            SidebarActionMenuItem(
                              icon: Icons.copy_all_outlined,
                              label: l10n.homeWorkspaceCloneProject,
                              menuController: controller,
                              onTap: () => unawaited(
                                cloneHomeWorkspaceProject(context, project),
                              ),
                            ),
                            SidebarActionMenuItem(
                              icon: Icons.delete_outline,
                              label: l10n.deleteProject,
                              destructive: true,
                              menuController: controller,
                              onTap: () => unawaited(
                                confirmDeleteHomeWorkspaceProject(
                                  context,
                                  project,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              if (widget.favorited && !_showActions)
                Positioned(
                  top: 0,
                  right: 0,
                  child: Icon(
                    Icons.star_rounded,
                    size: AppIconSizes.sm,
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
