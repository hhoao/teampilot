import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../l10n/l10n_extensions.dart';
import '../../../models/session_usage_dashboard.dart';
import '../../../models/team_config.dart';
import '../usage_format.dart';

const String usageGroupColumnId = 'group';
const String usageTotalColumnId = 'total';

List<TpTableColumn<UsageGroup>> buildUsageTableColumns({
  required BuildContext context,
  required UsageSummary summary,
  required UsageGroupBy groupBy,
}) {
  final l10n = context.l10n;

  return [
    TpTableColumn<UsageGroup>(
      id: usageGroupColumnId,
      label: usageGroupLabel(context, groupBy),
      flex: 3,
      minWidth: 240,
      locked: true,
      hideable: false,
      draggable: false,
      sortValue: (row) => row.label.toLowerCase(),
      cellBuilder: (context, row) => _GroupCell(row: row),
    ),
    _numberColumn(
      id: usageTotalColumnId,
      label: l10n.sessionUsageTotalShort,
      width: 100,
      value: (row) => row.totalTokens,
    ),
    _numberColumn(
      id: 'input',
      label: l10n.sessionUsageInputShort,
      width: 90,
      value: (row) => row.freshInputTokens,
    ),
    _numberColumn(
      id: 'output',
      label: l10n.sessionUsageOutputShort,
      width: 90,
      value: (row) => row.outputTokens,
    ),
    _numberColumn(
      id: 'cache',
      label: l10n.sessionUsageCacheShort,
      width: 100,
      value: (row) => row.cacheReadTokens,
    ),
    TpTableColumn<UsageGroup>(
      id: 'cost',
      label: l10n.sessionUsageCostShort,
      width: 110,
      groupStart: true,
      sortValue: (row) => row.costMicroUsd,
      cellBuilder: (context, row) => _CostCell(row: row),
    ),
    _numberColumn(
      id: 'requests',
      label: l10n.sessionUsageRequestsShort,
      width: 80,
      value: (row) => row.requests,
    ),
    _numberColumn(
      id: 'sessions',
      label: l10n.sessionUsageSessionsShort,
      width: 90,
      value: (row) => row.sessions,
    ),
    TpTableColumn<UsageGroup>(
      id: 'share',
      label: l10n.sessionUsageShareShort,
      width: 120,
      groupStart: true,
      sortValue: (row) => row.totalTokens,
      cellBuilder: (context, row) => _ShareCell(
        totalTokens: row.totalTokens,
        summaryTotal: summary.totalTokens,
      ),
    ),
  ];
}

TpTableColumn<UsageGroup> _numberColumn({
  required String id,
  required String label,
  required double width,
  required int Function(UsageGroup row) value,
}) {
  return TpTableColumn<UsageGroup>(
    id: id,
    label: label,
    width: width,
    sortValue: (row) => value(row),
    cellBuilder: (context, row) =>
        _NumberText(text: formatUsageTokens(value(row))),
  );
}

List<UsageGroup> sortUsageRows(
  List<UsageGroup> rows,
  TpTableSort? sort,
  List<TpTableColumn<UsageGroup>> columns,
) {
  if (sort == null || rows.isEmpty) return rows;
  final column = columns.where((item) => item.id == sort.columnId).firstOrNull;
  final sortValue = column?.sortValue;
  if (sortValue == null) return rows;

  final indexed = rows.indexed.toList(growable: false);
  indexed.sort((a, b) {
    final left = sortValue(a.$2);
    final right = sortValue(b.$2);
    int result;
    if (left == null && right == null) {
      result = 0;
    } else if (left == null) {
      result = 1;
    } else if (right == null) {
      result = -1;
    } else {
      result = left.compareTo(right);
    }
    if (!sort.ascending) result = -result;
    if (result != 0) return result;
    return a.$1.compareTo(b.$1);
  });

  return [for (final entry in indexed) entry.$2];
}

class _NumberText extends StatelessWidget {
  const _NumberText({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final style = TpTextStyles.of(context).sm.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: style);
  }
}

class _GroupCell extends StatelessWidget {
  const _GroupCell({required this.row});

  final UsageGroup row;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);
    final cli = CliTool.tryParse(row.label);
    final label = cli == null ? usageGroupName(context, row) : usageCliLabel(cli);
    final subtitle = usageGroupSubtitle(context, row.subtitle);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: styles.smMedium,
        ),
        const SizedBox(height: 2),
        Wrap(
          spacing: 4,
          runSpacing: 2,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final tool in row.clis)
              if (cli == null) _CliBadge(cli: tool),
            if (subtitle.isNotEmpty)
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: styles.xs.copyWith(
                  color: cs.onSurface.withValues(alpha: 0.5),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _CliBadge extends StatelessWidget {
  const _CliBadge({required this.cli});

  final CliTool cli;

  @override
  Widget build(BuildContext context) {
    final color = usageCliColor(cli);
    final styles = TpTextStyles.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        usageCliLabel(cli),
        style: styles.xs.copyWith(color: color, fontSize: 10),
      ),
    );
  }
}

class _CostCell extends StatelessWidget {
  const _CostCell({required this.row});

  final UsageGroup row;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final text = row.pricedEvents == 0
        ? l10n.sessionUsageCostUnpriced
        : '${formatUsageCost(row.costMicroUsd)}'
              '${row.unpricedEvents > 0 ? '*' : ''}';
    final style = TpTextStyles.of(context).sm.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Text(text, maxLines: 1, style: style);
  }
}

class _ShareCell extends StatelessWidget {
  const _ShareCell({required this.totalTokens, required this.summaryTotal});

  final int totalTokens;
  final int summaryTotal;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);
    final share = summaryTotal == 0 ? 0.0 : totalTokens / summaryTotal;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          formatUsagePercent(share),
          style: styles.smMedium.copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: share,
            minHeight: 4,
            backgroundColor: cs.surfaceContainerHighest,
            valueColor: AlwaysStoppedAnimation(cs.primary),
          ),
        ),
      ],
    );
  }
}
