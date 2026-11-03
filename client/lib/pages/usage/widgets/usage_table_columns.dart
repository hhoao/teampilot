import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../l10n/l10n_extensions.dart';
import '../../../models/session_usage_dashboard.dart';
import '../../../models/team_config.dart';
import '../../../widgets/cli/cli_brand_icon.dart';
import '../usage_format.dart';

const String usageGroupColumnId = 'group';
const String usageCliColumnId = 'cli';
const String usageTeamColumnId = 'team';
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
      minWidth: 200,
      maxWidth: 520,
      locked: true,
      hideable: false,
      draggable: false,
      sortValue: (row) => row.label.toLowerCase(),
      tooltip: (row) {
        final cli = groupBy == UsageGroupBy.cli
            ? CliTool.tryParse(row.label)
            : null;
        return cli == null ? usageGroupName(context, row) : usageCliLabel(cli);
      },
      cellBuilder: (context, row) =>
          _GroupCell(row: row, isCliGroup: groupBy == UsageGroupBy.cli),
    ),
    if (groupBy != UsageGroupBy.cli)
      TpTableColumn<UsageGroup>(
        id: usageCliColumnId,
        label: l10n.sessionUsageGroupCli,
        width: 120,
        minWidth: 72,
        maxWidth: 160,
        sortValue: (row) => row.clis.map((cli) => cli.value).join(','),
        tooltip: (row) => row.clis.map(usageCliLabel).join(' · '),
        cellBuilder: (context, row) => _CliCell(row: row),
      ),
    if (groupBy == UsageGroupBy.session || groupBy == UsageGroupBy.member)
      TpTableColumn<UsageGroup>(
        id: usageTeamColumnId,
        label: l10n.workspaceChatLandingModeTeam,
        width: 150,
        minWidth: 90,
        maxWidth: 260,
        sortValue: (row) => row.subtitle.toLowerCase(),
        tooltip: (row) => usageGroupSubtitle(context, row.subtitle),
        cellBuilder: (context, row) => _TeamCell(row: row),
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
      minWidth: 80,
      maxWidth: 200,
      groupStart: true,
      sortValue: (row) => row.costMicroUsd,
      tooltip: (row) => row.pricedEvents == 0
          ? l10n.sessionUsageCostUnpriced
          : '${formatUsageCost(row.costMicroUsd)}'
                '${row.unpricedEvents > 0 ? '*' : ''}',
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
      minWidth: 110,
      maxWidth: 240,
      groupStart: true,
      sortValue: (row) => row.totalTokens,
      tooltip: (row) => formatUsagePercent(
        summary.totalTokens == 0 ? 0 : row.totalTokens / summary.totalTokens,
      ),
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
    minWidth: 64,
    maxWidth: 200,
    sortValue: (row) => value(row),
    tooltip: (row) => '${value(row)}',
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
    final style = TpTextStyles.of(
      context,
    ).md.copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: style,
    );
  }
}

class _GroupCell extends StatelessWidget {
  const _GroupCell({required this.row, required this.isCliGroup});

  final UsageGroup row;
  final bool isCliGroup;

  @override
  Widget build(BuildContext context) {
    final styles = TpTextStyles.of(context);
    final cli = isCliGroup ? CliTool.tryParse(row.label) : null;
    final label = cli == null
        ? usageGroupName(context, row)
        : usageCliLabel(cli);

    return Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: styles.md,
    );
  }
}

class _TeamCell extends StatelessWidget {
  const _TeamCell({required this.row});

  final UsageGroup row;

  @override
  Widget build(BuildContext context) {
    final text = usageGroupSubtitle(context, row.subtitle);
    if (text.isEmpty) return const SizedBox.shrink();
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TpTextStyles.of(context).md,
    );
  }
}

class _CliCell extends StatelessWidget {
  const _CliCell({required this.row});

  final UsageGroup row;

  @override
  Widget build(BuildContext context) {
    if (row.clis.isEmpty) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (index, cli) in row.clis.indexed) ...[
          if (index > 0) const SizedBox(width: 6),
          Tooltip(
            message: usageCliLabel(cli),
            child: CliBrandIcon(
              cli: cli,
              size: context.tpIconSizes.md,
              showBorder: false,
            ),
          ),
        ],
      ],
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
    final style = TpTextStyles.of(
      context,
    ).md.copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
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
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: styles.md.copyWith(
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
