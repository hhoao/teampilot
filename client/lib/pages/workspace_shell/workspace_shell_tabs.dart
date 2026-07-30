import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/chat_cubit.dart';
import '../../cubits/layout_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../services/cli/registry/cli_tool_registry_scope.dart';
import '../../theme/workspace_surface_layers.dart';
import '../../utils/ui/app_keys.dart';
import '../../utils/session/session_row_content.dart';
import '../../widgets/tab_close_button.dart';
import '../../widgets/cli/cli_brand_icon.dart';
import '../../widgets/session_working_spinner.dart';
import 'workspace_shell_models.dart';

/// Sidebar + right-tools visibility toggles for the workspace IDE shell.
class WorkspaceShellPaneVisibilityToggles extends StatelessWidget {
  const WorkspaceShellPaneVisibilityToggles({super.key});

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        WorkspaceShellSidebarVisibilityToggle(),
        SizedBox(width: 2),
        WorkspaceShellRightToolsVisibilityToggle(),
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
    final composeLanding = context.select<ChatCubit, bool>(
      (c) => c.state.newChatActive, // chrome is for the active workspace
    );
    return BlocBuilder<LayoutCubit, LayoutState>(
      buildWhen: (a, b) =>
          a.preferences.rightToolsVisible != b.preferences.rightToolsVisible ||
          a.landingRightToolsOverride != b.landingRightToolsOverride,
      builder: (context, state) {
        final visible = composeLanding
            ? (state.landingRightToolsOverride ?? false)
            : state.preferences.rightToolsVisible;
        return TpIconButton(
          key: AppKeys.rightToolsVisibilityButton,
          icon: Icons.vertical_split_outlined,
          tooltip: visible
              ? l10n.rightToolsPanelHidden
              : l10n.rightToolsPanelVisible,
          color: visible ? cs.primary : cs.onSurfaceVariant,
          backgroundColor: Colors.transparent,
          onTap: () => context.read<LayoutCubit>().toggleRightTools(
            composeLanding: composeLanding,
          ),
        );
      },
    );
  }
}

