import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

import 'app_session.dart';
import 'team_config.dart';

/// Sentinels used by the pure aggregator when attribution cannot resolve a
/// human label. The UI localizes them; the aggregator stays l10n-free.
const String usageUnknownModel = '\u0000unknown-model';
const String usageUnknownSession = '\u0000unknown-session';
const String usageUnknownTeam = '\u0000unknown-team';
const String usageSimpleSeat = '\u0000simple-seat';

enum UsageRange { today, sevenDays, thirtyDays, all }

enum UsageGroupBy { session, member, model, cli }

/// Human labels resolved from the current session/team repositories.
///
/// Keys are namespaced so the same member id in two teams, or the same member
/// id in two sessions, cannot collide.
@immutable
final class UsageAttribution extends Equatable {
  const UsageAttribution({
    this.sessionTitles = const {},
    this.teamNames = const {},
    this.memberNames = const {},
  });

  factory UsageAttribution.fromSessionsAndTeams({
    required List<AppSession> sessions,
    required List<TeamProfile> teams,
  }) {
    final teamsById = {for (final team in teams) team.id: team};
    final sessionTitles = <String, String>{};
    final teamNames = <String, String>{};
    final memberNames = <String, String>{};

    for (final session in sessions) {
      final sessionId = session.sessionId.trim();
      if (sessionId.isEmpty) continue;
      final display = session.display.trim();
      sessionTitles[sessionId] = display.isEmpty ? sessionId : display;

      final team =
          teamsById[session.profileId] ?? teamsById[session.sessionTeam];
      if (team == null) continue;
      teamNames[team.id] = team.name;
      List<TeamMemberConfig> roster;
      try {
        roster = sessionRosterMembers(session, team);
      } on Object {
        // A malformed binding should not hide every other session's usage.
        roster = const [];
      }
      for (final member in roster) {
        final memberId = member.id.trim();
        if (memberId.isEmpty) continue;
        final name = member.name.trim().isEmpty ? memberId : member.name;
        memberNames['$sessionId\u0000$memberId'] = name;
        memberNames['${team.id}\u0000$memberId'] = name;
      }
    }

    return UsageAttribution(
      sessionTitles: Map.unmodifiable(sessionTitles),
      teamNames: Map.unmodifiable(teamNames),
      memberNames: Map.unmodifiable(memberNames),
    );
  }

  final Map<String, String> sessionTitles;
  final Map<String, String> teamNames;

  /// `<sessionId>\u0000<memberId>` and `<teamId>\u0000<memberId>`.
  final Map<String, String> memberNames;

  String sessionTitle(String sessionId) {
    final id = sessionId.trim();
    if (id.isEmpty) return usageUnknownSession;
    return sessionTitles[id] ?? id;
  }

  String teamName(String teamId) {
    final id = teamId.trim();
    if (id.isEmpty) return usageUnknownTeam;
    return teamNames[id] ?? id;
  }

  String memberName({
    required String sessionId,
    required String teamId,
    required String memberId,
  }) {
    final id = memberId.trim();
    if (id.isEmpty) return usageSimpleSeat;
    return memberNames['${sessionId.trim()}\u0000$id'] ??
        memberNames['${teamId.trim()}\u0000$id'] ??
        id;
  }

  @override
  List<Object?> get props => [sessionTitles, teamNames, memberNames];
}

@immutable
final class UsageFilter extends Equatable {
  const UsageFilter({
    this.range = UsageRange.all,
    this.cli,
    this.groupBy = UsageGroupBy.session,
    this.query = '',
  });

  final UsageRange range;
  final CliTool? cli;
  final UsageGroupBy groupBy;
  final String query;

  UsageFilter copyWith({
    UsageRange? range,
    CliTool? cli,
    bool clearCli = false,
    UsageGroupBy? groupBy,
    String? query,
  }) {
    return UsageFilter(
      range: range ?? this.range,
      cli: clearCli ? null : (cli ?? this.cli),
      groupBy: groupBy ?? this.groupBy,
      query: query ?? this.query,
    );
  }

  @override
  List<Object?> get props => [range, cli, groupBy, query];
}

@immutable
final class UsageSummary extends Equatable {
  const UsageSummary({
    this.totalTokens = 0,
    this.freshInputTokens = 0,
    this.outputTokens = 0,
    this.cacheReadTokens = 0,
    this.cacheCreationTokens = 0,
    this.requests = 0,
    this.sessions = 0,
    this.cacheHitRate = 0,
    this.costMicroUsd = 0,
    this.pricedEvents = 0,
    this.unpricedEvents = 0,
  });

