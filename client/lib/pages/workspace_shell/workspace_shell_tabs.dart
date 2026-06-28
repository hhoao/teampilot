import 'dart:io';

import 'package:flutter/material.dart';
import 'package:teampilot/theme/app_icon_sizes.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/layout_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/workspace_surface_layers.dart';
import '../../utils/app_keys.dart';
import '../../widgets/app_icon_button.dart';
import '../../widgets/menu/sidebar_action_menu.dart';
import '../../widgets/session_working_spinner.dart';
import 'workspace_shell_models.dart';

class WorkspaceShellTabRowTrailing extends StatelessWidget {
  const WorkspaceShellTabRowTrailing({
    super.key,
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
        return AppIconButton(
          key: AppKeys.rightToolsVisibilityButton,
          icon: Icons.vertical_split_outlined,
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
  const WorkspaceShellTabRow({
    super.key,
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
    return Container(
      height: 40,
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
                      key: ValueKey(tabs[i].id),
                      title: tabs[i].title,
                      working: tabs[i].working,
                      active: i == activeIndex,
                      onTap: () => onTabSelected?.call(i),
                      onClose: () => onTabClosed?.call(i),
                      onCloseOthers: () => onTabCloseOthers?.call(i),
                      onCloseRight: () => onTabCloseRight?.call(i),
                      icon: tabs[i].icon,
                      accentColor: tabs[i].accentColor,
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
  const WorkspaceShellTabChip({
    super.key,
    required this.title,
    required this.active,
    required this.onTap,
    required this.onClose,
    this.onCloseOthers,
    this.onCloseRight,
    this.working = false,
    this.icon = Icons.terminal_rounded,
    this.accentColor,
  });

  final String title;
  final bool working;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback onClose;
  final VoidCallback? onCloseOthers;
  final VoidCallback? onCloseRight;
  final IconData icon;
  final Color? accentColor;

  @override
  State<WorkspaceShellTabChip> createState() => WorkspaceShellTabChipState();
}

class WorkspaceShellTabChipState extends State<WorkspaceShellTabChip> {
  var _hovered = false;

  /// Keeps overflow actions (and [SidebarActionMenuButton]) mounted while the menu is
  /// open; otherwise moving the pointer onto the overlay triggers
  /// [MouseRegion.onExit] and removes the button before [onSelected] runs.
  final _overflowMenuOpen = false;

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

  /// Touch platforms have no hover; keep tab chrome visible on Android.
  bool get _showChrome =>
      widget.active || _hovered || _overflowMenuOpen || Platform.isAndroid;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = AppTextStyles.of(context);
    final active = widget.active;
    final Color fg = active ? cs.onSurface : cs.onSurfaceVariant;
    final Color accent = widget.accentColor ?? cs.primary;
    final double barAlpha = active ? 1.0 : (_hovered ? 0.7 : 0.4);
    final Color barColor = accent.withValues(alpha: barAlpha);
    final double iconAlpha = active ? 1.0 : (_hovered ? 0.9 : 0.8);
    final Color iconColor = accent.withValues(alpha: iconAlpha);

    return Tooltip(
      message: widget.title,
      waitDuration: const Duration(milliseconds: 500),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          onSecondaryTapDown: _showTabContextMenuFromTap,
          onLongPress: Platform.isAndroid
              ? _showTabContextMenuAtChipCenter
              : null,
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 200),
              padding: const EdgeInsets.only(
                left: 10,
                right: 6,
                top: 6,
                bottom: 6,
              ),
              decoration: BoxDecoration(
                color: active
                    ? cs.surfaceContainerHigh
                    : _hovered
                    ? cs.onSurface.withValues(alpha: 0.05)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: active
                      ? cs.outlineVariant.withValues(alpha: 0.7)
                      : Colors.transparent,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Left accent bar
                  SizedBox(
                    width: 3,
                    height: context.appIconSizes.md,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: barColor,
                        borderRadius: BorderRadius.circular(1.5),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Working indicator always visible when working;
                  // icon fades with chrome when idle.
                  if (widget.working)
                    SessionWorkingIndicator(
                      working: true,
                      size: context.appIconSizes.md,
                      color: iconColor,
                    )
                  else
                    _TabChromeSlot(
                      visible: _showChrome,
                      child: Icon(
                        widget.icon,
                        size: context.appIconSizes.md,
                        color: iconColor,
                      ),
                    ),
                  const SizedBox(width: 12),
                  // Title
                  Flexible(
                    child: Text(
                      widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: styles.bodySmall.copyWith(color: fg),
                    ),
                  ),
                  // Close button
                  _TabChromeSlot(
                    visible: _showChrome,
                    child: InkWell(
                      onTap: widget.onClose,
                      borderRadius: BorderRadius.circular(5),
                      child: Padding(
                        padding: const EdgeInsets.all(2),
                        child: Icon(
                          Icons.close,
                          size: context.appIconSizes.md,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Keeps tab chrome in the layout while hiding it visually until hover/active.
class _TabChromeSlot extends StatelessWidget {
  const _TabChromeSlot({required this.visible, required this.child});

  final bool visible;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: child,
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
