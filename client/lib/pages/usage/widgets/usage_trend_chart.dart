import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../l10n/l10n_extensions.dart';
import '../../../models/session_usage_dashboard.dart';
import '../../../models/team_config.dart';
import '../../../theme/workspace_surface_layers.dart';
import '../usage_format.dart';

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
              height: 150,
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
              height: 160,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final day in days)
                    Expanded(
                      child: Tooltip(
                        message: formatUsageTokens(day.totalTokens),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              for (final cli in legendClis)
                                if ((day.tokensByCli[cli] ?? 0) > 0)
                                  Container(
                                    height:
                                        132 *
                                        (day.tokensByCli[cli]! / maxTotal),
                                    decoration: BoxDecoration(
                                      color: usageCliColor(cli).withValues(
                                        alpha:
                                            selectedCli == null ||
                                                selectedCli == cli
                                            ? 0.92
                                            : 0.22,
                                      ),
                                      borderRadius: const BorderRadius.vertical(
                                        top: Radius.circular(3),
                                      ),
                                    ),
                                  ),
                              const SizedBox(height: 8),
                              Text(
                                formatUsageDayLabel(
                                  context,
                                  day.dayStartMs,
                                  nowMs,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: styles.xs.copyWith(
                                  color: cs.onSurface.withValues(alpha: 0.54),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
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
