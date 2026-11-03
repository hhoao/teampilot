import '../../models/cursor_usage_range.dart';

int cursorUsageDayStartMs(int ms) {
  final local = DateTime.fromMillisecondsSinceEpoch(ms).toLocal();
  return DateTime(local.year, local.month, local.day).millisecondsSinceEpoch;
}

int cursorUsageDayEndMs(int ms) {
  final local = DateTime.fromMillisecondsSinceEpoch(ms).toLocal();
  return DateTime(
        local.year,
        local.month,
        local.day + 1,
      ).millisecondsSinceEpoch -
      1;
}

/// Expands a window outward to whole local days.
CursorUsageWindow cursorUsageAlignWindow(CursorUsageWindow window) =>
    CursorUsageWindow(
      startMs: cursorUsageDayStartMs(window.startMs),
      endMs: cursorUsageDayEndMs(window.endMs),
    );

CursorUsageWindow cursorUsageResolveRange({
  required CursorUsageRange range,
  required int nowMs,
  CursorUsageWindow? billingCycle,
}) {
  final alignedCycle = billingCycle == null
      ? null
      : cursorUsageAlignWindow(billingCycle);
  switch (range) {
    case CursorUsageCustomRange(:final startMs, :final endMs):
      return cursorUsageAlignWindow(
        CursorUsageWindow(
          startMs: startMs <= endMs ? startMs : endMs,
          endMs: startMs <= endMs ? endMs : startMs,
        ),
      );
    case CursorUsagePresetRange(:final preset):
      final now = DateTime.fromMillisecondsSinceEpoch(nowMs).toLocal();
      final todayStart = DateTime(now.year, now.month, now.day);
      switch (preset) {
        case CursorUsagePreset.billingCycle:
          if (alignedCycle != null) return alignedCycle;
          return _windowFor(todayStart, DateTime(now.year, now.month, 1));
        case CursorUsagePreset.today:
          return _windowFor(todayStart, todayStart);
        case CursorUsagePreset.sevenDays:
          return _windowFor(
            todayStart,
            DateTime(now.year, now.month, now.day - 6),
          );
        case CursorUsagePreset.thirtyDays:
          return _windowFor(
            todayStart,
            DateTime(now.year, now.month, now.day - 29),
          );
      }
  }
}

CursorUsageWindow _windowFor(DateTime todayStart, DateTime start) =>
    CursorUsageWindow(
      startMs: start.millisecondsSinceEpoch,
      endMs: _endOfDay(todayStart),
    );

int _endOfDay(DateTime dayStart) =>
    DateTime(
      dayStart.year,
      dayStart.month,
      dayStart.day + 1,
    ).millisecondsSinceEpoch -
    1;

List<CursorUsageWindow> cursorUsageMergeWindows(
  Iterable<CursorUsageWindow> windows,
) {
  final sorted = windows.toList()
    ..sort((a, b) => a.startMs.compareTo(b.startMs));
  final out = <CursorUsageWindow>[];
  for (final window in sorted) {
    if (out.isEmpty) {
      out.add(window);
      continue;
    }
    final last = out.last;
    if (window.startMs <= last.endMs + 1) {
      out[out.length - 1] = CursorUsageWindow(
        startMs: last.startMs,
        endMs: window.endMs > last.endMs ? window.endMs : last.endMs,
      );
    } else {
      out.add(window);
    }
  }
  return List.unmodifiable(out);
}

/// Parts of [requested] that no covered window covers.
List<CursorUsageWindow> cursorUsageMissingWindows({
  required Iterable<CursorUsageWindow> covered,
  required CursorUsageWindow requested,
}) {
  final merged = cursorUsageMergeWindows(covered);
  final gaps = <CursorUsageWindow>[];
  var cursor = requested.startMs;
  for (final window in merged) {
    if (window.endMs < cursor) continue;
    if (window.startMs > requested.endMs) break;
    if (window.startMs > cursor) {
      gaps.add(
        cursorUsageAlignWindow(
          CursorUsageWindow(
            startMs: cursor,
            endMs: window.startMs - 1 < requested.endMs
                ? window.startMs - 1
                : requested.endMs,
          ),
        ),
      );
    }
    final next = window.endMs + 1;
    if (next > cursor) cursor = next;
    if (cursor > requested.endMs) break;
  }
  if (cursor <= requested.endMs) {
    gaps.add(
      cursorUsageAlignWindow(
        CursorUsageWindow(startMs: cursor, endMs: requested.endMs),
      ),
    );
  }
  return List.unmodifiable(gaps.where((gap) => gap.startMs <= gap.endMs));
}
