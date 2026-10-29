import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../l10n/l10n_extensions.dart';
import '../../../models/session_usage_dashboard.dart';
import '../../../theme/workspace_surface_layers.dart';
import '../usage_format.dart';

class UsageSummaryCards extends StatelessWidget {
  const UsageSummaryCards({
    required this.dashboard,
    required this.nowMs,
    super.key,
  });

  final UsageDashboard dashboard;
  final int nowMs;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final summary = dashboard.summary;
    final total = summary.totalTokens;

    final cards = <Widget>[
      _MetricCard(
        title: l10n.sessionUsageTotalTokens,
        value: formatUsageTokens(summary.totalTokens),
        icon: Icons.data_usage_outlined,
        accent: const Color(0xFFD97757),
        details: [
          l10n.sessionUsageRequestsSessions(summary.requests, summary.sessions),
        ],
        sparkline: UsageSparkline(days: dashboard.chart),
      ),
      _MetricCard(
        title: l10n.sessionUsageInputTokens,
        value: formatUsageTokens(summary.freshInputTokens),
        icon: Icons.south_east_outlined,
        accent: const Color(0xFF6366F1),
        details: [
          l10n.sessionUsageShare(
            formatUsageShare(summary.freshInputTokens, total),
          ),
        ],
      ),
      _MetricCard(
        title: l10n.sessionUsageOutputTokens,
        value: formatUsageTokens(summary.outputTokens),
        icon: Icons.north_east_outlined,
        accent: const Color(0xFF10A37F),
        details: [
          l10n.sessionUsageShare(formatUsageShare(summary.outputTokens, total)),
        ],
      ),
      _MetricCard(
        title: l10n.sessionUsageCacheRead,
        value: formatUsageTokens(summary.cacheReadTokens),
        icon: Icons.bolt_outlined,
        accent: const Color(0xFFF59E0B),
        details: [
          l10n.sessionUsageCacheHit(formatUsagePercent(summary.cacheHitRate)),
          l10n.sessionUsageCacheWrite(
            formatUsageTokens(summary.cacheCreationTokens),
          ),
        ],
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width >= 980
            ? 4
            : width >= 520
            ? 2
            : 1;
        const gap = 12.0;
        final cardWidth = columns == 1
            ? width
            : (width - gap * (columns - 1)) / columns;
        // Cards grow with their content (typography is scaled through the
        // theme, not MediaQuery.textScaler, so a fixed height overflows) while
        // every card in a run keeps the height of the tallest one.
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var start = 0; start < cards.length; start += columns) ...[
              if (start > 0) const SizedBox(height: gap),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (
                      var index = start;
                      index < start + columns && index < cards.length;
                      index++
                    ) ...[
                      if (index > start) const SizedBox(width: gap),
                      SizedBox(
                        width: cardWidth,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 148),
                          child: cards[index],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.accent,
    required this.details,
    this.sparkline,
  });

  final String title;
  final String value;
  final IconData icon;
  final Color accent;
  final List<String> details;
  final Widget? sparkline;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: workspaceCardDecoration(
        cs,
        radius: 14,
      ).copyWith(color: cs.workspaceCard),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 17, color: accent),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: styles.smMedium.copyWith(
                    color: cs.onSurface.withValues(alpha: 0.66),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: styles.xl.copyWith(fontWeight: FontWeight.w700),
          ),
          const Spacer(),
          if (sparkline != null) ...[sparkline!, const SizedBox(height: 7)],
          for (final detail in details)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                detail,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: styles.xs.copyWith(
                  color: cs.onSurface.withValues(alpha: 0.56),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class UsageSparkline extends StatelessWidget {
  const UsageSparkline({required this.days, super.key});

  final List<UsageChartDay> days;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final maxTotal = days.fold<int>(
      0,
      (max, day) => day.totalTokens > max ? day.totalTokens : max,
    );
    final maxY = maxTotal == 0 ? 1.0 : maxTotal * 1.05;
    return SizedBox(
      height: 26,
      child: BarChart(
        BarChartData(
          minY: 0,
          maxY: maxY,
          alignment: BarChartAlignment.spaceAround,
          barGroups: [
            for (var index = 0; index < days.length; index++)
              BarChartGroupData(
                x: index,
                barRods: [
                  BarChartRodData(
                    toY: days[index].totalTokens == 0
                        ? maxY * 0.06
                        : days[index].totalTokens.toDouble(),
                    width: 6,
                    color: cs.primary.withValues(
                      alpha: days[index].totalTokens == 0 ? 0.16 : 0.56,
                    ),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ],
              ),
          ],
          titlesData: const FlTitlesData(show: false),
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          barTouchData: BarTouchData(enabled: false),
        ),
        duration: Duration.zero,
      ),
    );
  }
}
