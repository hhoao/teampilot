import 'package:flutter/material.dart';

import '../../l10n/l10n_extensions.dart';
import '../../models/session_usage_dashboard.dart';
import '../../models/team_config.dart';
import '../../models/cursor_usage_import.dart';
import '../../services/usage/usage_aggregator.dart';

String formatUsageTokens(int value) {
  if (value >= 1000000) {
    final millions = value / 1000000;
    return '${millions >= 100 ? millions.toStringAsFixed(0) : millions.toStringAsFixed(1)}M';
  }
  if (value >= 1000) {
    final thousands = value / 1000;
    return '${thousands >= 100 ? thousands.toStringAsFixed(0) : thousands.toStringAsFixed(1)}K';
  }
  return '$value';
}

String formatUsagePercent(double value) {
  final percent = (value.clamp(0, 1)) * 100;
  if (percent == 0) return '0%';
  if (percent >= 10) return '${percent.toStringAsFixed(0)}%';
  return '${percent.toStringAsFixed(1)}%';
}

String formatUsageShare(int part, int total) =>
    formatUsagePercent(total == 0 ? 0 : part / total);

String formatUsageCost(int? microUsd) {
  if (microUsd == null) return '—';
  if (microUsd == 0) return r'$0.00';
  if (microUsd < 10000) return r'<$0.01';
  final dollars = microUsd / 1000000;
  if (dollars < 1) return '\$${dollars.toStringAsFixed(4)}';
  return '\$${dollars.toStringAsFixed(2)}';
}

String formatUsageLastSync(BuildContext context, int? timestampMs) {
  if (timestampMs == null) return context.l10n.sessionUsageNeverSynced;
  final date = DateTime.fromMillisecondsSinceEpoch(timestampMs).toLocal();
  final material = MaterialLocalizations.of(context);
  final time = material.formatTimeOfDay(
    TimeOfDay.fromDateTime(date),
    alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
  );
  return context.l10n.sessionUsageLastSync(
    '${material.formatShortDate(date)} $time',
  );
}

String formatUsageDayLabel(BuildContext context, int dayStartMs, int nowMs) {
  if (usageIsToday(dayStartMs, nowMs)) return context.l10n.sessionUsageToday;
  final date = DateTime.fromMillisecondsSinceEpoch(dayStartMs).toLocal();
  return '${date.month}/${date.day}';
}

String usageCliLabel(CliTool cli) => switch (cli) {
  CliTool.claude => 'Claude Code',
  CliTool.codex => 'Codex',
  CliTool.opencode => 'OpenCode',
  CliTool.cursor => 'Cursor',
  CliTool.gemini => 'Gemini',
  CliTool.codebuddy => 'CodeBuddy',
  CliTool.flashskyai => 'FlashSky',
};

Color usageCliColor(CliTool cli) => switch (cli) {
  CliTool.claude => const Color(0xFFD97757),
  CliTool.codex => const Color(0xFF10A37F),
  CliTool.opencode => const Color(0xFF8B5CF6),
  CliTool.cursor => const Color(0xFF2F80ED),
  CliTool.gemini => const Color(0xFF4285F4),
  CliTool.codebuddy => const Color(0xFF1E6FFF),
  CliTool.flashskyai => const Color(0xFFF59E0B),
};

String usageGroupLabel(BuildContext context, UsageGroupBy groupBy) {
  final l10n = context.l10n;
  return switch (groupBy) {
    UsageGroupBy.session => l10n.sessionUsageGroupSession,
    UsageGroupBy.member => l10n.sessionUsageGroupMember,
    UsageGroupBy.model => l10n.sessionUsageGroupModel,
    UsageGroupBy.cli => l10n.sessionUsageGroupCli,
  };
}

String usageGroupSubtitle(BuildContext context, String subtitle) {
  final l10n = context.l10n;
  return switch (subtitle) {
    usageSimpleSeat => l10n.sessionUsageSimpleSeat,
    usageUnknownTeam => l10n.sessionUsageUnknownTeam,
    usageUnknownSession => l10n.sessionUsageUnknownSession,
    _ => subtitle,
  };
}

String usageGroupName(BuildContext context, UsageGroup group) {
  final l10n = context.l10n;
  if (group.label == cursorImportedSessionId) {
    return l10n.sessionUsageCursorImportedSession;
  }
  return switch (group.label) {
    usageUnknownModel => l10n.sessionUsageUnknownModel,
    usageUnknownSession => l10n.sessionUsageUnknownSession,
    usageUnknownTeam => l10n.sessionUsageUnknownTeam,
    usageSimpleSeat => l10n.sessionUsageSimpleSeat,
    _ => group.label,
  };
}

/// Bottom-axis label stride for the usage trend chart.
///
/// Keeps at most about seven day labels visible for any selected range.
int usageChartLabelStride(int dayCount) {
  if (dayCount <= 0) return 1;
  return (dayCount / 7).ceil();
}
