import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/session_usage_dashboard.dart';
import 'package:teampilot/pages/usage/widgets/usage_heatmap_layout.dart';

final _now = DateTime(2026, 10, 28, 12).millisecondsSinceEpoch;

UsageHeatmapDay _day(
  DateTime date, {
  int tokens = 100,
  int requests = 1,
  int costMicroUsd = 0,
  double? hitRate,
}) {
  return UsageHeatmapDay(
    dayStartMs: DateTime(date.year, date.month, date.day).millisecondsSinceEpoch,
    tokens: tokens,
    requests: requests,
    costMicroUsd: costMicroUsd,
    cacheHitRate: hitRate,
  );
}

void main() {
  test('span count covers the earliest day', () {
    expect(usageHeatmapSpanCount(const [], _now), 0);
    expect(usageHeatmapSpanCount([_day(DateTime(2026, 10, 28))], _now), 1);
    expect(usageHeatmapSpanCount([_day(DateTime(2025, 10, 27))], _now), 1);
    expect(usageHeatmapSpanCount([_day(DateTime(2025, 10, 26))], _now), 2);
    expect(usageHeatmapSpanCount([_day(DateTime(2024, 10, 1))], _now), 3);
  });

  test('span zero starts on a Monday and ends today', () {
    final spans = usageHeatmapSpans(
      days: [_day(DateTime(2026, 10, 25))],
      nowMs: _now,
    );
    final span = spans.single;
    final start = DateTime.fromMillisecondsSinceEpoch(span.startDayMs);
    final end = DateTime.fromMillisecondsSinceEpoch(span.endDayMs);

    expect(start.weekday, DateTime.monday);
    expect(start.year, 2025);
    expect(start.month, 10);
    expect(start.day, 27);
    expect(end, DateTime(2026, 10, 28));
    expect(span.weekDayStarts.length, usageHeatmapWeeks);
    expect(span.weekDayStarts.every((week) => week.length == 7), isTrue);
    expect(
      span.weekDayStarts.last.last,
      greaterThan(DateTime(2026, 10, 28).millisecondsSinceEpoch),
    );
  });

  test('older spans end the day before the newer span starts', () {
    final spans = usageHeatmapSpans(
      days: [_day(DateTime(2025, 10, 20), tokens: 5)],
      nowMs: _now,
    );
    expect(spans.length, 2);
    final olderEnd = DateTime.fromMillisecondsSinceEpoch(spans[1].endDayMs);
    expect(
      DateTime(olderEnd.year, olderEnd.month, olderEnd.day),
      DateTime(2025, 10, 26),
    );
  });

  test('span totals exclude future cells', () {
    final today = DateTime(2026, 10, 28);
    final spans = usageHeatmapSpans(
      days: [
        _day(today, tokens: 10, requests: 2, costMicroUsd: 7),
        _day(DateTime(2026, 10, 26), tokens: 5, requests: 1, costMicroUsd: 3),
      ],
      nowMs: _now,
    );
    expect(spans.single.tokens, 15);
    expect(spans.single.requests, 3);
    expect(spans.single.costMicroUsd, 10);
  });

  test('thresholds and levels follow quartiles', () {
    expect(usageHeatmapThresholds(const []), [
      double.infinity,
      double.infinity,
      double.infinity,
    ]);
    final thresholds = usageHeatmapThresholds([1, 2, 3, 4]);
    expect(thresholds, [2, 3, 4]);
    expect(usageHeatmapLevel(null, thresholds), 0);
    expect(usageHeatmapLevel(1, thresholds), 1);
    expect(usageHeatmapLevel(2, thresholds), 1);
    expect(usageHeatmapLevel(2.5, thresholds), 2);
    expect(usageHeatmapLevel(3.5, thresholds), 3);
    expect(usageHeatmapLevel(5, thresholds), 4);
  });

  test('local day start ignores the time of day', () {
    final first = usageHeatmapLocalDayStart(
      DateTime(2026, 10, 28, 0, 1).millisecondsSinceEpoch,
    );
    final last = usageHeatmapLocalDayStart(
      DateTime(2026, 10, 28, 23, 59).millisecondsSinceEpoch,
    );
    expect(first, last);
    expect(first, DateTime(2026, 10, 28).millisecondsSinceEpoch);
  });
}
