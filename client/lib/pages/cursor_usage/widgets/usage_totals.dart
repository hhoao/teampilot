import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../l10n/l10n_extensions.dart';
import '../../../models/cursor_usage_report.dart';
import '../../../pages/usage/usage_format.dart';
import '../cursor_usage_format.dart';

class CursorUsageTotals extends StatelessWidget {
  const CursorUsageTotals({required this.report, super.key});

  final CursorUsageReport report;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final styles = TpTextStyles.of(context);
    final cs = Theme.of(context).colorScheme;
    final cells = <(String, String)>[
      (
        l10n.cursorUsageGrandTotal,
        formatUsageTokens(
          report.inputTokens +
              report.outputTokens +
              report.cacheReadTokens +
              report.cacheWriteTokens,
        ),
      ),
      (l10n.cursorUsageInput, formatUsageTokens(report.inputTokens)),
      (l10n.cursorUsageOutput, formatUsageTokens(report.outputTokens)),
      (l10n.cursorUsageCacheRead, formatUsageTokens(report.cacheReadTokens)),
      (l10n.cursorUsageCacheWrite, formatUsageTokens(report.cacheWriteTokens)),
      (l10n.cursorUsageCost, formatCursorUsageUsd(report.totalCents)),
      (l10n.cursorUsageEvents, '${report.eventCount}'),
    ];
    return Wrap(
      spacing: 24,
      runSpacing: 12,
      children: [
        for (final cell in cells)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                cell.$1,
                style: styles.xsColored(cs.onSurface.withValues(alpha: 0.55)),
              ),
              const SizedBox(height: 2),
              Text(cell.$2, style: styles.mdSemibold),
            ],
          ),
      ],
    );
  }
}
