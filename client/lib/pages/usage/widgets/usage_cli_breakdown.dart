import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../l10n/l10n_extensions.dart';
import '../../../models/session_usage_dashboard.dart';
import '../../../models/team_config.dart';
import '../../../theme/workspace_surface_layers.dart';
import '../usage_format.dart';

class UsageCliBreakdown extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);
    final cacheShare = summary.totalTokens == 0
        ? 0.0
        : summary.cacheReadTokens / summary.totalTokens;

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
          if (slices.isEmpty)
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
          else
            for (final slice in slices) ...[
              _CliSliceRow(
                slice: slice,
                dimmed: selectedCli != null && selectedCli != slice.cli,
              ),
              const SizedBox(height: 12),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: slice.share,
              minHeight: 5,
              backgroundColor: cs.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ],
      ),
    );
  }
}