  final int totalTokens;
  final int freshInputTokens;
  final int outputTokens;
  final int cacheReadTokens;
  final int cacheCreationTokens;
  final int requests;
  final int sessions;

  /// `cacheRead / (freshInput + cacheRead)`, clamped to 0..1.
  final double cacheHitRate;

  final int costMicroUsd;
  final int pricedEvents;
  final int unpricedEvents;

  @override
  List<Object?> get props => [
    totalTokens,
    freshInputTokens,
    outputTokens,
    cacheReadTokens,
    cacheCreationTokens,
    requests,
    sessions,
    cacheHitRate,
    costMicroUsd,
    pricedEvents,
    unpricedEvents,
  ];
}

@immutable
final class UsageGroup extends Equatable {
  const UsageGroup({
    required this.key,
    required this.label,
    this.subtitle = '',
    this.clis = const [],
    this.totalTokens = 0,
    this.freshInputTokens = 0,
    this.outputTokens = 0,
    this.cacheReadTokens = 0,
    this.cacheCreationTokens = 0,
    this.requests = 0,
    this.sessions = 0,
    this.lastUsedMs = 0,
    this.costMicroUsd = 0,
    this.pricedEvents = 0,
    this.unpricedEvents = 0,
  });

  /// Stable grouping key, e.g. `session:s1`, `member:team/dev`.
  final String key;
  final String label;
  final String subtitle;

  /// Sorted by [CliTool.index] so equality is deterministic.
  final List<CliTool> clis;

  final int totalTokens;
  final int freshInputTokens;
  final int outputTokens;
  final int cacheReadTokens;
  final int cacheCreationTokens;
  final int requests;
  final int sessions;
  final int lastUsedMs;
  final int costMicroUsd;
  final int pricedEvents;
  final int unpricedEvents;

  @override
  List<Object?> get props => [
    key,
    label,
    subtitle,
    clis,
    totalTokens,
    freshInputTokens,
    outputTokens,
    cacheReadTokens,
    cacheCreationTokens,
    requests,
    sessions,
    lastUsedMs,
    costMicroUsd,
    pricedEvents,
    unpricedEvents,
  ];
}

@immutable
final class UsageChartDay extends Equatable {
  const UsageChartDay({required this.dayStartMs, this.tokensByCli = const {}});

  final int dayStartMs;
  final Map<CliTool, int> tokensByCli;

  int get totalTokens =>
      tokensByCli.values.fold(0, (sum, value) => sum + value);

  @override
  List<Object?> get props => [dayStartMs, tokensByCli];
}

@immutable
final class UsageHeatmapDay extends Equatable {
  const UsageHeatmapDay({
    required this.dayStartMs,
    required this.tokens,
    required this.requests,
    required this.costMicroUsd,
    this.cacheHitRate,
  });

  /// Local midnight of the day.
  final int dayStartMs;

  /// Billed total tokens, same definition as the rest of the page.
  final int tokens;

  final int requests;
  final int costMicroUsd;

  /// `cacheRead / (freshInput + cacheRead)`, null when there was no input.
  final double? cacheHitRate;

  @override
  List<Object?> get props => [
    dayStartMs,
    tokens,
    requests,
    costMicroUsd,
    cacheHitRate,
  ];
}

@immutable
final class UsageCliSlice extends Equatable {
  const UsageCliSlice({
    required this.cli,
    required this.totalTokens,
    required this.requests,
    required this.share,
  });

  final CliTool cli;
  final int totalTokens;
  final int requests;

  /// Fraction of the last-seven-day total, 0..1.
  final double share;

  @override
  List<Object?> get props => [cli, totalTokens, requests, share];
}

@immutable
final class UsageDashboard extends Equatable {
  const UsageDashboard({
    this.summary = const UsageSummary(),
    this.rows = const [],
    this.chart = const [],
    this.cliSlices = const [],
    this.heatmap = const [],
    this.matchedEventCount = 0,
    this.totalEventCount = 0,
  });

  final UsageSummary summary;

  /// Range + CLI + search filtered groups, sorted by total descending.
  final List<UsageGroup> rows;

  /// Fixed last-seven-local-day buckets, all CLIs.
  final List<UsageChartDay> chart;

  /// Fixed last-seven-local-day CLI distribution, all CLIs.
  final List<UsageCliSlice> cliSlices;

  /// All-history local-day buckets, filtered by CLI only (ascending).
  final List<UsageHeatmapDay> heatmap;

  final int matchedEventCount;
  final int totalEventCount;

  @override
  List<Object?> get props => [
    summary,
    rows,
    chart,
    cliSlices,
    heatmap,
    matchedEventCount,
    totalEventCount,
  ];
}
