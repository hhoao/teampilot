import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/cursor_usage_range.dart';
import 'package:teampilot/models/cursor_usage_report.dart';
import 'package:teampilot/services/cursor_usage/cursor_usage_cache.dart';

int ms(int day) => DateTime(2026, 10, day).millisecondsSinceEpoch;

CursorUsageEvent event(
  String id,
  int day, {
  String model = 'cursor-grok-4.6-high',
  int input = 10,
  int output = 5,
  int cacheRead = 100,
  int cacheWrite = 0,
  double totalCents = 2,
}) => CursorUsageEvent(
  eventId: id,
  timestampMs: ms(day) + 1000,
  model: model,
  kind: 'USAGE_EVENT_KIND_INCLUDED_IN_PRO',
  inputTokens: input,
  outputTokens: output,
  cacheReadTokens: cacheRead,
  cacheWriteTokens: cacheWrite,
  totalCents: totalCents,
);

void main() {
  test('replaces a covered window instead of double counting', () {
    final window = CursorUsageWindow(startMs: ms(1), endMs: ms(2) + 86399999);
    var cache = applyCursorUsageEvents(CursorUsageCache(accountId: 'a'), [
      event('e1', 1),
      event('e2', 2),
    ], window: window);
    cache = applyCursorUsageEvents(cache, [
      event('e1', 1),
      event('e3', 2),
    ], window: window);

    final report = buildCursorUsageReport(cache, window: window);
    expect(report.eventCount, 2);
    expect(report.inputTokens, 20);
    expect(cache.events.map((e) => e.eventId), containsAll(['e1', 'e3']));
    expect(cache.events.any((e) => e.eventId == 'e2'), isFalse);
  });

  test('aggregates days and models for the requested window', () {
    final window = CursorUsageWindow(startMs: ms(1), endMs: ms(3) + 86399999);
    final cache = applyCursorUsageEvents(CursorUsageCache(accountId: 'a'), [
      event('e1', 1, input: 10),
      event('e2', 1, model: 'composer-2.5-fast', input: 4),
      event('e3', 3, input: 6),
    ], window: window);

    final report = buildCursorUsageReport(cache, window: window);
    expect(report.days.length, 2);
    expect(report.days.first.dayMs, ms(1));
    expect(report.days.first.inputTokens, 14);
    expect(report.models.length, 2);
    expect(report.models['cursor-grok-4.6-high']!.eventCount, 2);
    expect(report.summaryOnly, isFalse);
  });

  test('a window outside the raw retention window is summary only', () {
    final cache = CursorUsageCache(
      accountId: 'a',
      coverage: [CursorUsageWindow(startMs: ms(1), endMs: ms(2) + 86399999)],
      days: [CursorUsageDay(dayMs: ms(1), inputTokens: 99, eventCount: 1)],
      events: const [],
    );
    final report = buildCursorUsageReport(
      cache,
      window: CursorUsageWindow(startMs: ms(1), endMs: ms(2) + 86399999),
    );
    expect(report.summaryOnly, isTrue);
    expect(report.inputTokens, 99);
  });

  test('trim drops events older than the retention window', () {
    final nowMs = ms(20);
    final cache = applyCursorUsageEvents(CursorUsageCache(accountId: 'a'), [
      event('old', 1),
      event('new', 19),
    ], window: CursorUsageWindow(startMs: ms(1), endMs: ms(19) + 86399999));
    final trimmed = trimCursorUsageCache(cache, nowMs: nowMs, retentionDays: 5);
    expect(trimmed.events.map((e) => e.eventId), ['new']);
    expect(trimmed.days.length, 2);
  });
}
