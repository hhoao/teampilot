import 'dart:io';

import 'package:flutter/material.dart';
import 'package:teampilot/theme/app_icon_sizes.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/layout_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/layout_preferences.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/workspace_surface_layers.dart';
import '../../utils/app_keys.dart';
import '../../widgets/app_icon_button.dart';
import '../../widgets/menu/sidebar_action_menu.dart';
import '../../widgets/session_working_spinner.dart';
import 'workspace_shell_models.dart';

class WorkspaceShellTabRowTrailing extends StatelessWidget {
  const WorkspaceShellTabRowTrailing({super.key, 
    this.actions,
    required this.showRightToolsToggle,
  });

  final Widget? actions;
  final bool showRightToolsToggle;

  @override
  Widget build(BuildContext context) {
    if (actions == null && !showRightToolsToggle) {
      return const SizedBox.shrink();
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (actions != null) actions!,
        if (showRightToolsToggle) ...[
          if (actions != null) const SizedBox(width: 4),
          const WorkspaceShellRightToolsVisibilityToggle(),
        ],
      ],
    );
  }
}

class WorkspaceShellRightToolsVisibilityToggle extends StatelessWidget {
  const WorkspaceShellRightToolsVisibilityToggle({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    return BlocBuilder<LayoutCubit, LayoutState>(
      builder: (context, state) {
        final prefs = state.preferences;
        final visible = prefs.rightToolsVisible;
        final icon = prefs.toolPlacement == ToolPanelPlacement.bottom
            ? Icons.splitscreen_outlined
            : Icons.vertical_split_outlined;
        return AppIconButton(
          key: AppKeys.rightToolsVisibilityButton,
          icon: icon,
          tooltip: visible
              ? l10n.rightToolsPanelHidden
              : l10n.rightToolsPanelVisible,
          color: visible ? cs.primary : cs.onSurfaceVariant,
          backgroundColor: visible
              ? cs.primaryContainer.withValues(alpha: 0.45)
              : Colors.transparent,
          onTap: () =>
              context.read<LayoutCubit>().setRightToolsVisible(!visible),
        );
      },
    );
  }
}

class WorkspaceShellTabRow extends StatelessWidget {
  const WorkspaceShellTabRow({super.key, 
    required this.tabs,
    required this.activeIndex,
    this.onTabSelected,
    this.onTabClosed,
    this.onTabCloseOthers,
    this.onTabCloseRight,
    this.trailing,
  });

  final List<TabInfo> tabs;
  final int activeIndex;
  final ValueChanged<int>? onTabSelected;
  final ValueChanged<int>? onTabClosed;
  final ValueChanged<int>? onTabCloseOthers;
  final ValueChanged<int>? onTabCloseRight;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textBase = isDark ? Colors.white : const Color(0xFF111827);
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (var i = 0; i < tabs.length; i++)
                    WorkspaceShellTabChip(
                      title: tabs[i].title,
                      working: tabs[i].working,
                      active: i == activeIndex,
                      onTap: () => onTabSelected?.call(i),
                      onClose: () => onTabClosed?.call(i),
                      onCloseOthers: () => onTabCloseOthers?.call(i),
                      onCloseRight: () => onTabCloseRight?.call(i),
                      textColor: textBase,
                      activeBg: cs.surfaceContainerHighest,
                      borderColor: cs.outlineVariant.withValues(alpha: 0.5),
                    ),
                ],
              ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class WorkspaceShellTabChip extends StatefulWidget {
  const WorkspaceShellTabChip({super.key,
    required this.title,
    required this.active,
    required this.onTap,
    required this.onClose,
    this.onCloseOthers,
    this.onCloseRight,
    required this.textColor,
    required this.activeBg,
    required this.borderColor,
    this.working = false,
  });

  final String title;
  final bool working;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback onClose;
  final VoidCallback? onCloseOthers;
  final VoidCallback? onCloseRight;
  final Color textColor;
  final Color activeBg;
  final Color borderColor;

  @override
  State<WorkspaceShellTabChip> createState() => WorkspaceShellTabChipState();
}

class WorkspaceShellTabChipState extends State<WorkspaceShellTabChip> {
  var _hovered = false;

  /// Keeps overflow actions (and [SidebarActionMenuButton]) mounted while the menu is
  /// open; otherwise moving the pointer onto the overlay triggers
  /// [MouseRegion.onExit] and removes the button before [onSelected] runs.
  var _overflowMenuOpen = false;

  void _handleTabMenuSelection(String value) {
    if (value == 'close') {
      widget.onClose();
    } else if (value == 'closeOthers') {
      widget.onCloseOthers?.call();
    } else if (value == 'closeRight') {
      widget.onCloseRight?.call();
    }
  }

