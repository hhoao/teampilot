import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../l10n/l10n_extensions.dart';
import '../../../models/session_usage_dashboard.dart';
import '../../../models/team_config.dart';
import '../../../theme/workspace_surface_layers.dart';
import '../../../utils/ui/app_keys.dart';
import '../usage_format.dart';

class UsageDetailTable extends StatelessWidget {
  const UsageDetailTable({
    required this.dashboard,
    required this.groupBy,
    required this.searchController,
    required this.onQueryChanged,
    required this.onResetFilters,
    super.key,
  });

  final UsageDashboard dashboard;
  final UsageGroupBy groupBy;
  final TextEditingController searchController;
  final ValueChanged<String> onQueryChanged;
  final VoidCallback onResetFilters;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);
    final groupLabel = usageGroupLabel(context, groupBy);

    return Container(
      key: AppKeys.sessionUsageTable,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      decoration: workspaceCardDecoration(
        cs,
        radius: 14,
      ).copyWith(color: cs.workspaceCard),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.sessionUsageGroupCount(dashboard.rows.length),
                    style: styles.mdBold,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${l10n.sessionUsageGroupBy} · $groupLabel',
                    style: styles.xs.copyWith(
                      color: cs.onSurface.withValues(alpha: 0.56),
                    ),
                  ),
                ],
              ),
              SizedBox(
                width: 240,
                child: TextField(
                  key: AppKeys.sessionUsageSearchField,
                  controller: searchController,
                  onChanged: onQueryChanged,
                  style: styles.sm,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: l10n.sessionUsageSearchHint,
                    prefixIcon: const Icon(Icons.search, size: 18),
                    suffixIcon: searchController.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: l10n.sessionUsageResetFilters,
                            iconSize: 18,
                            onPressed: () {
                              searchController.clear();
                              onQueryChanged('');
                            },
                            icon: const Icon(Icons.close),
                          ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(9),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Divider(color: cs.outlineVariant.withValues(alpha: 0.5), height: 1),
          if (dashboard.rows.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 26),
              child: Column(
                children: [
                  Text(l10n.sessionUsageTableEmpty, style: styles.smMedium),
                  const SizedBox(height: 4),
                  Text(
                    l10n.sessionUsageTableEmptyHint,
                    style: styles.xs.copyWith(
                      color: cs.onSurface.withValues(alpha: 0.56),
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: onResetFilters,
                    child: Text(l10n.sessionUsageResetFilters),
                  ),
                ],
              ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth < 1000
                    ? 1000.0
                    : constraints.maxWidth;
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: width,
                    child: Column(
                      children: [
                        _HeaderRow(groupLabel: groupLabel),
                        for (final row in dashboard.rows)
                          _UsageRow(
                            row: row,
                            groupBy: groupBy,
                            summary: dashboard.summary,
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

class _HeaderRow extends StatelessWidget {
  const _HeaderRow({required this.groupLabel});

  final String groupLabel;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final styles = TpTextStyles.of(context);
    final cs = Theme.of(context).colorScheme;
    final style = styles.xs.copyWith(
      color: cs.onSurface.withValues(alpha: 0.5),
      fontWeight: FontWeight.w600,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          Expanded(child: Text(groupLabel, style: style)),
          _headerCell(l10n.sessionUsageTotalShort, 90, style),
          _headerCell(l10n.sessionUsageInputShort, 80, style),
          _headerCell(l10n.sessionUsageOutputShort, 80, style),
          _headerCell(l10n.sessionUsageCacheShort, 90, style),
          _headerCell(l10n.sessionUsageCostShort, 100, style),
          _headerCell(l10n.sessionUsageRequestsShort, 70, style),
          _headerCell(l10n.sessionUsageSessionsShort, 70, style),
          _headerCell(l10n.sessionUsageShareShort, 120, style),
        ],
      ),
    );
  }

  Widget _headerCell(String text, double width, TextStyle style) {
    return SizedBox(
      width: width,
      child: Text(text, textAlign: TextAlign.end, style: style),
    );
  }
}

class _UsageRow extends StatelessWidget {
  const _UsageRow({
    required this.row,
    required this.groupBy,
    required this.summary,
  });

  final UsageGroup row;
  final UsageGroupBy groupBy;
  final UsageSummary summary;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);
    final share = summary.totalTokens == 0
        ? 0.0
        : row.totalTokens / summary.totalTokens;
    final isCliGroup = groupBy == UsageGroupBy.cli;
    final cli = isCliGroup ? CliTool.tryParse(row.label) : null;
    final label = cli == null
        ? usageGroupName(context, row)
        : usageCliLabel(cli);
    final subtitle = usageGroupSubtitle(context, row.subtitle);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.35)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: styles.smMedium,
                ),
                const SizedBox(height: 3),
                Wrap(
                  spacing: 4,
                  runSpacing: 2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    for (final tool in row.clis)
                      if (!isCliGroup)
                        _CliBadge(cli: tool)
                      else
                        const SizedBox.shrink(),
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
            ),
          ),
          _numberCell(formatUsageTokens(row.totalTokens), 90, styles),
          _numberCell(formatUsageTokens(row.freshInputTokens), 80, styles),
          _numberCell(formatUsageTokens(row.outputTokens), 80, styles),
          _numberCell(formatUsageTokens(row.cacheReadTokens), 90, styles),
          _costCell(context, row, styles),
          _numberCell('${row.requests}', 70, styles),
          _numberCell('${row.sessions}', 70, styles),
          SizedBox(
            width: 120,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(formatUsagePercent(share), style: styles.smMedium),
                const SizedBox(height: 5),
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
            ),
          ),
        ],
      ),
    );
  }

  Widget _numberCell(String text, double width, TpTextStyles styles) {
    return SizedBox(
      width: width,
      child: Text(text, textAlign: TextAlign.end, style: styles.sm),
    );
  }

  Widget _costCell(BuildContext context, UsageGroup row, TpTextStyles styles) {
    final l10n = context.l10n;
    final text = row.pricedEvents == 0
        ? l10n.sessionUsageCostUnpriced
        : '${formatUsageCost(row.costMicroUsd)}${row.unpricedEvents > 0 ? '*' : ''}';
    return SizedBox(
      width: 100,
      child: Text(text, textAlign: TextAlign.end, style: styles.sm),
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
