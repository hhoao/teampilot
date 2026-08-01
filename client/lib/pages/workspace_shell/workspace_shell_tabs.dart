import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/models/team_config.dart';

import '../../cubits/chat_cubit.dart';
import '../../cubits/layout_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../services/cli/registry/cli_tool_registry_scope.dart';
import '../../theme/workspace_surface_layers.dart';
import '../../utils/session/session_row_content.dart';
import '../../utils/ui/app_keys.dart';
import '../../widgets/cli/cli_brand_icon.dart';
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
    this.onReorder,
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
  final ReorderCallback? onReorder;
  final Widget? newChatButton;
  final Widget? leading;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return TpTabStrip(
      metrics: TpTabStripMetrics.shell,
      showBottomBorder: true,
      itemCount: tabs.length,
      itemKey: (i) => ValueKey(tabs[i].id),
      onReorder: onReorder,
      leading: leading,
      inStripTrailing: newChatButton,
      trailing: trailing,
      itemBuilder: (context, i) {
        final tab = tabs[i];
        return WorkbenchStripTabChip(
          sessionId: tab.sessionId,
          title: tab.title,
          working: tab.working,
          active: activeIndex >= 0 && i == activeIndex,
          preview: tab.preview,
          pinnable: tab.pinnable,
          pinned: tab.pinned,
          onTap: () => onTabSelected?.call(i),
          onClose: () => onTabClosed?.call(i),
          onCloseOthers: () => onTabCloseOthers?.call(i),
          onCloseRight: () => onTabCloseRight?.call(i),
          onPin: tab.pinnable && onTabPin != null
              ? () => onTabPin!(i)
              : null,
          icon: tab.icon,
          cli: tab.cli,
          accentColor: tab.accentColor,
        );
      },
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

/// App-host chip: domain menus / CLI / live session title around [TpTabChip].
class WorkbenchStripTabChip extends StatefulWidget {
  const WorkbenchStripTabChip({
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
  State<WorkbenchStripTabChip> createState() => WorkbenchStripTabChipState();
}

class WorkbenchStripTabChipState extends State<WorkbenchStripTabChip> {
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
    unawaited(_showTabContextMenu(center));
  }

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

    return TpTabChip(
      title: title,
      active: widget.active,
      preview: widget.preview,
      working: working,
      accentColor: widget.accentColor,
      onTap: widget.onTap,
      onClose: widget.onClose,
      onSecondaryTapDown: _showTabContextMenuAtTap,
      onLongPress: defaultTargetPlatform == TargetPlatform.android
          ? _showTabContextMenuAtChipCenter
          : null,
      leading: _WorkbenchStripLeading(cli: widget.cli, icon: widget.icon),
    );
  }
}

class _WorkbenchStripLeading extends StatelessWidget {
  const _WorkbenchStripLeading({required this.cli, required this.icon});

  final CliTool? cli;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final cliTool = cli;
    if (cliTool == null) {
      return Icon(icon, size: context.tpIconSizes.md);
    }
    final registry = CliToolRegistryScope.of(context);
    return CliBrandIcon(
      cli: cliTool,
      definition: registry.tryGet(cliTool),
      size: context.tpIconSizes.md,
      borderRadius: 4,
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
