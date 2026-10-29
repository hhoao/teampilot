import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../l10n/l10n_extensions.dart';
import '../../../models/cursor_usage_account.dart';
import '../../../models/cursor_usage_range.dart';
import '../../../models/cursor_usage_report.dart';
import '../cursor_usage_format.dart';
import 'event_table.dart';
import 'model_breakdown.dart';
import 'usage_totals.dart';

class CursorUsageDetail extends StatelessWidget {
  const CursorUsageDetail({
    required this.report,
    required this.account,
    required this.cycle,
    super.key,
  });

  final CursorUsageReport report;
  final CursorUsageAccount? account;
  final CursorUsageWindow? cycle;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final styles = TpTextStyles.of(context);
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.cursorUsageTotals, style: styles.mdSemibold),
        const SizedBox(height: 8),
        CursorUsageTotals(report: report),
        const SizedBox(height: 20),
        Text(l10n.cursorUsageByModel, style: styles.mdSemibold),
        const SizedBox(height: 8),
        CursorUsageModelBreakdown(report: report),
        const SizedBox(height: 20),
        Text(l10n.cursorUsageEvents, style: styles.mdSemibold),
        const SizedBox(height: 8),
        CursorUsageEventTable(report: report),
        if (cycle != null) ...[
          const SizedBox(height: 16),
          Text(
            l10n.cursorUsageCycleRange(
              formatCursorUsageDate(cycle!.startMs),
              formatCursorUsageDate(cycle!.endMs),
            ),
            style: styles.xsColored(cs.onSurface.withValues(alpha: 0.6)),
          ),
        ],
      ],
    );
  }
}
