import '../../models/session_usage.dart';
import '../../models/session_usage_dashboard.dart';
import '../../models/session_usage_pricing.dart';
import '../../models/team_config.dart';
import 'usage_cost_calculator.dart';

/// Input tokens excluding cache, for both wire semantics.
int usageFreshInputTokens(SessionUsageEvent event) => event.freshInputTokens;

/// Billed total. Cache is included once and never double-counted.
int usageTotalTokens(SessionUsageEvent event) =>
    event.freshInputTokens +
    event.outputTokens +
    event.cacheReadTokens +
    event.cacheCreationTokens;

/// Local-midnight start of the selected window, or null for all time.
int? usageRangeStartMs(UsageRange range, int nowMs) {
  if (range == UsageRange.all) return null;
  final now = DateTime.fromMillisecondsSinceEpoch(nowMs).toLocal();
  final today = DateTime(now.year, now.month, now.day);
  final days = switch (range) {
    UsageRange.today => 0,
    UsageRange.sevenDays => 6,
    UsageRange.thirtyDays => 29,
    UsageRange.all => 0,
  };
  return today.subtract(Duration(days: days)).millisecondsSinceEpoch;
}

/// True when [dayStartMs] is the local day containing [nowMs].
bool usageIsToday(int dayStartMs, int nowMs) {
  final a = DateTime.fromMillisecondsSinceEpoch(dayStartMs).toLocal();
  final b = DateTime.fromMillisecondsSinceEpoch(nowMs).toLocal();
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

UsageDashboard buildUsageDashboard({
  required List<SessionUsageEvent> events,
  required UsageAttribution attribution,
  required UsageFilter filter,
  required int nowMs,
  UsagePricingCatalog pricing = const UsagePricingCatalog(),
}) {
  final rangeStart = usageRangeStartMs(filter.range, nowMs);
  final scoped = events
      .where((event) {
        if (rangeStart != null && event.timestampMs < rangeStart) return false;
        if (filter.cli != null && event.cli != filter.cli) return false;
        return true;
      })
      .toList(growable: false);

  final summary = _summarize(scoped, pricing);
  final query = filter.query.trim().toLowerCase();
  var rows = _group(scoped, filter.groupBy, attribution, pricing);
  if (query.isNotEmpty) {
    rows = rows
        .where((row) {
          return row.label.toLowerCase().contains(query) ||
              row.subtitle.toLowerCase().contains(query) ||
              row.key.toLowerCase().contains(query);
        })
        .toList(growable: false);
  }

  final sevenStart = usageRangeStartMs(UsageRange.sevenDays, nowMs)!;
  final sevenDayEvents = events
      .where((event) => event.timestampMs >= sevenStart)
      .toList(growable: false);

  return UsageDashboard(
    summary: summary,
    rows: rows,
    chart: _chart(sevenDayEvents, nowMs),
    cliSlices: _cliSlices(sevenDayEvents),
    heatmap: _heatmap(events, filter.cli, pricing),
    matchedEventCount: rows.fold(0, (sum, row) => sum + row.requests),
    totalEventCount: events.length,
  );
}

UsageSummary _summarize(
  List<SessionUsageEvent> events,
  UsagePricingCatalog pricing,
) {
  var fresh = 0;
  var output = 0;
  var cacheRead = 0;
  var cacheCreation = 0;
  var cost = 0;
  var priced = 0;
  var unpriced = 0;
  final sessions = <String>{};

  for (final event in events) {
    fresh += event.freshInputTokens;
    output += event.outputTokens;
    cacheRead += event.cacheReadTokens;
    cacheCreation += event.cacheCreationTokens;
    final unit = calculateUsageCost(event, pricing);
    if (unit.microUsd != null) {
      cost += unit.microUsd!;
      priced++;
    } else {
      unpriced++;
    }
    if (event.sessionId.trim().isNotEmpty) sessions.add(event.sessionId);
  }

  final cacheBase = fresh + cacheRead;
  return UsageSummary(
    totalTokens: fresh + output + cacheRead + cacheCreation,
    freshInputTokens: fresh,
    outputTokens: output,
    cacheReadTokens: cacheRead,
    cacheCreationTokens: cacheCreation,
    requests: events.length,
    sessions: sessions.length,
    cacheHitRate: cacheBase == 0 ? 0 : (cacheRead / cacheBase).clamp(0, 1),
    costMicroUsd: cost,
    pricedEvents: priced,
    unpricedEvents: unpriced,
  );
}

List<UsageGroup> _group(
  List<SessionUsageEvent> events,
  UsageGroupBy groupBy,
  UsageAttribution attribution,
  UsagePricingCatalog pricing,
) {
  final groups = <String, _GroupAccumulator>{};

  for (final event in events) {
    final (key, label, subtitle) = switch (groupBy) {
      UsageGroupBy.session => (
        'session:${event.sessionId}',
        attribution.sessionTitle(event.sessionId),
        event.teamId.trim().isEmpty ? '' : attribution.teamName(event.teamId),
      ),
      UsageGroupBy.member =>
        event.memberId.trim().isEmpty
            ? (
                'session:${event.sessionId}',
                attribution.sessionTitle(event.sessionId),
                usageSimpleSeat,
              )
            : (
                'member:${event.teamId}\u0000${event.memberId}',
                attribution.memberName(
                  sessionId: event.sessionId,
                  teamId: event.teamId,
                  memberId: event.memberId,
                ),
                attribution.teamName(event.teamId),
              ),
      UsageGroupBy.model => (
        'model:${event.model}',
        event.model.trim().isEmpty ? usageUnknownModel : event.model.trim(),
        '',
      ),
      UsageGroupBy.cli => ('cli:${event.cli.value}', event.cli.value, ''),
    };

    final group = groups.putIfAbsent(
      key,
      () => _GroupAccumulator(key, label, subtitle),
    );
    group.add(event, calculateUsageCost(event, pricing));
  }

  final rows = groups.values.map((group) => group.build()).toList();
  rows.sort((a, b) {
    final byTotal = b.totalTokens.compareTo(a.totalTokens);
    return byTotal != 0 ? byTotal : a.label.compareTo(b.label);
  });
  return List.unmodifiable(rows);
}

List<UsageChartDay> _chart(List<SessionUsageEvent> events, int nowMs) {
  final now = DateTime.fromMillisecondsSinceEpoch(nowMs).toLocal();
  final today = DateTime(now.year, now.month, now.day);
  final start = today.subtract(const Duration(days: 6));
  final buckets = <int, Map<CliTool, int>>{};
  for (var i = 0; i < 7; i++) {
    final day = start.add(Duration(days: i));
    buckets[day.millisecondsSinceEpoch] = <CliTool, int>{};
  }

  for (final event in events) {
    final local = DateTime.fromMillisecondsSinceEpoch(
      event.timestampMs,
    ).toLocal();
    final dayStart = DateTime(
      local.year,
      local.month,
      local.day,
    ).millisecondsSinceEpoch;
    final bucket = buckets[dayStart];
    if (bucket == null) continue;
    bucket[event.cli] = (bucket[event.cli] ?? 0) + usageTotalTokens(event);
  }

  return List.unmodifiable([
    for (final entry in buckets.entries)
      UsageChartDay(
        dayStartMs: entry.key,
        tokensByCli: Map.unmodifiable(entry.value),
      ),
  ]);
}

List<UsageCliSlice> _cliSlices(List<SessionUsageEvent> events) {
  final totals = <CliTool, int>{};
  final requests = <CliTool, int>{};
  for (final event in events) {
    totals[event.cli] = (totals[event.cli] ?? 0) + usageTotalTokens(event);
    requests[event.cli] = (requests[event.cli] ?? 0) + 1;
  }
  final grandTotal = totals.values.fold(0, (sum, value) => sum + value);
  final slices = [
    for (final entry in totals.entries)
      UsageCliSlice(
        cli: entry.key,
        totalTokens: entry.value,
        requests: requests[entry.key] ?? 0,
        share: grandTotal == 0 ? 0 : entry.value / grandTotal,
      ),
  ];
  slices.sort((a, b) => b.totalTokens.compareTo(a.totalTokens));
  return List.unmodifiable(slices);
}

final class _GroupAccumulator {
  _GroupAccumulator(this.key, this.label, this.subtitle);

  final String key;
  final String label;
  final String subtitle;
  final Set<CliTool> clis = {};
  final Set<String> sessions = {};
  var totalTokens = 0;
  var freshInputTokens = 0;
  var outputTokens = 0;
  var cacheReadTokens = 0;
  var cacheCreationTokens = 0;
  var requests = 0;
  var lastUsedMs = 0;
  var costMicroUsd = 0;
  var pricedEvents = 0;
  var unpricedEvents = 0;

  void add(SessionUsageEvent event, UsageCost cost) {
    totalTokens += usageTotalTokens(event);
    freshInputTokens += event.freshInputTokens;
    outputTokens += event.outputTokens;
    cacheReadTokens += event.cacheReadTokens;
    cacheCreationTokens += event.cacheCreationTokens;
    requests++;
    clis.add(event.cli);
    if (event.sessionId.trim().isNotEmpty) sessions.add(event.sessionId);
    if (event.timestampMs > lastUsedMs) lastUsedMs = event.timestampMs;
    if (cost.microUsd != null) {
      costMicroUsd += cost.microUsd!;
      pricedEvents++;
    } else {
      unpricedEvents++;
    }
  }

  UsageGroup build() {
    final sortedClis = clis.toList()
      ..sort((a, b) => a.index.compareTo(b.index));
    return UsageGroup(
      key: key,
      label: label,
      subtitle: subtitle,
      clis: List.unmodifiable(sortedClis),
      totalTokens: totalTokens,
      freshInputTokens: freshInputTokens,
      outputTokens: outputTokens,
      cacheReadTokens: cacheReadTokens,
      cacheCreationTokens: cacheCreationTokens,
      requests: requests,
      sessions: sessions.length,
      lastUsedMs: lastUsedMs,
      costMicroUsd: costMicroUsd,
      pricedEvents: pricedEvents,
      unpricedEvents: unpricedEvents,
    );
  }
}

class _HeatmapAccumulator {
  int tokens = 0;
  int requests = 0;
  int costMicroUsd = 0;
  int freshInput = 0;
  int cacheRead = 0;
}

List<UsageHeatmapDay> _heatmap(
  List<SessionUsageEvent> events,
  CliTool? cli,
  UsagePricingCatalog pricing,
) {
  final buckets = <int, _HeatmapAccumulator>{};
  for (final event in events) {
    if (cli != null && event.cli != cli) continue;
    final local = DateTime.fromMillisecondsSinceEpoch(
      event.timestampMs,
    ).toLocal();
    final dayStart = DateTime(
      local.year,
      local.month,
      local.day,
    ).millisecondsSinceEpoch;
    final bucket = buckets.putIfAbsent(dayStart, _HeatmapAccumulator.new);
    bucket
      ..tokens += usageTotalTokens(event)
      ..requests += 1
      ..freshInput += event.freshInputTokens
      ..cacheRead += event.cacheReadTokens;
    final unit = calculateUsageCost(event, pricing);
    if (unit.microUsd != null) bucket.costMicroUsd += unit.microUsd!;
  }

  final dayStarts = buckets.keys.toList()..sort();
  return List.unmodifiable([
    for (final dayStart in dayStarts)
      UsageHeatmapDay(
        dayStartMs: dayStart,
        tokens: buckets[dayStart]!.tokens,
        requests: buckets[dayStart]!.requests,
        costMicroUsd: buckets[dayStart]!.costMicroUsd,
        cacheHitRate: _heatmapHitRate(buckets[dayStart]!),
      ),
  ]);
}

double? _heatmapHitRate(_HeatmapAccumulator bucket) {
  final base = bucket.freshInput + bucket.cacheRead;
  return base == 0 ? null : bucket.cacheRead / base;
}
