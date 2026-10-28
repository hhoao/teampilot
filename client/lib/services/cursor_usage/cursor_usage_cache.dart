import '../../models/cursor_usage_range.dart';
import '../../models/cursor_usage_report.dart';
import 'cursor_usage_range_math.dart';

/// Adds [incoming] to [cache], first dropping anything previously stored inside
/// [window] so a re-fetch of the same range replaces rather than duplicates.
CursorUsageCache applyCursorUsageEvents(
  CursorUsageCache cache,
  List<CursorUsageEvent> incoming, {
  required CursorUsageWindow window,
  String? owningUser,
}) {
  final aligned = cursorUsageAlignWindow(window);
  final keptEvents = cache.events
      .where((event) => !aligned.contains(event.timestampMs))
      .toList();
  final byId = <String, CursorUsageEvent>{
    for (final event in keptEvents) event.eventId: event,
  };
  for (final event in incoming) {
    if (!aligned.contains(event.timestampMs)) continue;
    byId[event.eventId] = event;
  }

  final keptDays = cache.days
      .where((day) => !aligned.contains(day.dayMs))
      .toList();
  final daysByStart = <int, CursorUsageDay>{
    for (final day in keptDays) day.dayMs: day,
  };
  for (final event in byId.values) {
    if (!aligned.contains(event.timestampMs)) continue;
    final dayMs = cursorUsageDayStartMs(event.timestampMs);
    final totals = event.totals;
    final previous = daysByStart[dayMs] ?? CursorUsageDay(dayMs: dayMs);
    final models = <String, CursorUsageModelTotals>{...previous.models};
    models[event.model] =
        (models[event.model] ?? const CursorUsageModelTotals()).merge(totals);
    daysByStart[dayMs] = CursorUsageDay(
      dayMs: dayMs,
      inputTokens: previous.inputTokens + event.inputTokens,
      outputTokens: previous.outputTokens + event.outputTokens,
      cacheReadTokens: previous.cacheReadTokens + event.cacheReadTokens,
      cacheWriteTokens: previous.cacheWriteTokens + event.cacheWriteTokens,
      totalCents: previous.totalCents + event.totalCents,
      chargedCents: previous.chargedCents + event.chargedCents,
      eventCount: previous.eventCount + 1,
      models: models,
    );
  }

  final days = daysByStart.values.toList()
    ..sort((a, b) => a.dayMs.compareTo(b.dayMs));
  final events = byId.values.toList()
    ..sort((a, b) => b.timestampMs.compareTo(a.timestampMs));

  return cache.copyWith(
    owningUser: owningUser ?? cache.owningUser,
    coverage: cursorUsageMergeWindows([...cache.coverage, aligned]),
    days: days,
    events: events,
  );
}

CursorUsageCache trimCursorUsageCache(
  CursorUsageCache cache, {
  required int nowMs,
  int retentionDays = 90,
}) {
  final cutoff = cursorUsageDayStartMs(
    DateTime.fromMillisecondsSinceEpoch(
      nowMs,
    ).subtract(Duration(days: retentionDays)).millisecondsSinceEpoch,
  );
  final events = cache.events
      .where((event) => event.timestampMs >= cutoff)
      .toList(growable: false);
  return cache.copyWith(events: events);
}

CursorUsageReport buildCursorUsageReport(
  CursorUsageCache cache, {
  required CursorUsageWindow window,
}) {
  final aligned = cursorUsageAlignWindow(window);
  final days = cache.days
      .where((day) => aligned.contains(day.dayMs))
      .toList(growable: false);
  final events = cache.events
      .where((event) => aligned.contains(event.timestampMs))
      .toList(growable: false);

  var inputTokens = 0;
  var outputTokens = 0;
  var cacheReadTokens = 0;
  var cacheWriteTokens = 0;
  var totalCents = 0.0;
  var chargedCents = 0.0;
  var eventCount = 0;
  final models = <String, CursorUsageModelTotals>{};
  for (final day in days) {
    inputTokens += day.inputTokens;
    outputTokens += day.outputTokens;
    cacheReadTokens += day.cacheReadTokens;
    cacheWriteTokens += day.cacheWriteTokens;
    totalCents += day.totalCents;
    chargedCents += day.chargedCents;
    eventCount += day.eventCount;
    for (final entry in day.models.entries) {
      models[entry.key] = (models[entry.key] ?? const CursorUsageModelTotals())
          .merge(entry.value);
    }
  }

  return CursorUsageReport(
    accountId: cache.accountId,
    startMs: aligned.startMs,
    endMs: aligned.endMs,
    inputTokens: inputTokens,
    outputTokens: outputTokens,
    cacheReadTokens: cacheReadTokens,
    cacheWriteTokens: cacheWriteTokens,
    totalCents: totalCents,
    chargedCents: chargedCents,
    eventCount: eventCount,
    days: days,
    models: models,
    events: events,
    summaryOnly: events.isEmpty && eventCount > 0,
  );
}
