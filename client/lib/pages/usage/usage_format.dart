import 'package:flutter/material.dart';

import '../../l10n/l10n_extensions.dart';
import '../../models/session_usage_dashboard.dart';
import '../../models/team_config.dart';
import '../../services/cursor_usage/cursor_usage_event_source.dart';

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
  if (timestampMs == null) return context.l10n.sessionUsage.neverSynced;
  final date = DateTime.fromMillisecondsSinceEpoch(timestampMs).toLocal();
  final material = MaterialLocalizations.of(context);
  final time = material.formatTimeOfDay(
    TimeOfDay.fromDateTime(date),
    alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
  );
  return context.l10n.sessionUsage.lastSync(
    time: '${material.formatShortDate(date)} $time',
  );
}

String usageCliLabel(CliTool cli) => switch (cli) {
  CliTool.claude => 'Claude Code',
  CliTool.codex => 'Codex',
  CliTool.opencode => 'OpenCode',
  CliTool.cursor => 'Cursor',
  CliTool.gemini => 'Gemini',
  CliTool.codebuddy => 'CodeBuddy',
  CliTool.antigravity => 'Antigravity',
  CliTool.qoder => 'Qoder',
  CliTool.qoderCn => 'Qoder CN',
  CliTool.flashskyai => 'FlashSky',
};

Color usageCliColor(CliTool cli) => switch (cli) {
  CliTool.claude => const Color(0xFFD97757),
  CliTool.codex => const Color(0xFF10A37F),
  CliTool.opencode => const Color(0xFF8B5CF6),
  CliTool.cursor => const Color(0xFF2F80ED),
  CliTool.gemini => const Color(0xFF4285F4),
  CliTool.codebuddy => const Color(0xFF1E6FFF),
  CliTool.antigravity => const Color(0xFF34A853),
  CliTool.qoder => const Color(0xFF6B4EFF),
  CliTool.qoderCn => const Color(0xFF6B4EFF),
  CliTool.flashskyai => const Color(0xFFF59E0B),
};

String usageGroupLabel(BuildContext context, UsageGroupBy groupBy) {
  final l10n = context.l10n;
  return switch (groupBy) {
    UsageGroupBy.session => l10n.sessionUsage.groupSession,
    UsageGroupBy.member => l10n.sessionUsage.groupMember,
    UsageGroupBy.model => l10n.sessionUsage.groupModel,
    UsageGroupBy.cli => l10n.sessionUsage.groupCli,
  };
}

String usageGroupSubtitle(BuildContext context, String subtitle) {
  final l10n = context.l10n;
  return switch (subtitle) {
    usageSimpleSeat => l10n.sessionUsage.simpleSeat,
    usageUnknownTeam => l10n.sessionUsage.unknownTeam,
    usageUnknownSession => l10n.sessionUsage.unknownSession,
    _ => subtitle,
  };
}

String usageGroupName(BuildContext context, UsageGroup group) {
  final l10n = context.l10n;
  if (group.label == cursorAccountUsageSessionId) {
    return l10n.cursor.accountUsageSession;
  }
  return switch (group.label) {
    usageUnknownModel => l10n.sessionUsage.unknownModel,
    usageUnknownSession => l10n.sessionUsage.unknownSession,
    usageUnknownTeam => l10n.sessionUsage.unknownTeam,
    usageSimpleSeat => l10n.sessionUsage.simpleSeat,
    _ => group.label,
  };
}

/// Label for a usage range preset.
///
/// `UsageRange.custom` has no preset label and uses all-time as a neutral
/// fallback.
String usageRangeLabel(BuildContext context, UsageRange range) {
  final l10n = context.l10n;
  return switch (range) {
    UsageRange.today => l10n.sessionUsage.rangeToday,
    UsageRange.last24Hours => l10n.sessionUsage.rangeLast24Hours,
    UsageRange.sevenDays => l10n.sessionUsage.rangeSevenDays,
    UsageRange.fourteenDays => l10n.sessionUsage.rangeFourteenDays,
    UsageRange.thirtyDays => l10n.sessionUsage.rangeThirtyDays,
    UsageRange.all => l10n.sessionUsage.rangeAll,
    UsageRange.custom => l10n.sessionUsage.rangeAll,
  };
}

/// Shared height for the usage filter controls and search field.
const double usageFilterControlHeight = 40;
