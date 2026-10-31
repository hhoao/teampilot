import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../l10n/l10n_extensions.dart';
import '../../../models/session_usage_dashboard.dart';
import '../../../utils/ui/app_keys.dart';
import '../usage_format.dart';

class UsageTableToolbar extends StatelessWidget {
  const UsageTableToolbar({
    required this.groupBy,
    required this.searchController,
    required this.onQueryChanged,
    required this.onGroupByChanged,
    required this.columns,
    required this.tableState,
    required this.onTableStateChanged,
    required this.labels,
    super.key,
  });

  final UsageGroupBy groupBy;
  final TextEditingController searchController;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<UsageGroupBy> onGroupByChanged;
  final List<TpTableColumn<UsageGroup>> columns;
  final TpTableState tableState;
  final ValueChanged<TpTableState> onTableStateChanged;
  final TpDataTableLabels labels;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);

    final search = SizedBox(
      height: usageFilterControlHeight,
      child: TextField(
        key: AppKeys.sessionUsageSearchField,
        controller: searchController,
        onChanged: onQueryChanged,
        style: styles.sm,
        decoration: InputDecoration(
          isDense: true,
          hintText: context.l10n.sessionUsageSearchHint,
          prefixIcon: const Icon(Icons.search, size: 18),
          suffixIcon: searchController.text.isEmpty
              ? null
              : IconButton(
                  tooltip: context.l10n.sessionUsageResetFilters,
                  iconSize: 18,
                  onPressed: () {
                    searchController.clear();
                    onQueryChanged('');
                  },
                  icon: const Icon(Icons.close),
                ),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(9)),
        ),
      ),
    );

    final groupControls = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: TpSegmentedControl(
        totalSwitches: UsageGroupBy.values.length,
        initialLabelIndex: UsageGroupBy.values.indexOf(groupBy),
        labels: [
          for (final group in UsageGroupBy.values)
            usageGroupLabel(context, group),
        ],
        variant: TpSegmentedControlVariant.outlined,
        minHeight: usageFilterControlHeight,
        onToggle: (index) {
          if (index == null) return;
          onGroupByChanged(UsageGroupBy.values[index]);
        },
      ),
    );

    final columnMenu = Container(
      width: usageFilterControlHeight,
      height: usageFilterControlHeight,
      decoration: BoxDecoration(
        border: Border.all(color: cs.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: TpTableColumnMenu<UsageGroup>(
          columns: columns,
          state: tableState,
          onChanged: onTableStateChanged,
          labels: labels,
        ),
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 720) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              groupControls,
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: search),
                  const SizedBox(width: 8),
                  columnMenu,
                ],
              ),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: groupControls),
            const SizedBox(width: 12),
            SizedBox(width: 240, child: search),
            const SizedBox(width: 8),
            columnMenu,
          ],
        );
      },
    );
  }
}
