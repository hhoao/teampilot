import 'package:flutter/material.dart';

import '../../models/layout_preferences.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/workspace_surface_layers.dart';
import '../../utils/app_keys.dart';
import 'workspace_shell_layout.dart';
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
    this.layoutPreferences = const LayoutPreferences(),
    this.onRightToolsWidthChanged,
    this.rightTools,
    this.showRightToolsVisibilityToggle = false,
    this.childAnimationKey,
    this.workspaceTerminalWorkingDirectory,
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
  final LayoutPreferences layoutPreferences;
  final ValueChanged<double>? onRightToolsWidthChanged;
  final Widget? rightTools;
  final bool showRightToolsVisibilityToggle;
  final Key? childAnimationKey;

  /// When set (e.g. home-v2 project page), the bottom shell terminal follows
  /// this path instead of [ChatCubit.activeTabWorkingDirectory].
  final String? workspaceTerminalWorkingDirectory;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textBase = isDark ? Colors.white : const Color(0xFF111827);
    final textScale = MediaQuery.textScalerOf(context).scale(1.0);
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
                        style: AppTextStyles.of(context).caption.copyWith(
                          color: textBase.withValues(alpha: 0.52),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.of(context).body.copyWith(
                          fontWeight: FontWeight.w800,
                          color: textBase,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.of(context).caption.copyWith(
                          color: textBase.withValues(alpha: 0.58),
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
        if (tabs.isNotEmpty)
          WorkspaceShellTabRow(
            tabs: tabs,
            activeIndex: activeTabIndex,
            onTabSelected: onTabSelected,
            onTabClosed: onTabClosed,
            onTabCloseOthers: onTabCloseOthers,
            onTabCloseRight: onTabCloseRight,
            trailing: WorkspaceShellTabRowTrailing(
              actions: actions.isNotEmpty && showHeader
                  ? Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Wrap(spacing: 6, children: actions),
                    )
                  : null,
              showRightToolsToggle: showRightToolsVisibilityToggle,
            ),
          ),
        if (tabs.isEmpty && actions.isNotEmpty && showHeader)
          WorkspaceShellActionsBar(actions: actions),
        Expanded(
          child: WorkspaceShellMainWithTerminal(
            preferences: layoutPreferences,
            rightTools: rightTools,
            onRightToolsWidthChanged: onRightToolsWidthChanged,
            childAnimationKey: childAnimationKey,
            workspaceTerminalWorkingDirectory:
                workspaceTerminalWorkingDirectory,
            child: child,
          ),
        ),
      ],
    );
  }
}
