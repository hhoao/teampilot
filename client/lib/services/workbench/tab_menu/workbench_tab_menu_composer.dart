import 'package:shared_ui/shared_ui.dart';

import 'workbench_tab_menu_context.dart';
import 'workbench_tab_menu_source.dart';

/// Merges ordered menu sources into [TpActionMenuSpec]s with group dividers.
abstract final class WorkbenchTabMenuComposer {
  static List<TpActionMenuSpec> compose(
    List<WorkbenchTabMenuSource> sources,
    WorkbenchTabMenuContext ctx,
  ) {
    final groups = <List<WorkbenchTabMenuItem>>[];
    for (final source in sources) {
      final items = source.buildItems(ctx);
      if (items.isNotEmpty) groups.add(items);
    }

    final specs = <TpActionMenuSpec>[];
    for (var i = 0; i < groups.length; i++) {
      if (i > 0) specs.add(const TpActionMenuSpec.divider());
      for (final item in groups[i]) {
        specs.add(
          TpActionMenuSpec.item(
            value: item.id,
            icon: item.icon,
            label: item.label,
            enabled: item.enabled,
            destructive: item.destructive,
            onAction: item.onAction,
          ),
        );
      }
    }
    return specs;
  }
}
