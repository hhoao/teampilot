import 'package:flutter/material.dart';

import '../../../models/cursor_usage_account.dart';
import '../../../models/cursor_usage_range.dart';
import '../../../models/cursor_usage_report.dart';

/// Placeholder body: Task 10 replaces this with the totals/model/event widgets.
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
  Widget build(BuildContext context) => const SizedBox.shrink();
}
