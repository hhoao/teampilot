import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../theme/app_spacing.dart';
import '../../theme/workspace_surface_layers.dart';
import '../../utils/ui/app_keys.dart';
import 'workspace_shell_models.dart';
import 'workspace_shell_tabs.dart';

export 'workspace_shell_models.dart';

class WorkspaceShell extends StatelessWidget {
  const WorkspaceShell({
    required this.breadcrumb,
    required this.title,
    required this.subtitle,
    required this.actions,
    required this.child,
    this.showHeader = true,
    this.tabs = const [],
    this.activeTabIndex = 0,
    this.onTabSelected,
    this.onTabClosed,
    this.onTabCloseOthers,
    this.onTabCloseRight,
    this.onTabPin,
    this.onTabsReorder,
    this.showNewChatButton = false,
    this.newChatTooltip = '',
    this.newConversationLabel = '',
    this.newTerminalLabel = '',
    this.onNewConversation,
    this.onNewTerminal,
    this.tabBarTrailing,
    super.key,
  });

  final String breadcrumb;
  final String title;
  final String subtitle;
  final List<Widget> actions;
  final Widget child;
  final bool showHeader;
  final List<TabInfo> tabs;
  final int activeTabIndex;
  final ValueChanged<int>? onTabSelected;
  final ValueChanged<int>? onTabClosed;
  final ValueChanged<int>? onTabCloseOthers;
  final ValueChanged<int>? onTabCloseRight;
  final ValueChanged<int>? onTabPin;

  /// Material [ReorderableListView.onReorder] for the center strip.
  final ReorderCallback? onTabsReorder;

  /// "+" action at the end of the session tab row — New conversation / terminal.
  final bool showNewChatButton;
  final String newChatTooltip;
  final String newConversationLabel;
  final String newTerminalLabel;
  final VoidCallback? onNewConversation;
  final void Function(Offset anchor)? onNewTerminal;

  /// Extra controls on the right of the tab row (e.g. Chat/Terminal toggle).
  final Widget? tabBarTrailing;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textBase = cs.onSurface;
    final textScale = context.uiScale;
    return Column(
      children: [
        if (showHeader)
          Container(
            key: AppKeys.workspaceTopbar,
            height: 82.0 * textScale,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: cs.workspaceCard,
              border: Border(
                bottom: BorderSide(
                  color: cs.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        breadcrumb,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TpTextStyles.of(context).xsColored(textBase.withValues(alpha: 0.52),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TpTextStyles.of(context).mdBoldColored(textBase,),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TpTextStyles.of(context).xsColored(textBase.withValues(alpha: 0.58),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Flexible(
                  flex: 0,
                  child: Wrap(spacing: 8, runSpacing: 8, children: actions),
                ),
              ],
            ),
          ),
        if (tabs.isNotEmpty || showNewChatButton)
          WorkspaceShellTabRow(
            tabs: tabs,
            activeIndex: activeTabIndex,
            onTabSelected: onTabSelected,
            onTabClosed: onTabClosed,
            onTabCloseOthers: onTabCloseOthers,
            onTabCloseRight: onTabCloseRight,
            onTabPin: onTabPin,
            onReorder: onTabsReorder,
            newChatButton: showNewChatButton
                ? WorkspaceShellNewChatButton(
                    tooltip: newChatTooltip,
                    newConversationLabel: newConversationLabel,
                    newTerminalLabel: newTerminalLabel,
                    onNewConversation: onNewConversation,
                    onNewTerminal: onNewTerminal,
                  )
                : null,
            trailing: tabBarTrailing ??
                (actions.isNotEmpty && showHeader
                    ? Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Wrap(spacing: 6, children: actions),
                      )
                    : null),
          ),
        if (tabs.isEmpty && !showNewChatButton && actions.isNotEmpty && showHeader)
          WorkspaceShellActionsBar(actions: actions),
        Expanded(child: child),
      ],
    );
  }
}
