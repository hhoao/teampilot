import 'package:flutter/material.dart';
import 'package:panes/src/pane_theme.dart';

/// Builder function for creating the content of a tab.
typedef TabContentBuilder = Widget Function(BuildContext context, int index);

/// A pane capable of displaying a header with tabs and action buttons.
class TabbedPane extends StatelessWidget {
  /// Optional list of icons for each tab.
  final List<IconData>? icons;

  /// List of text labels for each tab.
  final List<String> labels;

  /// The index of the currently selected tab.
  final int selectedIndex;

  /// Callback when a tab is selected.
  final ValueChanged<int> onTabSelected;

  /// The builder used to create the content for the selected tab.
  final TabContentBuilder tabBuilder;

  /// Optional list of widget actions to display in the header (e.g., icons).
  final List<Widget>? actions;

  /// Creates a [TabbedPane].
  const TabbedPane({
    super.key,
    this.icons,
    required this.labels,
    required this.selectedIndex,
    required this.onTabSelected,
    required this.tabBuilder,
    this.actions,
  }) : assert(icons == null || icons.length == labels.length);

  @override
  Widget build(BuildContext context) {
    final theme = PaneTheme.of(context);

    return Column(
      children: [
        Container(
          height: 32,
          color: theme.tabHeaderColor ?? Colors.grey[200],
          child: Row(
            children: [
              for (int i = 0; i < labels.length; i++) _buildTab(i, theme),
              const Spacer(),
              ...?actions,
            ],
          ),
        ),
        Expanded(child: tabBuilder(context, selectedIndex)),
      ],
    );
  }

  Widget _buildTab(int index, PaneThemeData theme) {
    bool isSelected = index == selectedIndex;

    final bg = isSelected
        ? (theme.tabSelectedBackground ?? Colors.white)
        : (theme.tabBackground ?? Colors.transparent);

    final labelColor = isSelected
        ? (theme.tabSelectedLabelColor ?? Colors.black87)
        : (theme.tabLabelColor ?? Colors.black54);

    return GestureDetector(
      onTap: () => onTabSelected(index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        color: bg,
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icons case final icons?) ...[
              Icon(
                icons[index],
                size: 14,
                color: labelColor,
              ),
              const SizedBox(width: 6),
            ],
            Text(
              labels[index],
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
                color: labelColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
