import 'package:flutter/material.dart';

import '../workbench_tab_menu_context.dart';
import '../workbench_tab_menu_source.dart';

/// Split-group actions for center-strip tab context menus. Produces "Split
/// Right" / "Split Down" entries only when the host supplies the corresponding
/// callback (wide layouts with a splittable group); hosts pass null on narrow
/// viewports or single-tab groups, where a split would be a reducer no-op.
class SplitTabMenuSource implements WorkbenchTabMenuSource {
  const SplitTabMenuSource();

  @override
  List<WorkbenchTabMenuItem> buildItems(WorkbenchTabMenuContext ctx) {
    final items = <WorkbenchTabMenuItem>[];
    if (ctx.onSplitRight != null) {
      items.add(
        WorkbenchTabMenuItem(
          id: 'split.right',
          icon: Icons.vertical_split,
          label: ctx.l10n.tabMenuSplitRight,
          onAction: ctx.onSplitRight!,
        ),
      );
    }
    if (ctx.onSplitDown != null) {
      items.add(
        WorkbenchTabMenuItem(
          id: 'split.down',
          icon: Icons.horizontal_split,
          label: ctx.l10n.tabMenuSplitDown,
          onAction: ctx.onSplitDown!,
        ),
      );
    }
    return items;
  }
}