class WorkspaceShellSidebarVisibilityToggle extends StatelessWidget {
  const WorkspaceShellSidebarVisibilityToggle({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    return BlocBuilder<LayoutCubit, LayoutState>(
      buildWhen: (a, b) =>
          a.preferences.sidebarVisible != b.preferences.sidebarVisible ||
          a.narrowLeftSuppressed != b.narrowLeftSuppressed,
      builder: (context, state) {
        final effectiveOpen =
            state.preferences.sidebarVisible && !state.narrowLeftSuppressed;
        return TpIconButton(
          key: AppKeys.sidebarVisibilityButton,
          icon: Icons.view_sidebar_outlined,
          tooltip: effectiveOpen
              ? l10n.sidebarPanelHidden
              : l10n.sidebarPanelVisible,
          color: effectiveOpen ? cs.primary : cs.onSurfaceVariant,
          backgroundColor: Colors.transparent,
          onTap: () {
            final layout = context.read<LayoutCubit>();
            if (effectiveOpen) {
              layout.setSidebarVisible(false);
              layout.clearNarrowLeftSuppressed();
            } else {
              layout.clearNarrowLeftSuppressed();
              layout.setSidebarVisible(true);
            }
          },
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
    this.onTabPin,
    this.newChatButton,
    this.leading,
    this.trailing,
  });

  final List<TabInfo> tabs;
  final int activeIndex;
  final ValueChanged<int>? onTabSelected;
  final ValueChanged<int>? onTabClosed;
  final ValueChanged<int>? onTabCloseOthers;
  final ValueChanged<int>? onTabCloseRight;
  final ValueChanged<int>? onTabPin;
  final Widget? newChatButton;
  final Widget? leading;
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
          if (leading != null) ...[leading!, const SizedBox(width: 2)],
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (var i = 0; i < tabs.length; i++)
                    WorkspaceShellTabChip(
                      key: ValueKey(tabs[i].id),
                      sessionId: tabs[i].sessionId,
                      title: tabs[i].title,
                      working: tabs[i].working,
                      active: activeIndex >= 0 && i == activeIndex,
                      preview: tabs[i].preview,
                      pinnable: tabs[i].pinnable,
                      pinned: tabs[i].pinned,
                      onTap: () => onTabSelected?.call(i),
                      onClose: () => onTabClosed?.call(i),
                      onCloseOthers: () => onTabCloseOthers?.call(i),
                      onCloseRight: () => onTabCloseRight?.call(i),
                      onPin: tabs[i].pinnable && onTabPin != null
                          ? () => onTabPin!(i)
                          : null,
                      icon: tabs[i].icon,
                      cli: tabs[i].cli,
                      accentColor: tabs[i].accentColor,
                    ),
                  if (newChatButton != null) ...[
                    const SizedBox(width: 2),
                    newChatButton!,
                  ],
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

/// "+" action beside session tabs — opens New conversation / New terminal menu.
class WorkspaceShellNewChatButton extends StatefulWidget {
  const WorkspaceShellNewChatButton({
    required this.tooltip,
    required this.newConversationLabel,
    required this.newTerminalLabel,
    this.onNewConversation,
    this.onNewTerminal,
    super.key,
  });

  final String tooltip;
  final String newConversationLabel;
  final String newTerminalLabel;
  final VoidCallback? onNewConversation;

  /// Called with the `+` button anchor when "New terminal" is chosen.
  final void Function(Offset anchor)? onNewTerminal;

  @override
  State<WorkspaceShellNewChatButton> createState() =>
      _WorkspaceShellNewChatButtonState();
}

class _WorkspaceShellNewChatButtonState
    extends State<WorkspaceShellNewChatButton> {
  final _anchorKey = GlobalKey();

  Future<void> _showMenu() async {
    final box = _anchorKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final anchor = box.localToGlobal(box.size.bottomLeft(Offset.zero));
    final selected = await showTpActionMenuFromSpecs<String>(
      context: context,
      globalPosition: anchor + const Offset(0, 4),
      specs: [
        TpActionMenuSpec.item(
          value: 'conversation',
          label: widget.newConversationLabel,
          icon: Icons.chat_bubble_outline_rounded,
        ),
        TpActionMenuSpec.item(
          value: 'terminal',
          label: widget.newTerminalLabel,
          icon: Icons.terminal_rounded,
        ),
      ],
    );
    if (!mounted || selected == null) return;
    switch (selected) {
      case 'conversation':
        widget.onNewConversation?.call();
      case 'terminal':
        widget.onNewTerminal?.call(anchor + const Offset(0, 4));
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled =
        widget.onNewConversation != null || widget.onNewTerminal != null;
    return KeyedSubtree(
      key: _anchorKey,
      child: TpIconButton(
        key: AppKeys.workspaceTabRowNewChatButton,
        icon: Icons.add_rounded,
        tooltip: widget.tooltip,
        compact: true,
        enabled: enabled,
        onTap: enabled ? () => unawaited(_showMenu()) : null,
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
    this.sessionId,
    this.onCloseOthers,
    this.onCloseRight,
    this.onPin,
    this.working = false,
    this.preview = false,
    this.pinnable = false,
    this.pinned = false,
    this.icon = Icons.terminal_rounded,
    this.cli,
    this.accentColor,
  });

  final String title;
  final String? sessionId;
  final bool working;
  final bool active;
  final bool preview;
  final bool pinnable;
  final bool pinned;
  final VoidCallback onTap;
  final VoidCallback onClose;
  final VoidCallback? onCloseOthers;
  final VoidCallback? onCloseRight;
  final VoidCallback? onPin;
  final IconData icon;
  final CliTool? cli;
  final Color? accentColor;

  @override
  State<WorkspaceShellTabChip> createState() => WorkspaceShellTabChipState();
}

class WorkspaceShellTabChipState extends State<WorkspaceShellTabChip> {
  var _hovered = false;

  /// Keeps overflow actions (and [TpActionMenuButton]) mounted while the menu is
  /// open; otherwise moving the pointer onto the overlay triggers
  /// [MouseRegion.onExit] and removes the button before [onSelected] runs.
  final _overflowMenuOpen = false;

  void _handleTabMenuSelection(String value) {
    if (value == 'pin') {
      widget.onPin?.call();
    } else if (value == 'close') {
      widget.onClose();
    } else if (value == 'closeOthers') {
      widget.onCloseOthers?.call();
    } else if (value == 'closeRight') {
      widget.onCloseRight?.call();
    }
  }

  List<TpActionMenuSpec> _tabMenuSpecs(BuildContext menuContext) {
    final l10n = menuContext.l10n;
    return [
      if (widget.pinnable && widget.onPin != null)
        TpActionMenuSpec.item(
          value: 'pin',
          icon: widget.pinned ? Icons.push_pin : Icons.push_pin_outlined,
          label: widget.pinned ? l10n.unpinConversation : l10n.pinConversation,
        ),
      TpActionMenuSpec.item(
        value: 'close',
        icon: Icons.close,
        label: l10n.closeTab,
      ),
      TpActionMenuSpec.item(
        value: 'closeOthers',
        icon: Icons.tab_unselected,
        label: l10n.closeOtherTabs,
      ),
      TpActionMenuSpec.item(
        value: 'closeRight',
        icon: Icons.arrow_forward,
        label: l10n.closeRightTabs,
      ),
    ];
  }

  Future<void> _showTabContextMenuAtTap(TapDownDetails details) async {
    if (!mounted) return;
    final selected = await showTpActionMenuFromSpecsAtTap<String>(
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
    final selected = await showTpActionMenuFromSpecs<String>(
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
    final sessionId = widget.sessionId;
    final working = sessionId == null
        ? widget.working
        : context.select<ChatCubit, bool>(
            (c) => c.state.workingSessionIds.contains(sessionId),
          );
    final title = sessionId == null
        ? widget.title
        : context.select<ChatCubit, String>(
            (c) =>
                SessionRowContent.fromChatState(c.state, sessionId).titleForPaint,
          );
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);
    final active = widget.active;
    final Color fg = active ? cs.onSurface : cs.onSurfaceVariant;
    final Color accent = widget.accentColor ?? cs.primary;
    final double barAlpha = active ? 1.0 : (_hovered ? 0.7 : 0.4);
    final Color barColor = accent.withValues(alpha: barAlpha);
    final double iconAlpha = active ? 1.0 : (_hovered ? 0.9 : 0.8);
    final Color iconColor = accent.withValues(alpha: iconAlpha);

    return Tooltip(
      message: title,
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
          child: Material(
            color: active
                ? cs.surfaceContainerHigh
                : _hovered
                ? cs.onSurface.withValues(alpha: 0.05)
                : Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(
                color: active
                    ? cs.outlineVariant.withValues(alpha: 0.7)
                    : Colors.transparent,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: widget.onTap,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 200),
                child: Padding(
                  padding: const EdgeInsets.only(
                    left: 10,
                    right: 6,
                    top: 6,
                    bottom: 6,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Left accent bar
                      SizedBox(
                        width: 3,
                        height: context.tpIconSizes.md,
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
                      if (working)
                        SessionWorkingIndicator(
                          working: true,
                          size: context.tpIconSizes.sm,
                          color: iconColor,
                        )
                      else
                        _TabChromeSlot(
                          visible: _showChrome,
                          child: _TabLeadingIcon(
                            cli: widget.cli,
                            icon: widget.icon,
                            iconColor: iconColor,
                            iconOpacity: iconAlpha,
                          ),
                        ),
                      const SizedBox(width: 12),
                      // Title
                      Flexible(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: styles.smColored(
                            widget.preview ? fg.withValues(alpha: 0.72) : fg,
                          ),
                        ),
                      ),
                      // Close button
                      _TabChromeSlot(
                        visible: _showChrome,
                        child: TabCloseButton(
                          active: active,
                          onTap: widget.onClose,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TabLeadingIcon extends StatelessWidget {
  const _TabLeadingIcon({
    required this.cli,
    required this.icon,
    required this.iconColor,
    required this.iconOpacity,
  });

  final CliTool? cli;
  final IconData icon;
  final Color iconColor;
  final double iconOpacity;

  @override
  Widget build(BuildContext context) {
    final cliTool = cli;
    if (cliTool == null) {
      return Icon(icon, size: context.tpIconSizes.md, color: iconColor);
    }
    final registry = CliToolRegistryScope.of(context);
    return Opacity(
      opacity: iconOpacity,
      child: CliBrandIcon(
        cli: cliTool,
        definition: registry.tryGet(cliTool),
        size: context.tpIconSizes.md,
        borderRadius: 4,
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
