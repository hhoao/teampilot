import 'package:flutter/material.dart';

import '../utils/app_keys.dart';
import '../models/layout_preferences.dart';
import '../theme/app_theme.dart';

class WorkspaceShell extends StatelessWidget {
  const WorkspaceShell({
    required this.breadcrumb,
    required this.title,
    required this.subtitle,
    required this.actions,
    required this.child,
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
  final LayoutPreferences layoutPreferences;
  final ValueChanged<double>? onRightToolsWidthChanged;
  final Widget? rightTools;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textBase = isDark ? Colors.white : const Color(0xFF111827);
    return Expanded(
      child: Column(
        children: [
          Container(
            key: AppKeys.workspaceTopbar,
            height: 82,
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
          Expanded(
            child: _WorkspaceBody(
              preferences: layoutPreferences,
              rightTools: rightTools,
              onRightToolsWidthChanged: onRightToolsWidthChanged,
              child: child,
            ),
          ),
        ],
      ),
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
