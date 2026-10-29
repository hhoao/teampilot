import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../l10n/l10n_extensions.dart';
import '../../../models/cursor_usage_report.dart';
import '../../usage/usage_format.dart';

const cursorUsageUnattributedModel = 'unattributed';

@immutable
final class CursorUsageModelSlice {
  const CursorUsageModelSlice({
    required this.model,
    required this.totals,
    required this.share,
  });

  final String model;
  final CursorUsageModelTotals totals;
  final double share;
}

List<CursorUsageModelSlice> cursorUsageModelSlices(CursorUsageReport report) {
  final merged = <String, CursorUsageModelTotals>{};
  for (final entry in report.models.entries) {
    final key = entry.key.trim().isEmpty
        ? cursorUsageUnattributedModel
        : entry.key;
    merged[key] = (merged[key] ?? const CursorUsageModelTotals()).merge(
      entry.value,
    );
  }
  final total = merged.values.fold<int>(
    0,
    (sum, value) => sum + value.totalTokens,
  );
  final slices =
      merged.entries
          .map(
            (entry) => CursorUsageModelSlice(
              model: entry.key,
              totals: entry.value,
              share: total == 0 ? 0 : entry.value.totalTokens / total,
            ),
          )
          .toList()
        ..sort((a, b) => b.totals.totalTokens.compareTo(a.totals.totalTokens));
  return slices;
}

class CursorUsageModelBreakdown extends StatelessWidget {
  const CursorUsageModelBreakdown({required this.report, super.key});

  final CursorUsageReport report;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final styles = TpTextStyles.of(context);
    final cs = Theme.of(context).colorScheme;
    final slices = cursorUsageModelSlices(report);
    if (slices.isEmpty) {
      return Text(
        l10n.cursorUsageNoData,
        style: styles.smColored(cs.onSurface.withValues(alpha: 0.6)),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final slice in slices)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    slice.model == cursorUsageUnattributedModel
                        ? l10n.cursorUsageUnattributed
                        : slice.model,
                    style: styles.xs,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '${formatUsageTokens(slice.totals.totalTokens)}  '
                  '${formatUsagePercent(slice.share)}',
                  style: styles.xsColored(cs.onSurface.withValues(alpha: 0.6)),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
