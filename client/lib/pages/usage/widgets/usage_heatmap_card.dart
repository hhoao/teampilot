import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../l10n/l10n_extensions.dart';
import '../../../models/session_usage_dashboard.dart';
import '../../../theme/workspace_surface_layers.dart';
import '../usage_format.dart';
import 'usage_heatmap_layout.dart';

enum _HeatmapMetric { tokens, requests, cost, hitRate }

/// Month labels are wider than one week column, so skip labels that would
/// sit closer than this many weeks to the previous one.
const int _minMonthLabelWeeks = 3;

class UsageHeatmapCard extends StatefulWidget {
  const UsageHeatmapCard({required this.days, required this.nowMs, super.key});

  final List<UsageHeatmapDay> days;
  final int nowMs;

  @override
  State<UsageHeatmapCard> createState() => _UsageHeatmapCardState();
}

class _UsageHeatmapCardState extends State<UsageHeatmapCard> {
  _HeatmapMetric _metric = _HeatmapMetric.tokens;
  bool _showEarlier = false;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);
    final spans = usageHeatmapSpans(days: widget.days, nowMs: widget.nowMs);
    final today = usageHeatmapLocalDayStart(widget.nowMs);
    final byDay = {
      for (final day in widget.days)
        usageHeatmapLocalDayStart(day.dayStartMs): day,
    };
    final values = <double>[];
    for (final span in spans) {
      for (final week in span.weekDayStarts) {
        for (final dayStart in week) {
          if (dayStart > today) continue;
          final value = _metricValue(byDay[dayStart], _metric);
          if (value != null) values.add(value);
        }
      }
    }
    final thresholds = usageHeatmapThresholds(values);
    final visible = _showEarlier
        ? spans
        : spans.take(1).toList(growable: false);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: workspaceCardDecoration(
        cs,
        radius: 14,
      ).copyWith(color: cs.workspaceCard),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final title = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.sessionUsageHeatmapTitle, style: styles.mdBold),
                  const SizedBox(height: 2),
                  Text(
                    l10n.sessionUsageHeatmapSubtitle,
                    style: styles.sm.copyWith(
                      color: cs.onSurface.withValues(alpha: 0.56),
                    ),
                  ),
                ],
              );
              final control = TpSegmentedControl(
                key: ValueKey(_metric),
                totalSwitches: _HeatmapMetric.values.length,
                initialLabelIndex: _metric.index,
                labels: [
                  l10n.sessionUsageHeatmapMetricTokens,
                  l10n.sessionUsageRequests,
                  l10n.sessionUsageCost,
                  l10n.sessionUsageHeatmapMetricHitRate,
                ],
                variant: TpSegmentedControlVariant.outlined,
                minWidth: 56,
                minHeight: 30,
                onToggle: (index) {
                  if (index == null) return;
                  setState(() => _metric = _HeatmapMetric.values[index]);
                },
              );
              if (constraints.maxWidth < 620) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    title,
                    const SizedBox(height: 10),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: control,
                    ),
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: title),
                  const SizedBox(width: 12),
                  control,
                ],
              );
            },
          ),
          const SizedBox(height: 14),
          if (widget.days.isEmpty)
            SizedBox(
              height: 120,
              child: Center(
                child: Text(
                  l10n.sessionUsageNoData,
                  style: styles.sm.copyWith(
                    color: cs.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ),
            )
          else ...[
            for (var index = 0; index < visible.length; index++) ...[
              if (index > 0) const SizedBox(height: 16),
              _SpanBlock(
                span: visible[index],
                byDay: byDay,
                metric: _metric,
                thresholds: thresholds,
                todayMs: today,
                styles: styles,
                cs: cs,
                l10n: l10n,
              ),
            ],
            const SizedBox(height: 10),
            _footer(spans, cs, styles, l10n),
          ],
        ],
      ),
    );
  }

  Widget _footer(
    List<UsageHeatmapSpan> spans,
    ColorScheme cs,
    TpTextStyles styles,
    AppLocalizations l10n,
  ) {
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (spans.length > 1)
          TextButton(
            key: const ValueKey('usageHeatmapShowEarlier'),
            onPressed: () => setState(() => _showEarlier = !_showEarlier),
            child: Text(
              _showEarlier
                  ? l10n.sessionUsageHeatmapShowLess
                  : l10n.sessionUsageHeatmapShowEarlier,
              style: styles.xs,
            ),
          ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.sessionUsageHeatmapLess,
              style: styles.xs.copyWith(
                color: cs.onSurface.withValues(alpha: 0.56),
              ),
            ),
            for (var level = 0; level < 5; level++)
              Container(
                width: 10,
                height: 10,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  color: _heatColor(level, cs),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            Text(
              l10n.sessionUsageHeatmapMore,
              style: styles.xs.copyWith(
                color: cs.onSurface.withValues(alpha: 0.56),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _SpanBlock extends StatelessWidget {
  const _SpanBlock({
    required this.span,
    required this.byDay,
    required this.metric,
    required this.thresholds,
    required this.todayMs,
    required this.styles,
    required this.cs,
    required this.l10n,
  });

  final UsageHeatmapSpan span;
  final Map<int, UsageHeatmapDay> byDay;
  final _HeatmapMetric metric;
  final List<double> thresholds;
  final int todayMs;
  final TpTextStyles styles;
  final ColorScheme cs;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final material = MaterialLocalizations.of(context);
    final monthFormat = DateFormat.MMM(
      Localizations.localeOf(context).toLanguageTag(),
    );
    final monthLabels = <String?>[];
    int? previousMonth;
    var lastLabelWeek = -_minMonthLabelWeeks;
    for (var week = 0; week < usageHeatmapWeeks; week++) {
      final first = DateTime.fromMillisecondsSinceEpoch(
        span.weekDayStarts[week].first,
      ).toLocal();
      // Labels are wider than one week column, so a month that starts right
      // after the previous label (span start) is skipped instead of overlapping.
      final newMonth = week == 0 || first.month != previousMonth;
      if (newMonth && week - lastLabelWeek >= _minMonthLabelWeeks) {
        monthLabels.add(monthFormat.format(first));
        lastLabelWeek = week;
      } else {
        monthLabels.add(null);
      }
      previousMonth = first.month;
    }
    final range =
        '${material.formatShortDate(DateTime.fromMillisecondsSinceEpoch(span.startDayMs))} – '
        '${material.formatShortDate(DateTime.fromMillisecondsSinceEpoch(span.endDayMs))}';

    final spacing = context.tpSpacing;
    final gap = spacing.xs;
    final labelWidth = spacing.xxl;
    final labelStyle = styles.md.copyWith(
      color: cs.onSurface.withValues(alpha: 0.54),
      // Keep the label box inside one cell pitch.
      height: 1.1,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: spacing.sm,
          runSpacing: spacing.xxs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(range, style: styles.smMedium),
            Text(
              l10n.sessionUsageHeatmapSpanSummary(
                formatUsageTokens(span.tokens),
                '${span.requests}',
                formatUsageCost(span.costMicroUsd),
              ),
              style: styles.sm.copyWith(
                color: cs.onSurface.withValues(alpha: 0.56),
              ),
            ),
          ],
        ),
        SizedBox(height: spacing.md),
        LayoutBuilder(
          builder: (context, constraints) {
            // Cells grow up to [spacing.xl] to fill the card; narrower
            // layouts keep [spacing.md] and scroll instead.
            final rawCell =
                (constraints.maxWidth -
                    labelWidth -
                    gap * (usageHeatmapWeeks - 1)) /
                usageHeatmapWeeks;
            final cell = rawCell.clamp(spacing.md, spacing.xl);
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: labelWidth + usageHeatmapWeeks * (cell + gap),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      // Month labels keep one spacing step above the grid.
                      padding: EdgeInsets.only(bottom: spacing.md),
                      child: SizedBox(
                        height: cell + gap,
                        child: MediaQuery.withNoTextScaling(
                          child: Row(
                            children: [
                              SizedBox(width: labelWidth),
                              for (var week = 0;
                                  week < usageHeatmapWeeks;
                                  week++)
                                SizedBox(
                                  width: cell + gap,
                                  child: OverflowBox(
                                    alignment: Alignment.centerLeft,
                                    maxWidth: 48,
                                    child: Text(
                                      monthLabels[week] ?? '',
                                      maxLines: 1,
                                      style: labelStyle,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    for (var day = 0; day < 7; day++)
                      Row(
                        children: [
                          SizedBox(
                            width: labelWidth,
                            height: cell + gap,
                            child: day == 0 || day == 2 || day == 4
                                ? MediaQuery.withNoTextScaling(
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      alignment: Alignment.centerRight,
                                      child: Padding(
                                        padding: EdgeInsets.only(
                                          right: spacing.md,
                                        ),
                                        child: Text(
                                          material.narrowWeekdays[(day + 1) % 7],
                                          maxLines: 1,
                                          style: labelStyle,
                                        ),
                                      ),
                                    ),
                                  )
                                : null,
                          ),
                          for (var week = 0;
                              week < usageHeatmapWeeks;
                              week++)
                            Padding(
                              padding: EdgeInsets.only(right: gap, bottom: gap),
                              child: _cell(
                                span.weekDayStarts[week][day],
                                cell,
                                material,
                              ),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _cell(int dayStart, double cell, MaterialLocalizations material) {
    final future = dayStart > todayMs;
    final data = byDay[dayStart];
    final level = future
        ? 0
        : usageHeatmapLevel(_metricValue(data, metric), thresholds);
    return Tooltip(
      message: future ? '' : _tooltip(dayStart, data, material),
      waitDuration: const Duration(milliseconds: 150),
      child: Container(
        key: ValueKey('usageHeatmapCell-$dayStart'),
        width: cell,
        height: cell,
        decoration: BoxDecoration(
          color: future ? Colors.transparent : _heatColor(level, cs),
          borderRadius: BorderRadius.circular(3),
        ),
      ),
    );
  }

  String _tooltip(
    int dayStart,
    UsageHeatmapDay? data,
    MaterialLocalizations material,
  ) {
    final date = material.formatFullDate(
      DateTime.fromMillisecondsSinceEpoch(dayStart).toLocal(),
    );
    final hitRate = data?.cacheHitRate;
    return '$date\n'
        '${l10n.sessionUsageTotalTokens} ${formatUsageTokens(data?.tokens ?? 0)}\n'
        '${l10n.sessionUsageRequests} ${data?.requests ?? 0}\n'
        '${l10n.sessionUsageCost} ${formatUsageCost(data?.costMicroUsd ?? 0)}\n'
        '${l10n.sessionUsageHeatmapMetricHitRate} '
        '${hitRate == null ? '—' : formatUsagePercent(hitRate)}';
  }
}

double? _metricValue(UsageHeatmapDay? day, _HeatmapMetric metric) {
  if (day == null) return null;
  return switch (metric) {
    _HeatmapMetric.tokens => day.tokens > 0 ? day.tokens.toDouble() : null,
    _HeatmapMetric.requests =>
      day.requests > 0 ? day.requests.toDouble() : null,
    _HeatmapMetric.cost =>
      day.costMicroUsd > 0 ? day.costMicroUsd.toDouble() : null,
    _HeatmapMetric.hitRate => day.cacheHitRate,
  };
}

Color _heatColor(int level, ColorScheme cs) {
  return switch (level) {
    0 => cs.surfaceContainerHighest,
    1 => cs.primary.withValues(alpha: 0.20),
    2 => cs.primary.withValues(alpha: 0.38),
    3 => cs.primary.withValues(alpha: 0.58),
    _ => cs.primary.withValues(alpha: 0.82),
  };
}
