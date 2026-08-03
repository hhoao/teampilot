import 'package:flutter/material.dart';

import 'workbench_tab_menu_context.dart';

/// One actionable row in a tab context menu group.
class WorkbenchTabMenuItem {
  const WorkbenchTabMenuItem({
    required this.id,
    required this.icon,
    required this.label,
    this.enabled = true,
    this.destructive = false,
    required this.onAction,
  });

  final String id;
  final IconData icon;
  final String label;
  final bool enabled;
  final bool destructive;
  final VoidCallback onAction;
}

/// Contributes one menu group for a workbench tab context menu.
abstract class WorkbenchTabMenuSource {
  /// Returns items for this group, or empty to omit the group.
  List<WorkbenchTabMenuItem> buildItems(WorkbenchTabMenuContext ctx);
}
