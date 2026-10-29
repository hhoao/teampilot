import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../l10n/l10n_extensions.dart';
import '../../../models/cursor_usage_report.dart';
import '../../usage/usage_format.dart';
import '../cursor_usage_format.dart';

class CursorUsageEventTable extends StatelessWidget {
  const CursorUsageEventTable({required this.report, super.key});

  final CursorUsageReport report;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final styles = TpTextStyles.of(context);
    final cs = Theme.of(context).colorScheme;
    if (report.summaryOnly) {
      return Text(
        l10n.cursorUsageSummaryOnly,
        style: styles.xsColored(cs.onSurface.withValues(alpha: 0.6)),
      );
    }
    if (report.events.isEmpty) {
      return Text(
        l10n.cursorUsageNoData,
        style: styles.xsColored(cs.onSurface.withValues(alpha: 0.6)),
      );
    }
    return Column(
      children: [
        for (final event in report.events.take(200))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                SizedBox(
                  width: 132,
                  child: Text(
                    formatCursorUsageTimestamp(event.timestampMs),
                    style: styles.xsColored(
                      cs.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    event.model.isEmpty
                        ? l10n.cursorUsageUnattributed
                        : event.model,
                    style: styles.xs,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(formatUsageTokens(event.totalTokens), style: styles.xs),
                const SizedBox(width: 12),
                SizedBox(
                  width: 68,
                  child: Text(
                    formatCursorUsageUsd(event.totalCents),
                    textAlign: TextAlign.right,
                    style: styles.xs,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
