import 'dart:math' as math;

import '../../../models/session_usage_dashboard.dart';

/// Weeks in one heatmap span.
const int usageHeatmapWeeks = 53;

const int _daysPerWeek = 7;
const int _daysPerSpan = usageHeatmapWeeks * _daysPerWeek;

/// Local-midnight epoch millis for [ms].
int usageHeatmapLocalDayStart(int ms) {
  final local = DateTime.fromMillisecondsSinceEpoch(ms).toLocal();
  return DateTime(local.year, local.month, local.day).millisecondsSinceEpoch;
}

int _addDays(int ms, int days) {
  final local = DateTime.fromMillisecondsSinceEpoch(ms).toLocal();
  return DateTime(
    local.year,
    local.month,
    local.day + days,
  ).millisecondsSinceEpoch;
}

int _daysBetween(int fromMs, int toMs) {
  final from = DateTime.fromMillisecondsSinceEpoch(fromMs).toLocal();
  final to = DateTime.fromMillisecondsSinceEpoch(toMs).toLocal();
  return DateTime.utc(
    to.year,
    to.month,
    to.day,
  ).difference(DateTime.utc(from.year, from.month, from.day)).inDays;
}

int _thisMonday(int nowMs) {
  final today = usageHeatmapLocalDayStart(nowMs);
  final weekday = DateTime.fromMillisecondsSinceEpoch(today).weekday;
  return _addDays(today, 1 - weekday);
}

int _spanStart(int nowMs, int index) {
  final monday = _thisMonday(nowMs);
  return _addDays(
    monday,
    -((usageHeatmapWeeks - 1) * _daysPerWeek + index * _daysPerSpan),
  );
}

/// Number of 53-week spans needed to cover [days]; 0 when there is no data.
int usageHeatmapSpanCount(List<UsageHeatmapDay> days, int nowMs) {
  if (days.isEmpty) return 0;
  final earliest = usageHeatmapLocalDayStart(days.first.dayStartMs);
  final before = _daysBetween(earliest, _spanStart(nowMs, 0));
  if (before <= 0) return 1;
  return 1 + (before / _daysPerSpan).ceil();
}

/// One 53-week block, newest first.
final class UsageHeatmapSpan {
  const UsageHeatmapSpan({
    required this.startDayMs,
    required this.endDayMs,
    required this.weekDayStarts,
    required this.tokens,
    required this.requests,
    required this.costMicroUsd,
  });

  final int startDayMs;
  final int endDayMs;

  /// 53 weeks x 7 day-start millis, Monday-first.
  final List<List<int>> weekDayStarts;

  final int tokens;
  final int requests;
  final int costMicroUsd;
}

List<UsageHeatmapSpan> usageHeatmapSpans({
  required List<UsageHeatmapDay> days,
  required int nowMs,
}) {
  final count = usageHeatmapSpanCount(days, nowMs);
  if (count == 0) return const [];
  final byDay = {
    for (final day in days) usageHeatmapLocalDayStart(day.dayStartMs): day,
  };
  final today = usageHeatmapLocalDayStart(nowMs);
  final spans = <UsageHeatmapSpan>[];
  for (var index = 0; index < count; index++) {
    final start = _spanStart(nowMs, index);
    final end = index == 0
        ? today
        : _addDays(_spanStart(nowMs, index - 1), -1);
    final weeks = <List<int>>[];
    var tokens = 0;
    var requests = 0;
    var costMicroUsd = 0;
    for (var week = 0; week < usageHeatmapWeeks; week++) {
      final column = <int>[];
      for (var day = 0; day < _daysPerWeek; day++) {
        final dayStart = _addDays(start, week * _daysPerWeek + day);
        column.add(dayStart);
        if (dayStart > today) continue;
        final data = byDay[dayStart];
        if (data == null) continue;
        tokens += data.tokens;
        requests += data.requests;
        costMicroUsd += data.costMicroUsd;
      }
      weeks.add(List.unmodifiable(column));
    }
    spans.add(
      UsageHeatmapSpan(
        startDayMs: start,
        endDayMs: end,
        weekDayStarts: List.unmodifiable(weeks),
        tokens: tokens,
        requests: requests,
        costMicroUsd: costMicroUsd,
      ),
    );
  }
  return List.unmodifiable(spans);
}

/// Quartile thresholds over [values]; empty input uses infinities (level 0).
List<double> usageHeatmapThresholds(Iterable<double> values) {
  final sorted = values.where((value) => value.isFinite).toList()..sort();
  if (sorted.isEmpty) {
    return const [double.infinity, double.infinity, double.infinity];
  }
  double at(double quantile) {
    final index = math.min(
      sorted.length - 1,
      (sorted.length * quantile).floor(),
    );
    return sorted[index];
  }

  return [at(0.25), at(0.5), at(0.75)];
}

int usageHeatmapLevel(double? value, List<double> thresholds) {
  if (value == null) return 0;
  if (value <= thresholds[0]) return 1;
  if (value <= thresholds[1]) return 2;
  if (value <= thresholds[2]) return 3;
  return 4;
}
