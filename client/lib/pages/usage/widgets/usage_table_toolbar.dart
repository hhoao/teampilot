import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../l10n/l10n_extensions.dart';
import '../../../models/session_usage_dashboard.dart';
import '../../../utils/ui/app_keys.dart';
import '../usage_format.dart';

class UsageTableToolbar extends StatelessWidget {
  const UsageTableToolbar({
    required this.groupBy,
    required this.groupLabel,
    required this.count,
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
  final String groupLabel;
  final int count;
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

    final search = TextField(
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
    );

    final groupControls = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(context.l10n.sessionUsageGroupCount(count), style: styles.mdBold),
        const SizedBox(height: 2),
        Text(
          '${context.l10n.sessionUsageGroupBy} · $groupLabel',
          style: styles.xs.copyWith(
            color: cs.onSurface.withValues(alpha: 0.56),
          ),
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: TpSegmentedControl(
            totalSwitches: UsageGroupBy.values.length,
            initialLabelIndex: UsageGroupBy.values.indexOf(groupBy),
            labels: [
              for (final group in UsageGroupBy.values)
                usageGroupLabel(context, group),
            ],
            variant: TpSegmentedControlVariant.outlined,
            minHeight: 28,
            onToggle: (index) {
              if (index == null) return;
              onGroupByChanged(UsageGroupBy.values[index]);
            },
          ),
        ),
      ],
    );

    final columnMenu = TpTableColumnMenu<UsageGroup>(
      columns: columns,
      state: tableState,
      onChanged: onTableStateChanged,
      labels: labels,
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
          crossAxisAlignment: CrossAxisAlignment.end,
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
