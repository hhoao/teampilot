import 'package:flutter/material.dart';

import '../utils/app_keys.dart';
import '../models/layout_preferences.dart';
import '../theme/app_theme.dart';

enum AppSection { chat, runs, config }

class TabInfo {
  const TabInfo({required this.id, required this.title});

  final String id;
  final String title;
}

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
    this.layoutPreferences = const LayoutPreferences(),
    this.onRightToolsWidthChanged,
    this.rightTools,
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
  final LayoutPreferences layoutPreferences;
  final ValueChanged<double>? onRightToolsWidthChanged;
  final Widget? rightTools;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
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
              color: colors.topbarBackground,
              border: Border(bottom: BorderSide(color: colors.subtleBorder)),
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
                        style: TextStyle(
                          color: textBase.withValues(alpha: 0.52),
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: textBase,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: textBase.withValues(alpha: 0.58),
                          fontSize: 11,
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
            _TabRow(
              tabs: tabs,
              activeIndex: activeTabIndex,
              onTabSelected: onTabSelected,
              onTabClosed: onTabClosed,
              trailing: actions.isNotEmpty
                  ? Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Wrap(spacing: 6, children: actions),
                    )
                  : null,
            ),
          if (tabs.isEmpty && actions.isNotEmpty)
            _ActionsBar(actions: actions),
          Expanded(
            child: _WorkspaceBody(
              preferences: layoutPreferences,
              rightTools: rightTools,
              onRightToolsWidthChanged: onRightToolsWidthChanged,
              child: child,
            ),
          ),
        ],
      );
  }
}

class _WorkspaceBody extends StatelessWidget {
  const _WorkspaceBody({
    required this.preferences,
    required this.child,
    required this.rightTools,
    required this.onRightToolsWidthChanged,
  });

  final LayoutPreferences preferences;
  final Widget child;
  final Widget? rightTools;
  final ValueChanged<double>? onRightToolsWidthChanged;

  @override
  Widget build(BuildContext context) {
    if (rightTools == null) {
      return child;
    }
    if (preferences.toolPlacement == ToolPanelPlacement.bottom) {
      return Column(
        children: [
          Expanded(child: child),
          SizedBox(height: preferences.bottomToolsHeight, child: rightTools),
        ],
      );
    }
    return Row(
      children: [
        Expanded(child: child),
        _RightToolsDivider(
          onDragged: (delta) => onRightToolsWidthChanged?.call(
            preferences.rightToolsWidth - delta.delta.dx,
          ),
        ),
        SizedBox(width: preferences.rightToolsWidth, child: rightTools),
      ],
    );
  }
}

class _RightToolsDivider extends StatelessWidget {
  const _RightToolsDivider({required this.onDragged});

  final ValueChanged<DragUpdateDetails> onDragged;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        key: AppKeys.rightToolsDivider,
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: onDragged,
        child: Container(width: 8, color: colors.topbarBackground),
      ),
    );
  }
}

class _TabRow extends StatelessWidget {
  const _TabRow({
    required this.tabs,
    required this.activeIndex,
    this.onTabSelected,
    this.onTabClosed,
    this.trailing,
  });

  final List<TabInfo> tabs;
  final int activeIndex;
  final ValueChanged<int>? onTabSelected;
  final ValueChanged<int>? onTabClosed;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textBase = isDark ? Colors.white : const Color(0xFF111827);
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: colors.topbarBackground,
        border: Border(bottom: BorderSide(color: colors.subtleBorder)),
      ),
      child: Row(
        children: [
          for (var i = 0; i < tabs.length; i++)
            _TabChip(
              title: tabs[i].title,
              active: i == activeIndex,
              onTap: () => onTabSelected?.call(i),
              onClose: () => onTabClosed?.call(i),
              textColor: textBase,
              activeBg: colors.railButtonSelectedBg,
              borderColor: colors.subtleBorder,
            ),
          if (trailing != null) const Spacer(),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class _TabChip extends StatelessWidget {
  const _TabChip({
    required this.title,
    required this.active,
    required this.onTap,
    required this.onClose,
    required this.textColor,
    required this.activeBg,
    required this.borderColor,
  });

  final String title;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback onClose;
  final Color textColor;
  final Color activeBg;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 2),
      child: Material(
        color: active ? activeBg : Colors.transparent,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
        child: InkWell(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            height: 28,
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(color: active ? borderColor : Colors.transparent),
                right: BorderSide(color: active ? borderColor : Colors.transparent),
                top: BorderSide(color: active ? borderColor : Colors.transparent),
              ),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                  ),
                ),
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: onClose,
                  child: Icon(Icons.close, size: 14, color: textColor.withValues(alpha: 0.5)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionsBar extends StatelessWidget {
  const _ActionsBar({required this.actions});

  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: colors.topbarBackground,
        border: Border(bottom: BorderSide(color: colors.subtleBorder)),
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
