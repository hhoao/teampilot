import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../l10n/l10n_extensions.dart';
import '../../../models/session_usage_dashboard.dart';
import '../../../models/team_config.dart';
import '../../../theme/workspace_surface_layers.dart';
import '../usage_format.dart';

const double _chartHeight = 180;
const Duration _chartAnimation = Duration(milliseconds: 260);

class UsageTrendChart extends StatelessWidget {
  const UsageTrendChart({
    required this.days,
    required this.nowMs,
    this.selectedCli,
    super.key,
  });

  final List<UsageChartDay> days;
  final int nowMs;
  final CliTool? selectedCli;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);
    final maxTotal = days.fold<int>(
      0,
      (max, day) => day.totalTokens > max ? day.totalTokens : max,
    );
    final chartTotal = days.fold<int>(0, (sum, day) => sum + day.totalTokens);
    final average = days.isEmpty ? 0 : chartTotal ~/ days.length;
    final totalsByCli = <CliTool, int>{};
    for (final day in days) {
      for (final entry in day.tokensByCli.entries) {
        totalsByCli[entry.key] = (totalsByCli[entry.key] ?? 0) + entry.value;
      }
    }
    final legendClis = totalsByCli.keys.toList()
      ..sort((a, b) => a.index.compareTo(b.index));

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: workspaceCardDecoration(
        cs,
        radius: 14,
      ).copyWith(color: cs.workspaceCard),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.sessionUsageChartTitle, style: styles.mdBold),
                    const SizedBox(height: 2),
                    Text(
                      l10n.sessionUsageChartSubtitle,
                      style: styles.xs.copyWith(
                        color: cs.onSurface.withValues(alpha: 0.56),
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    l10n.sessionUsageChartTotal(formatUsageTokens(chartTotal)),
                    style: styles.smMedium,
                  ),
                  Text(
                    l10n.sessionUsageChartAverage(formatUsageTokens(average)),
                    style: styles.xs.copyWith(
                      color: cs.onSurface.withValues(alpha: 0.56),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (maxTotal == 0)
            SizedBox(
              height: _chartHeight,
              child: Center(
                child: Text(
                  l10n.sessionUsageNoData,
                  style: styles.sm.copyWith(
                    color: cs.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ),
            )
          else
            SizedBox(
              height: _chartHeight,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final rodWidth = (constraints.maxWidth / days.length * 0.46)
                      .clamp(3.0, 18.0)
                      .toDouble();
                  final stride = usageChartLabelStride(days.length);
                  final tickInterval = maxTotal <= 2 ? 1.0 : maxTotal / 2;
                  final labelStyle = styles.xs.copyWith(
                    color: cs.onSurface.withValues(alpha: 0.54),
                  );
                  return BarChart(
                    BarChartData(
                      minY: 0,
                      maxY: maxTotal * 1.12,
                      alignment: BarChartAlignment.spaceEvenly,
                      barGroups: [
                        for (var index = 0; index < days.length; index++)
                          _chartGroup(
                            index: index,
                            day: days[index],
                            legendClis: legendClis,
                            rodWidth: rodWidth,
                            selectedCli: selectedCli,
                          ),
                      ],
                      titlesData: FlTitlesData(
                        topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        rightTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 40,
                            interval: tickInterval,
                            maxIncluded: false,
                            getTitlesWidget: (value, meta) => SideTitleWidget(
                              meta: meta,
                              space: 6,
                              child: Text(
                                formatUsageTokens(value.round()),
                                style: labelStyle,
                              ),
                            ),
                          ),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 26,
                            interval: 1,
                            getTitlesWidget: (value, meta) {
                              final index = value.round();
                              if (index < 0 ||
                                  index >= days.length ||
                                  (days.length - 1 - index) % stride != 0) {
                                return const SizedBox.shrink();
                              }
                              return SideTitleWidget(
                                meta: meta,
                                space: 6,
                                child: Text(
                                  formatUsageDayLabel(
                                    context,
                                    days[index].dayStartMs,
                                    nowMs,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: labelStyle,
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        horizontalInterval: tickInterval,
                        getDrawingHorizontalLine: (value) => FlLine(
                          color: cs.outlineVariant.withValues(alpha: 0.35),
                          strokeWidth: 1,
                        ),
                      ),
                      borderData: FlBorderData(show: false),
                      barTouchData: BarTouchData(
                        enabled: true,
                        touchTooltipData: BarTouchTooltipData(
                          tooltipBorderRadius: BorderRadius.circular(8),
                          tooltipPadding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          tooltipMargin: 8,
                          maxContentWidth: 190,
                          fitInsideHorizontally: true,
                          fitInsideVertically: true,
                          getTooltipColor: (_) => cs.surfaceContainerHighest,
                          tooltipBorder: BorderSide(
                            color: cs.outlineVariant.withValues(alpha: 0.5),
                          ),
                          getTooltipItem: (group, groupIndex, rod, rodIndex) {
                            final index = groupIndex < days.length
                                ? groupIndex
                                : days.length - 1;
                            return _chartTooltip(
                              context: context,
                              day: days[index],
                              legendClis: legendClis,
                              styles: styles,
                              cs: cs,
                              nowMs: nowMs,
                            );
                          },
                        ),
                      ),
                    ),
                    duration: _chartAnimation,
                    curve: Curves.easeOutCubic,
                  );
                },
              ),
            ),
          if (legendClis.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 14,
              runSpacing: 6,
              children: [
                for (final cli in legendClis)
                  _LegendDot(
                    color: usageCliColor(cli),
                    label:
                        '${usageCliLabel(cli)} · ${formatUsageTokens(totalsByCli[cli] ?? 0)}',
                    dimmed: selectedCli != null && selectedCli != cli,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

BarChartGroupData _chartGroup({
  required int index,
  required UsageChartDay day,
  required List<CliTool> legendClis,
  required double rodWidth,
  required CliTool? selectedCli,
}) {
  var stacked = 0.0;
  final stackItems = <BarChartRodStackItem>[];
  for (final cli in legendClis) {
    final tokens = day.tokensByCli[cli] ?? 0;
    if (tokens <= 0) continue;
    final color = usageCliColor(
      cli,
    ).withValues(alpha: selectedCli == null || selectedCli == cli ? 0.92 : 0.22);
    stackItems.add(BarChartRodStackItem(stacked, stacked + tokens, color));
    stacked += tokens;
  }
  return BarChartGroupData(
    x: index,
    barRods: [
      BarChartRodData(
        toY: day.totalTokens.toDouble(),
        width: rodWidth,
        color: Colors.transparent,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
        rodStackItems: stackItems,
      ),
    ],
  );
}

BarTooltipItem _chartTooltip({
  required BuildContext context,
  required UsageChartDay day,
  required List<CliTool> legendClis,
  required TpTextStyles styles,
  required ColorScheme cs,
  required int nowMs,
}) {
  final children = <TextSpan>[];
  for (final cli in legendClis) {
    final tokens = day.tokensByCli[cli] ?? 0;
    if (tokens <= 0) continue;
    children.add(
      TextSpan(
        text: '\n${usageCliLabel(cli)}  ${formatUsageTokens(tokens)}',
        style: styles.xs.copyWith(color: usageCliColor(cli)),
      ),
    );
  }
  children.add(
    TextSpan(
      text:
          '\n${context.l10n.sessionUsageChartTotal(formatUsageTokens(day.totalTokens))}',
      style: styles.xsSemibold.copyWith(color: cs.onSurface),
    ),
  );
  return BarTooltipItem(
    formatUsageDayLabel(context, day.dayStartMs, nowMs),
    styles.smMedium.copyWith(color: cs.onSurface),
    children: children,
  );
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({
    required this.color,
    required this.label,
    required this.dimmed,
  });

  final Color color;
  final String label;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final styles = TpTextStyles.of(context);
    final cs = Theme.of(context).colorScheme;
    return Opacity(
      opacity: dimmed ? 0.42 : 1,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: styles.xs.copyWith(
              color: cs.onSurface.withValues(alpha: 0.68),
            ),
          ),
        ],
      ),
    );
  }
}
