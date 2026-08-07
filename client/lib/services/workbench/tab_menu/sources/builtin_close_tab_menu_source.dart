import 'package:flutter/material.dart';

import '../workbench_tab_menu_context.dart';
import '../workbench_tab_menu_source.dart';

/// Pin + close actions — always the last menu group.
class BuiltinCloseTabMenuSource implements WorkbenchTabMenuSource {
  const BuiltinCloseTabMenuSource();

  @override
  List<WorkbenchTabMenuItem> buildItems(WorkbenchTabMenuContext ctx) {
    final l10n = ctx.l10n;
    final items = <WorkbenchTabMenuItem>[];

    if (ctx.pinnable && ctx.onPin != null) {
      items.add(
        WorkbenchTabMenuItem(
          id: 'builtin.pin',
          icon: ctx.pinned ? Icons.push_pin : Icons.push_pin_outlined,
          label: ctx.pinned ? l10n.unpinConversation : l10n.pinConversation,
          onAction: ctx.onPin!,
        ),
      );
    }

    items.add(
      WorkbenchTabMenuItem(
        id: 'builtin.close',
        icon: Icons.close,
        label: l10n.closeTab,
        onAction: ctx.onClose,
      ),
    );

    if (ctx.onCloseOthers != null) {
      items.add(
        WorkbenchTabMenuItem(
          id: 'builtin.close_others',
          icon: Icons.tab_unselected,
          label: l10n.closeOtherTabs,
          onAction: ctx.onCloseOthers!,
        ),
      );
    }

    if (ctx.onCloseRight != null) {
      items.add(
        WorkbenchTabMenuItem(
          id: 'builtin.close_right',
          icon: Icons.arrow_forward,
          label: l10n.closeRightTabs,
          onAction: ctx.onCloseRight!,
        ),
      );
    }

    if (ctx.onCloseAll != null) {
      items.add(
        WorkbenchTabMenuItem(
          id: 'builtin.close_all',
          icon: Icons.select_all,
          label: l10n.closeAllTabs,
          onAction: ctx.onCloseAll!,
        ),
      );
    }

    return items;
  }
}
