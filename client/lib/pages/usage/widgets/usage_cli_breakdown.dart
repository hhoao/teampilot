import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../l10n/l10n_extensions.dart';
import '../../../models/session_usage_dashboard.dart';
import '../../../models/team_config.dart';
import '../../../theme/workspace_surface_layers.dart';
import '../usage_format.dart';

class UsageCliBreakdown extends StatefulWidget {
  const UsageCliBreakdown({
    required this.slices,
    required this.summary,
    this.selectedCli,
    super.key,
  });

  final List<UsageCliSlice> slices;
  final UsageSummary summary;
  final CliTool? selectedCli;

  @override
  State<UsageCliBreakdown> createState() => _UsageCliBreakdownState();
}

class _UsageCliBreakdownState extends State<UsageCliBreakdown> {
  int? _touchedIndex;

  void _handleTouch(FlTouchEvent event, PieTouchResponse? response) {
    final index = event.isInterestedForInteractions
        ? response?.touchedSection?.touchedSectionIndex ?? -1
        : -1;
    final next = index >= 0 && index < widget.slices.length ? index : null;
    if (next == _touchedIndex) return;
    setState(() => _touchedIndex = next);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);
    final slices = widget.slices;
    final total = slices.fold<int>(0, (sum, slice) => sum + slice.totalTokens);
    final cacheShare = widget.summary.totalTokens == 0
        ? 0.0
        : widget.summary.cacheReadTokens / widget.summary.totalTokens;
    final touched =
        _touchedIndex != null &&
            _touchedIndex! >= 0 &&
            _touchedIndex! < slices.length
        ? slices[_touchedIndex!]
        : null;
    final mutedXs = styles.xs.copyWith(
      color: cs.onSurface.withValues(alpha: 0.56),
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: workspaceCardDecoration(
        cs,
        radius: 14,
      ).copyWith(color: cs.workspaceCard),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.sessionUsageCliBreakdown, style: styles.mdBold),
          const SizedBox(height: 12),
          if (slices.isEmpty || total == 0)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 26),
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
            SizedBox(
              height: 150,
              width: double.infinity,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  PieChart(
                    PieChartData(
                      startDegreeOffset: -90,
                      centerSpaceRadius: 44,
                      sectionsSpace: 2,
                      sections: [
                        for (var index = 0; index < slices.length; index++)
                          PieChartSectionData(
                            value: slices[index].totalTokens.toDouble(),
                            color: usageCliColor(slices[index].cli).withValues(
                              alpha:
                                  widget.selectedCli == null ||
                                      widget.selectedCli == slices[index].cli
                                  ? 0.92
                                  : 0.22,
                            ),
                            radius: _touchedIndex == index ? 31.0 : 28.0,
                            showTitle: false,
                          ),
                      ],
                      pieTouchData: PieTouchData(touchCallback: _handleTouch),
                    ),
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                  ),
                  IgnorePointer(
                    child: SizedBox(
                      key: const ValueKey('usageCliBreakdownCenter'),
                      width: 86,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            formatUsageTokens(touched?.totalTokens ?? total),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: styles.mdBold,
                          ),
                          const SizedBox(height: 2),
                          if (touched == null)
                            Text(
                              l10n.sessionUsageTotalTokens,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: mutedXs,
                            )
                          else ...[
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                usageCliLabel(touched.cli),
                                maxLines: 1,
                                textAlign: TextAlign.center,
                                style: mutedXs,
                              ),
                            ),
                            Text(
                              formatUsagePercent(touched.share),
                              maxLines: 1,
                              textAlign: TextAlign.center,
                              style: mutedXs,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            for (final slice in slices) ...[
              _CliSliceRow(
                slice: slice,
                dimmed:
                    widget.selectedCli != null &&
                    widget.selectedCli != slice.cli,
              ),
              const SizedBox(height: 12),
            ],
          ],
          const SizedBox(height: 10),
          Divider(color: cs.outlineVariant.withValues(alpha: 0.5), height: 18),
          Text(
            l10n.sessionUsageCacheReadShare(formatUsagePercent(cacheShare)),
            style: styles.xs.copyWith(
              color: cs.onSurface.withValues(alpha: 0.56),
            ),
          ),
        ],
      ),
    );
  }
}

class _CliSliceRow extends StatelessWidget {
  const _CliSliceRow({required this.slice, required this.dimmed});

  final UsageCliSlice slice;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final styles = TpTextStyles.of(context);
    final cs = Theme.of(context).colorScheme;
    final color = usageCliColor(slice.cli);
    return Opacity(
      opacity: dimmed ? 0.42 : 1,
      child: Row(
        children: [
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              usageCliLabel(slice.cli),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: styles.smMedium,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            formatUsageTokens(slice.totalTokens),
            style: styles.smMedium,
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 42,
            child: Text(
              formatUsagePercent(slice.share),
              textAlign: TextAlign.end,
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