  List<SidebarActionMenuSpec> _tabMenuSpecs(BuildContext menuContext) {
    final l10n = menuContext.l10n;
    return [
      SidebarActionMenuSpec.item(
        value: 'close',
        icon: Icons.close,
        label: l10n.closeTab,
      ),
      SidebarActionMenuSpec.item(
        value: 'closeOthers',
        icon: Icons.tab_unselected,
        label: l10n.closeOtherTabs,
      ),
      SidebarActionMenuSpec.item(
        value: 'closeRight',
        icon: Icons.arrow_forward,
        label: l10n.closeRightTabs,
      ),
    ];
  }

  Future<void> _showTabContextMenuAtTap(TapDownDetails details) async {
    if (!mounted) return;
    final selected = await showSidebarActionMenuFromSpecsAtTap<String>(
      context: context,
      tapDetails: details,
      specs: _tabMenuSpecs(context),
    );
    if (!mounted || selected == null) return;
    _handleTabMenuSelection(selected);
  }

  void _showTabContextMenuFromTap(TapDownDetails details) {
    _showTabContextMenuAtTap(details);
  }

  Future<void> _showTabContextMenu(Offset globalPosition) async {
    if (!mounted) return;
    final selected = await showSidebarActionMenuFromSpecs<String>(
      context: context,
      globalPosition: globalPosition,
      specs: _tabMenuSpecs(context),
    );
    if (!mounted || selected == null) return;
    _handleTabMenuSelection(selected);
  }

  void _showTabContextMenuAtChipCenter() {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    final center = box.localToGlobal(
      Offset(box.size.width / 2, box.size.height / 2),
    );
    _showTabContextMenu(center);
  }

  /// Touch platforms have no hover; keep tab actions visible on Android.
  bool get _showTabActions =>
      _hovered || _overflowMenuOpen || Platform.isAndroid;

  /// Whole-tab hover from [MouseRegion]. Avoids [InkWell] + nested
  /// overflow menu ink fighting (hover patch only behind title text).
  Color _tabMaterialColor(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hoverTint = Theme.of(
      context,
    ).colorScheme.onSurface.withValues(alpha: 0.10);
    if (widget.active) {
      return _hovered
          ? Color.alphaBlend(hoverTint, widget.activeBg)
          : widget.activeBg;
    }
    if (_hovered) {
      return Color.alphaBlend(hoverTint, cs.workspaceCard);
    }
    return Colors.transparent;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 2),
      child: Tooltip(
        message: widget.title,
        child: MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: Material(
            color: _tabMaterialColor(context),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onTap,
              onSecondaryTapDown: _showTabContextMenuFromTap,
              onLongPress: Platform.isAndroid
                  ? _showTabContextMenuAtChipCenter
                  : null,
              child: Container(
                width: 200,
                padding: const EdgeInsets.only(left: 12, right: 12),
                height: 38,
                decoration: BoxDecoration(
                  border: Border(
                    left: BorderSide(
                      color: widget.active
                          ? widget.borderColor
                          : Colors.transparent,
                    ),
                    right: BorderSide(
                      color: widget.active
                          ? widget.borderColor
                          : Colors.transparent,
                    ),
                    top: BorderSide(
                      color: widget.active
                          ? widget.borderColor
                          : Colors.transparent,
                    ),
                  ),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(10),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.max,
                  children: [
                    SessionWorkingIndicator(working: widget.working, size: 13),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          widget.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.of(context).body,
                        ),
                      ),
                    ),
                    if (_showTabActions) ...[
                      const SizedBox(width: 4),
                      SidebarActionMenuButton(
                        icon: Icon(
                          Icons.more_horiz,
                          size: AppIconSizes.md,
                          color: widget.textColor.withValues(alpha: 0.6),
                        ),
                        size: 32,
                        onOpen: () => setState(() => _overflowMenuOpen = true),
                        onClose: () =>
                            setState(() => _overflowMenuOpen = false),
                        specs: _tabMenuSpecs(context),
                        onSelected: (value) {
                          setState(() => _overflowMenuOpen = false);
                          _handleTabMenuSelection(value as String);
                        },
                      ),
                      GestureDetector(
                        onTap: widget.onClose,
                        child: Icon(
                          Icons.close,
                          size: AppIconSizes.md,
                          color: widget.textColor.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class WorkspaceShellActionsBar extends StatelessWidget {
  const WorkspaceShellActionsBar({super.key, required this.actions});

  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: cs.workspaceCard,
        border: Border(
          bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
        ),
      ),
      child: Row(
        children: [
          const Spacer(),
          Wrap(spacing: 6, children: actions),
        ],
      ),
    );
  }
}
