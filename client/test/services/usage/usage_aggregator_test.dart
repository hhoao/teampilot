import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/session_member_binding.dart';
import 'package:teampilot/models/session_usage.dart';
import 'package:teampilot/models/session_usage_dashboard.dart';
import 'package:teampilot/models/session_usage_pricing.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/usage/usage_aggregator.dart';

final _now = DateTime(2026, 10, 26, 18).millisecondsSinceEpoch;

SessionUsageEvent _event({
  String id = 'r1',
  CliTool cli = CliTool.claude,
  String model = 'claude-sonnet-4',
  int input = 10,
  int output = 2,
  int cacheRead = 0,
  int cacheCreation = 0,
  UsageInputSemantics semantics = UsageInputSemantics.fresh,
  int? timestampMs,
  String sessionId = 's1',
  String memberId = '',
  String teamId = '',
}) {
  return SessionUsageEvent(
    requestId: id,
    cli: cli,
    model: model,
    inputTokens: input,
    outputTokens: output,
    cacheReadTokens: cacheRead,
    cacheCreationTokens: cacheCreation,
    inputSemantics: semantics,
    timestampMs: timestampMs ?? _now,
    sessionId: sessionId,
    memberId: memberId,
    teamId: teamId,
  );
}

UsageDashboard _build(
  List<SessionUsageEvent> events, {
  UsageFilter filter = const UsageFilter(),
  UsageAttribution attribution = const UsageAttribution(),
  UsagePricingCatalog pricing = const UsagePricingCatalog(),
}) {
  return buildUsageDashboard(
    events: events,
    attribution: attribution,
    filter: filter,
    nowMs: _now,
    pricing: pricing,
  );
}

void main() {
  test('normalizes total semantics and counts cache once', () {
    final total = _event(
      id: 'total',
      input: 100,
      output: 20,
      cacheRead: 30,
      cacheCreation: 10,
      semantics: UsageInputSemantics.total,
    );
    final fresh = _event(
      id: 'fresh',
      input: 100,
      output: 20,
      cacheRead: 30,
      cacheCreation: 10,
    );

    expect(usageFreshInputTokens(total), 60);
    expect(usageTotalTokens(total), 120);
    expect(usageFreshInputTokens(fresh), 100);
    expect(usageTotalTokens(fresh), 160);

    final dashboard = _build([total, fresh]);
    expect(dashboard.summary.freshInputTokens, 160);
    expect(dashboard.summary.totalTokens, 280);
    expect(dashboard.summary.cacheReadTokens, 60);
    expect(dashboard.summary.cacheCreationTokens, 20);
    expect(dashboard.summary.cacheHitRate, closeTo(60 / 220, 0.000001));
  });

  test('range windows start at local midnight', () {
    final today = DateTime(2026, 10, 26, 10).millisecondsSinceEpoch;
    final yesterday = DateTime(2026, 10, 25, 10).millisecondsSinceEpoch;
    final tenDaysAgo = DateTime(2026, 10, 16, 10).millisecondsSinceEpoch;
    final events = [
      _event(id: 'a', timestampMs: today),
      _event(id: 'b', timestampMs: yesterday),
      _event(id: 'c', timestampMs: tenDaysAgo),
    ];

    expect(
      _build(
        events,
        filter: const UsageFilter(range: UsageRange.today),
      ).summary.requests,
      1,
    );
    expect(
      _build(
        events,
        filter: const UsageFilter(range: UsageRange.sevenDays),
      ).summary.requests,
      2,
    );
    expect(
      _build(
        events,
        filter: const UsageFilter(range: UsageRange.thirtyDays),
      ).summary.requests,
      3,
    );
    expect(
      _build(
        events,
        filter: const UsageFilter(range: UsageRange.all),
      ).summary.requests,
      3,
    );
  });

  test('filters by CLI and groups by session, member, model, and CLI', () {
    final attribution = const UsageAttribution(
      sessionTitles: {'s1': 'Alpha', 's2': 'Beta'},
      teamNames: {'t1': 'Core'},
      memberNames: {'s1\u0000dev': 'Developer', 't1\u0000dev': 'Developer'},
    );
    final events = [
      _event(id: 'a', sessionId: 's1', memberId: 'dev', teamId: 't1'),
      _event(id: 'b', sessionId: 's1', memberId: 'dev', teamId: 't1'),
      _event(id: 'c', sessionId: 's2', cli: CliTool.codex, model: 'gpt-5'),
    ];

    final bySession = _build(
      events,
      attribution: attribution,
      filter: const UsageFilter(groupBy: UsageGroupBy.session),
    );
    expect(bySession.rows, hasLength(2));
    final alpha = bySession.rows.firstWhere((row) => row.label == 'Alpha');
    expect(alpha.requests, 2);
    expect(alpha.sessions, 1);

    final byMember = _build(
      events,
      attribution: attribution,
      filter: const UsageFilter(groupBy: UsageGroupBy.member),
    );
    final dev = byMember.rows.firstWhere((row) => row.label == 'Developer');
    expect(dev.subtitle, 'Core');
    expect(dev.requests, 2);
    expect(dev.clis, [CliTool.claude]);

    final byModel = _build(
      events,
      filter: const UsageFilter(groupBy: UsageGroupBy.model),
    );
    expect(
      byModel.rows.map((row) => row.label),
      containsAll(<String>['claude-sonnet-4', 'gpt-5']),
    );

    final byCli = _build(
      events,
      filter: const UsageFilter(groupBy: UsageGroupBy.cli),
    );
    expect(
      byCli.rows.map((row) => row.label),
      containsAll(<String>['claude', 'codex']),
    );

    final claudeOnly = _build(
      events,
      filter: const UsageFilter(cli: CliTool.claude),
    );
    expect(claudeOnly.summary.requests, 2);
  });

  test('search filters rows but leaves summary and chart intact', () {
    final attribution = const UsageAttribution(
      sessionTitles: {'s1': 'Alpha', 's2': 'Beta'},
    );
    final events = [
      _event(id: 'a', sessionId: 's1'),
      _event(id: 'b', sessionId: 's2'),
    ];

    final all = _build(events, attribution: attribution);
    final searched = _build(
      events,
      attribution: attribution,
      filter: const UsageFilter(query: 'alp'),
    );

    expect(searched.rows, hasLength(1));
    expect(searched.rows.single.label, 'Alpha');
    expect(searched.summary.requests, all.summary.requests);
    expect(searched.summary.totalTokens, all.summary.totalTokens);
    expect(
      searched.chart.map((day) => day.totalTokens),
      all.chart.map((day) => day.totalTokens),
    );
  });

  test('simple seats group by session instead of one shared bucket', () {
    final attribution = const UsageAttribution(
      sessionTitles: {'s1': 'One', 's2': 'Two'},
    );
    final events = [
      _event(id: 'a', sessionId: 's1'),
      _event(id: 'b', sessionId: 's2'),
    ];

    final dashboard = _build(
      events,
      attribution: attribution,
      filter: const UsageFilter(groupBy: UsageGroupBy.member),
    );

    expect(dashboard.rows, hasLength(2));
    expect(dashboard.rows.map((row) => row.key), {'session:s1', 'session:s2'});
    expect(
      dashboard.rows.every((row) => row.subtitle == usageSimpleSeat),
      isTrue,
    );
  });

  test('unknown model and attribution fall back to sentinels/ids', () {
    final dashboard = _build([
      _event(
        id: 'a',
        model: '',
        sessionId: 's1',
        memberId: 'dev',
        teamId: 't1',
      ),
    ], filter: const UsageFilter(groupBy: UsageGroupBy.model));
    expect(dashboard.rows.single.label, usageUnknownModel);

    const attribution = UsageAttribution();
    expect(attribution.sessionTitle('s1'), 's1');
    expect(attribution.sessionTitle(''), usageUnknownSession);
    expect(attribution.teamName('t1'), 't1');
    expect(attribution.teamName(''), usageUnknownTeam);
    expect(
      attribution.memberName(sessionId: 's1', teamId: 't1', memberId: 'dev'),
      'dev',
    );
    expect(
      attribution.memberName(sessionId: 's1', teamId: 't1', memberId: ''),
      usageSimpleSeat,
    );
  });

  test('builds attribution from sessions and teams', () {
    final team = const TeamProfile(
      id: 't1',
      name: 'Core',
      members: [TeamMemberConfig(id: 'dev', name: 'Developer')],
    );
    final session = AppSession(
      sessionId: 's1',
      workspaceId: 'w1',
      display: 'Alpha',
      profileId: 't1',
      sessionTeam: 't1',
      members: const [
        SessionMemberBinding(rosterMemberId: 'dev', taskId: 'task-1'),
      ],
      createdAt: 1,
    );

    final attribution = UsageAttribution.fromSessionsAndTeams(
      sessions: [session],
      teams: [team],
    );

    expect(attribution.sessionTitle('s1'), 'Alpha');
    expect(attribution.teamName('t1'), 'Core');
    expect(
      attribution.memberName(sessionId: 's1', teamId: 't1', memberId: 'dev'),
      'Developer',
    );
  });

  test('chart has seven local-day buckets and CLI slices use seven days', () {
    final yesterday = DateTime(2026, 10, 25, 10).millisecondsSinceEpoch;
    final events = [
      _event(id: 'a', timestampMs: _now),
      _event(id: 'b', timestampMs: yesterday, cli: CliTool.codex),
    ];

    final dashboard = _build(
      events,
      filter: const UsageFilter(range: UsageRange.today),
    );

    expect(dashboard.summary.requests, 1);
    expect(dashboard.chart, hasLength(7));
    final today = dashboard.chart.last;
    expect(usageIsToday(today.dayStartMs, _now), isTrue);
    expect(today.totalTokens, 12);
    expect(
      dashboard.cliSlices.map((slice) => slice.cli),
      containsAll(<CliTool>[CliTool.claude, CliTool.codex]),
    );
    expect(
      dashboard.cliSlices.fold<double>(0, (sum, slice) => sum + slice.share),
      closeTo(1, 0.000001),
    );
  });

  test('sorts groups by total and exposes empty dashboard defaults', () {
    final dashboard = _build([
      _event(id: 'small', input: 1, output: 0),
      _event(id: 'large', input: 100, output: 0, sessionId: 's2'),
    ]);
    expect(dashboard.rows.first.label, 's2');
    expect(dashboard.matchedEventCount, 2);

    final empty = _build(const []);
    expect(empty.summary.totalTokens, 0);
    expect(empty.summary.cacheHitRate, 0);
    expect(empty.rows, isEmpty);
    expect(empty.chart, hasLength(7));
    expect(empty.cliSlices, isEmpty);
  });

  test('calculates priced cost and counts unpriced events', () {
    final dashboard = _build([
      _event(
        id: 'priced',
        model: 'claude-sonnet-4-5',
        input: 1000000,
        output: 1000000,
      ),
      _event(id: 'unpriced', model: 'unknown-model', input: 1000000, output: 0),
    ], pricing: UsagePricingCatalog.builtIn());

    expect(dashboard.summary.pricedEvents, 1);
    expect(dashboard.summary.unpricedEvents, 1);
    expect(dashboard.summary.costMicroUsd, 18000000);
    expect(dashboard.rows.single.pricedEvents, 1);
    expect(dashboard.rows.single.unpricedEvents, 1);
    expect(dashboard.rows.single.costMicroUsd, 18000000);
  });
}
