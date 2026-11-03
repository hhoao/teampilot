# Usage Heatmap Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a cc-switch-style 53-week usage heatmap card to the session usage page, backed by a day-level series derived from the existing event stream.

**Architecture:** A new `UsageHeatmapDay` model is aggregated in `buildUsageDashboard` (CLI-filtered only) and exposed on `UsageDashboard.heatmap`. Pure calendar/threshold math lives in `usage_heatmap_layout.dart`; `usage_heatmap_card.dart` renders spans of 53×7 cells with a metric switch, tooltips and a "Show earlier" toggle. The page inserts the card between the cost card and the trend row.

**Tech Stack:** Flutter 3.47 / Dart 3.8, `intl` (already a dependency), `shared_ui` (`TpTextStyles`, `TpSegmentedControl`), `flutter_bloc` usage page.

## Global Constraints

- Spec: `docs/superpowers/specs/2026-10-29-usage-heatmap-design.md`.
- Do not add dependencies; `intl` and `shared_ui` already exist.
- Never run `flutter test` directly; use `cd client && dart run tool/run_tests.dart <path>`.
- Text styles only via `TpTextStyles` named getters; no inline `TextStyle(...)` or `fontSize`/`fontWeight` via `copyWith`. Setting `color` via `copyWith` is allowed.
- l10n: edit `client/lib/l10n/app_en.arb` and `app_zh.arb` only, then run `cd client && flutter gen-l10n` and commit the regenerated `lib/l10n/app_localizations*.dart`.
- The worktree contains unrelated modified files. Stage only the paths named in each task; never `git add -A` / `git commit -a`.
- Keep the heatmap independent of the page's range and query filters; it follows only `UsageFilter.cli`.
- Files: keep each new file under 500 lines (soft limit in `docs/CODE_QUALITY.md`).
- fl_chart is not used here: the heatmap is a custom grid of `Container`s + `Tooltip`s.

---

## File Map

| File | Responsibility |
|------|----------------|
| `client/lib/models/session_usage_dashboard.dart` | `UsageHeatmapDay` model + `UsageDashboard.heatmap` |
| `client/lib/services/usage/usage_aggregator.dart` | Day buckets from all events, CLI-filtered |
| `client/lib/pages/usage/widgets/usage_heatmap_layout.dart` | Pure span/calendar/threshold math |
| `client/lib/pages/usage/widgets/usage_heatmap_card.dart` | Heatmap card UI (metric switch, grid, tooltip, show earlier) |
| `client/lib/pages/usage/session_usage_page.dart` | Insert the card |
| `client/lib/l10n/app_en.arb`, `app_zh.arb` + generated | Nine new strings |
| `client/test/services/usage/usage_aggregator_test.dart` | Heatmap aggregation tests |
| `client/test/pages/usage/usage_heatmap_layout_test.dart` | Pure math tests |
| `client/test/pages/usage/usage_heatmap_card_test.dart` | Widget tests |
| `client/test/pages/usage/session_usage_page_test.dart` | Card presence |

---

### Task 1: Heatmap model and aggregation

**Files:**
- Modify: `client/lib/models/session_usage_dashboard.dart` (after `UsageChartDay`, and inside `UsageDashboard`)
- Modify: `client/lib/services/usage/usage_aggregator.dart` (imports, `buildUsageDashboard` return, new private helpers at end)
- Test: `client/test/services/usage/usage_aggregator_test.dart` (append tests)

**Interfaces:**
- Consumes: existing `SessionUsageEvent`, `UsageFilter.cli`, `calculateUsageCost`, `usageTotalTokens`.
- Produces: `UsageHeatmapDay` with `dayStartMs / tokens / requests / costMicroUsd / cacheHitRate`; `UsageDashboard.heatmap`.

- [ ] **Step 1: Write the failing tests**

Append to `client/test/services/usage/usage_aggregator_test.dart` (inside `main()`):

```dart
  test('heatmap buckets by local day and follows only the CLI filter', () {
    final evening = DateTime(2026, 10, 25, 23, 30).millisecondsSinceEpoch;
    final morning = DateTime(2026, 10, 26, 0, 10).millisecondsSinceEpoch;
    final dashboard = _build(
      [
        _event(id: 'a', input: 10, output: 2, timestampMs: evening),
        _event(id: 'b', cli: CliTool.codex, input: 5, output: 1, timestampMs: evening),
        _event(
          id: 'c',
          input: 3,
          output: 1,
          cacheRead: 6,
          timestampMs: morning,
        ),
      ],
      // A range that excludes both days must not affect the heatmap.
      filter: const UsageFilter(range: UsageRange.today, cli: CliTool.claude),
    );

    expect(dashboard.heatmap.length, 2);
    expect(
      dashboard.heatmap[0].dayStartMs,
      DateTime(2026, 10, 25).millisecondsSinceEpoch,
    );
    expect(dashboard.heatmap[0].tokens, 12);
    expect(dashboard.heatmap[0].requests, 1);
    expect(
      dashboard.heatmap[1].dayStartMs,
      DateTime(2026, 10, 26).millisecondsSinceEpoch,
    );
    expect(dashboard.heatmap[1].tokens, 10);
    expect(dashboard.heatmap[1].requests, 1);
    expect(dashboard.heatmap[1].cacheHitRate, closeTo(6 / 9, 1e-9));
    expect(dashboard.heatmap[0].cacheHitRate, 0);
  });

  test('heatmap prices days with the same catalog as the summary', () {
    const rule = UsagePriceRule(
      model: 'm',
      inputPerMillion: 3,
      outputPerMillion: 15,
      cacheReadPerMillion: 0.3,
      cacheWritePerMillion: 3.75,
      effectiveFromMs: 0,
      source: UsagePriceSource.user,
    );
    final dashboard = _build(
      [
        _event(
          id: 'priced',
          model: 'm',
          input: 1000000,
          output: 0,
          timestampMs: DateTime(2026, 10, 25, 9).millisecondsSinceEpoch,
        ),
      ],
      pricing: const UsagePricingCatalog(userRules: [rule]),
    );

    expect(dashboard.heatmap.single.costMicroUsd, 3000000);
  });

  test('empty events produce an empty heatmap', () {
    expect(_build(const []).heatmap, isEmpty);
  });
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd client && dart run tool/run_tests.dart test/services/usage/usage_aggregator_test.dart`
Expected: FAIL — `dashboard.heatmap` is not defined (or `UsageHeatmapDay` unresolved).

- [ ] **Step 3: Add the model**

In `client/lib/models/session_usage_dashboard.dart`, insert after the `UsageChartDay` class:

```dart
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
```

Then extend `UsageDashboard`:

```dart
  const UsageDashboard({
    this.summary = const UsageSummary(),
    this.rows = const [],
    this.chart = const [],
    this.cliSlices = const [],
    this.heatmap = const [],
    this.matchedEventCount = 0,
    this.totalEventCount = 0,
  });
```

Add the field with a doc comment:

```dart
  /// All-history local-day buckets, filtered by CLI only (ascending).
  final List<UsageHeatmapDay> heatmap;
```

Add `heatmap` to `props` after `cliSlices`.

- [ ] **Step 4: Add the aggregation**

In `client/lib/services/usage/usage_aggregator.dart`, add to the `UsageDashboard(...)` return in `buildUsageDashboard`:

```dart
    heatmap: _heatmap(events, filter.cli, pricing),
```

Append these private helpers at the end of the file:

```dart
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
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `cd client && dart run tool/run_tests.dart test/services/usage/usage_aggregator_test.dart`
Expected: PASS (all existing aggregator tests plus the three new ones).

- [ ] **Step 6: Analyze and commit**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings lib/models/session_usage_dashboard.dart lib/services/usage/usage_aggregator.dart`
Expected: `No issues found!`

```bash
cd /home/hhoa/git/hhoa/teampilot
git add client/lib/models/session_usage_dashboard.dart \
  client/lib/services/usage/usage_aggregator.dart \
  client/test/services/usage/usage_aggregator_test.dart
git commit -m "feat(usage): aggregate a daily usage heatmap series"
```

---

### Task 2: Heatmap layout math

**Files:**
- Create: `client/lib/pages/usage/widgets/usage_heatmap_layout.dart`
- Test: `client/test/pages/usage/usage_heatmap_layout_test.dart` (create)

**Interfaces:**
- Consumes: `UsageHeatmapDay` from Task 1.
- Produces:
  - `const int usageHeatmapWeeks`
  - `int usageHeatmapLocalDayStart(int ms)`
  - `int usageHeatmapSpanCount(List<UsageHeatmapDay> days, int nowMs)`
  - `final class UsageHeatmapSpan` (`startDayMs`, `endDayMs`, `weekDayStarts`, `tokens`, `requests`, `costMicroUsd`)
  - `List<UsageHeatmapSpan> usageHeatmapSpans({required List<UsageHeatmapDay> days, required int nowMs})`
  - `List<double> usageHeatmapThresholds(Iterable<double> values)`
  - `int usageHeatmapLevel(double? value, List<double> thresholds)`

- [ ] **Step 1: Write the failing tests**

Create `client/test/pages/usage/usage_heatmap_layout_test.dart`:

```dart
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd client && dart run tool/run_tests.dart test/pages/usage/usage_heatmap_layout_test.dart`
Expected: FAIL — the file `usage_heatmap_layout.dart` does not exist.

- [ ] **Step 3: Implement the layout math**

Create `client/lib/pages/usage/widgets/usage_heatmap_layout.dart`:

```dart
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
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd client && dart run tool/run_tests.dart test/pages/usage/usage_heatmap_layout_test.dart`
Expected: PASS (6 tests).

- [ ] **Step 5: Commit**

```bash
cd /home/hhoa/git/hhoa/teampilot
git add client/lib/pages/usage/widgets/usage_heatmap_layout.dart \
  client/test/pages/usage/usage_heatmap_layout_test.dart
git commit -m "feat(usage): add heatmap calendar layout math"
```

---

### Task 3: Heatmap card widget and strings

**Files:**
- Modify: `client/lib/l10n/app_en.arb`, `client/lib/l10n/app_zh.arb`
- Regenerate: `client/lib/l10n/app_localizations*.dart` via `flutter gen-l10n`
- Create: `client/lib/pages/usage/widgets/usage_heatmap_card.dart`
- Test: `client/test/pages/usage/usage_heatmap_card_test.dart` (create)

**Interfaces:**
- Consumes: `UsageHeatmapDay`, `usageHeatmapSpans`, `usageHeatmapLocalDayStart`, `usageHeatmapThresholds`, `usageHeatmapLevel`, `usageHeatmapWeeks`; `formatUsageTokens`, `formatUsageCost`, `formatUsagePercent`; `TpTextStyles`, `TpSegmentedControl`.
- Produces: `UsageHeatmapCard({required List<UsageHeatmapDay> days, required int nowMs})`.

- [ ] **Step 1: Write the failing tests**

Create `client/test/pages/usage/usage_heatmap_card_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/session_usage_dashboard.dart';
import 'package:teampilot/pages/usage/widgets/usage_heatmap_card.dart';

final _now = DateTime(2026, 10, 28, 12).millisecondsSinceEpoch;
final _today = DateTime(2026, 10, 28);

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

Widget _wrap(Widget child, {double width = 1000}) {
  return MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: TpTheme(
      data: TpThemeData.fromColorScheme(
        ColorScheme.fromSeed(seedColor: Colors.indigo),
        scale: 1,
      ),
      child: Scaffold(
        body: SingleChildScrollView(
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(width: width, child: child),
          ),
        ),
      ),
    ),
  );
}

Finder _cells() => find.byWidgetPredicate(
  (widget) =>
      widget is Container &&
      widget.key is ValueKey<String> &&
      (widget.key! as ValueKey<String>).value.startsWith('usageHeatmapCell-'),
);

Color? _cellColor(WidgetTester tester, DateTime date) {
  final container = tester.widget<Container>(
    find.byKey(
      ValueKey('usageHeatmapCell-${date.millisecondsSinceEpoch}'),
    ),
  );
  return (container.decoration! as BoxDecoration).color;
}

void main() {
  testWidgets('renders one 53x7 grid for the current span', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _wrap(
        UsageHeatmapCard(
          days: [
            _day(
              _today,
              tokens: 1000,
              requests: 5,
              costMicroUsd: 1000000,
              hitRate: 0.5,
            ),
          ],
          nowMs: _now,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Usage heatmap'), findsOneWidget);
    expect(_cells(), findsNWidgets(371));
    expect(find.text('Show earlier'), findsNothing);
  });

  testWidgets('tooltip lists tokens, requests, cost and hit rate', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _wrap(
        UsageHeatmapCard(
          days: [
            _day(
              _today,
              tokens: 1000,
              requests: 5,
              costMicroUsd: 1000000,
              hitRate: 0.5,
            ),
          ],
          nowMs: _now,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final tooltip = tester.widget<Tooltip>(
      find
          .ancestor(
            of: find.byKey(
              ValueKey('usageHeatmapCell-${_today.millisecondsSinceEpoch}'),
            ),
            matching: find.byType(Tooltip),
          )
          .first,
    );
    expect(tooltip.message, contains('Total tokens 1.0K'));
    expect(tooltip.message, contains('Requests 5'));
    expect(tooltip.message, contains(r'Cost $1.00'));
    expect(tooltip.message, contains('Hit rate 50%'));
  });

  testWidgets('metric switch re-colours cells', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _wrap(
        UsageHeatmapCard(
          days: [
            _day(_today, tokens: 1000, requests: 1),
            _day(DateTime(2026, 10, 27), tokens: 10, requests: 100),
          ],
          nowMs: _now,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final tokenColor = _cellColor(tester, _today);
    await tester.tap(find.text('Requests'));
    await tester.pumpAndSettle();
    final requestColor = _cellColor(tester, _today);

    expect(requestColor, isNot(tokenColor));
  });

  testWidgets('show earlier reveals the older span', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _wrap(
        UsageHeatmapCard(
          days: [_day(DateTime(2025, 10, 20), tokens: 5)],
          nowMs: _now,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(_cells(), findsNWidgets(371));
    await tester.tap(find.text('Show earlier'));
    await tester.pumpAndSettle();
    expect(_cells(), findsNWidgets(742));
    expect(find.text('Show less'), findsOneWidget);
  });

  testWidgets('empty days keep the no-data state', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _wrap(const UsageHeatmapCard(days: [], nowMs: 0)),
    );
    await tester.pumpAndSettle();

    expect(_cells(), findsNothing);
    expect(find.text('No data'), findsOneWidget);
  });

  testWidgets('fits a narrow card without overflowing', (tester) async {
    tester.view.physicalSize = const Size(900, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _wrap(
        UsageHeatmapCard(days: [_day(_today)], nowMs: _now),
        width: 400,
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(_cells(), findsNWidgets(371));
  });
}
```

- [ ] **Step 2: Add the strings**

In `client/lib/l10n/app_en.arb`, insert before `"sessionUsageNoData"`:

```json
  "sessionUsageHeatmapTitle": "Usage heatmap",
  "sessionUsageHeatmapSubtitle": "Last 53 weeks · hover or long-press a day",
  "sessionUsageHeatmapMetricTokens": "Tokens",
  "sessionUsageHeatmapMetricHitRate": "Hit rate",
  "sessionUsageHeatmapShowEarlier": "Show earlier",
  "sessionUsageHeatmapShowLess": "Show less",
  "sessionUsageHeatmapLess": "Less",
  "sessionUsageHeatmapMore": "More",
  "sessionUsageHeatmapSpanSummary": "{tokens} tokens · {requests} requests · {cost}",
  "@sessionUsageHeatmapSpanSummary": {
    "placeholders": {
      "tokens": { "type": "String" },
      "requests": { "type": "String" },
      "cost": { "type": "String" }
    }
  },
```

In `client/lib/l10n/app_zh.arb`, insert before `"sessionUsageNoData"`:

```json
  "sessionUsageHeatmapTitle": "用量热力图",
  "sessionUsageHeatmapSubtitle": "近 53 周 · 悬停或长按查看当天明细",
  "sessionUsageHeatmapMetricTokens": "Token",
  "sessionUsageHeatmapMetricHitRate": "命中率",
  "sessionUsageHeatmapShowEarlier": "显示更早",
  "sessionUsageHeatmapShowLess": "收起更早",
  "sessionUsageHeatmapLess": "少",
  "sessionUsageHeatmapMore": "多",
  "sessionUsageHeatmapSpanSummary": "{tokens} Token · {requests} 请求 · {cost}",
  "@sessionUsageHeatmapSpanSummary": {
    "placeholders": {
      "tokens": { "type": "String" },
      "requests": { "type": "String" },
      "cost": { "type": "String" }
    }
  },
```

Then run `cd client && flutter gen-l10n` and confirm it exits 0.

- [ ] **Step 3: Run the test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/pages/usage/usage_heatmap_card_test.dart`
Expected: FAIL — `usage_heatmap_card.dart` does not exist.

- [ ] **Step 4: Implement the card**

Create `client/lib/pages/usage/widgets/usage_heatmap_card.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../l10n/l10n_extensions.dart';
import '../../../models/session_usage_dashboard.dart';
import '../../../theme/workspace_surface_layers.dart';
import '../usage_format.dart';
import 'usage_heatmap_layout.dart';

enum _HeatmapMetric { tokens, requests, cost, hitRate }

class UsageHeatmapCard extends StatefulWidget {
  const UsageHeatmapCard({required this.days, required this.nowMs, super.key});

  final List<UsageHeatmapDay> days;
  final int nowMs;

  @override
  State<UsageHeatmapCard> createState() => _UsageHeatmapCardState();
}

class _UsageHeatmapCardState extends State<UsageHeatmapCard> {
  _HeatmapMetric _metric = _HeatmapMetric.tokens;
  bool _showEarlier = false;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);
    final spans = usageHeatmapSpans(days: widget.days, nowMs: widget.nowMs);
    final today = usageHeatmapLocalDayStart(widget.nowMs);
    final byDay = {
      for (final day in widget.days)
        usageHeatmapLocalDayStart(day.dayStartMs): day,
    };
    final values = <double>[];
    for (final span in spans) {
      for (final week in span.weekDayStarts) {
        for (final dayStart in week) {
          if (dayStart > today) continue;
          final value = _metricValue(byDay[dayStart], _metric);
          if (value != null) values.add(value);
        }
      }
    }
    final thresholds = usageHeatmapThresholds(values);
    final visible = _showEarlier
        ? spans
        : spans.take(1).toList(growable: false);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: workspaceCardDecoration(
        cs,
        radius: 14,
      ).copyWith(color: cs.workspaceCard),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final title = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.sessionUsageHeatmapTitle, style: styles.mdBold),
                  const SizedBox(height: 2),
                  Text(
                    l10n.sessionUsageHeatmapSubtitle,
                    style: styles.xs.copyWith(
                      color: cs.onSurface.withValues(alpha: 0.56),
                    ),
                  ),
                ],
              );
              final control = TpSegmentedControl(
                key: ValueKey(_metric),
                totalSwitches: _HeatmapMetric.values.length,
                initialLabelIndex: _metric.index,
                labels: [
                  l10n.sessionUsageHeatmapMetricTokens,
                  l10n.sessionUsageRequests,
                  l10n.sessionUsageCost,
                  l10n.sessionUsageHeatmapMetricHitRate,
                ],
                variant: TpSegmentedControlVariant.outlined,
                minWidth: 56,
                minHeight: 30,
                onToggle: (index) {
                  if (index == null) return;
                  setState(() => _metric = _HeatmapMetric.values[index]);
                },
              );
              if (constraints.maxWidth < 620) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    title,
                    const SizedBox(height: 10),
                    control,
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: title),
                  const SizedBox(width: 12),
                  control,
                ],
              );
            },
          ),
          const SizedBox(height: 14),
          if (widget.days.isEmpty)
            SizedBox(
              height: 120,
              child: Center(
                child: Text(
                  l10n.sessionUsageNoData,
                  style: styles.sm.copyWith(
                    color: cs.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ),
            )
          else ...[
            for (var index = 0; index < visible.length; index++) ...[
              if (index > 0) const SizedBox(height: 16),
              _SpanBlock(
                span: visible[index],
                byDay: byDay,
                metric: _metric,
                thresholds: thresholds,
                todayMs: today,
                styles: styles,
                cs: cs,
                l10n: l10n,
              ),
            ],
            const SizedBox(height: 10),
            _footer(spans, cs, styles, l10n),
          ],
        ],
      ),
    );
  }

  Widget _footer(
    List<UsageHeatmapSpan> spans,
    ColorScheme cs,
    TpTextStyles styles,
    AppLocalizations l10n,
  ) {
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (spans.length > 1)
          TextButton(
            key: const ValueKey('usageHeatmapShowEarlier'),
            onPressed: () => setState(() => _showEarlier = !_showEarlier),
            child: Text(
              _showEarlier
                  ? l10n.sessionUsageHeatmapShowLess
                  : l10n.sessionUsageHeatmapShowEarlier,
              style: styles.xs,
            ),
          ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.sessionUsageHeatmapLess,
              style: styles.xs.copyWith(
                color: cs.onSurface.withValues(alpha: 0.56),
              ),
            ),
            for (var level = 0; level < 5; level++)
              Container(
                width: 10,
                height: 10,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  color: _heatColor(level, cs),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            Text(
              l10n.sessionUsageHeatmapMore,
              style: styles.xs.copyWith(
                color: cs.onSurface.withValues(alpha: 0.56),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _SpanBlock extends StatelessWidget {
  const _SpanBlock({
    required this.span,
    required this.byDay,
    required this.metric,
    required this.thresholds,
    required this.todayMs,
    required this.styles,
    required this.cs,
    required this.l10n,
  });

  final UsageHeatmapSpan span;
  final Map<int, UsageHeatmapDay> byDay;
  final _HeatmapMetric metric;
  final List<double> thresholds;
  final int todayMs;
  final TpTextStyles styles;
  final ColorScheme cs;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final material = MaterialLocalizations.of(context);
    final monthFormat = DateFormat.MMM(
      Localizations.localeOf(context).toLanguageTag(),
    );
    final monthLabels = [
      for (var week = 0; week < usageHeatmapWeeks; week++)
        _monthLabel(span.weekDayStarts[week], week, monthFormat),
    ];
    final range =
        '${material.formatShortDate(DateTime.fromMillisecondsSinceEpoch(span.startDayMs))} – '
        '${material.formatShortDate(DateTime.fromMillisecondsSinceEpoch(span.endDayMs))}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 2,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(range, style: styles.xsMedium),
            Text(
              l10n.sessionUsageHeatmapSpanSummary(
                formatUsageTokens(span.tokens),
                '${span.requests}',
                formatUsageCost(span.costMicroUsd),
              ),
              style: styles.xs.copyWith(
                color: cs.onSurface.withValues(alpha: 0.56),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        LayoutBuilder(
          builder: (context, constraints) {
            const labelWidth = 24.0;
            const gap = 3.0;
            final available = constraints.maxWidth - labelWidth;
            final rawCell =
                (available - gap * (usageHeatmapWeeks - 1)) /
                usageHeatmapWeeks;
            final cell = rawCell.clamp(6.0, 14.0);
            final contentWidth =
                labelWidth + usageHeatmapWeeks * (cell + gap);
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: contentWidth,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const SizedBox(width: labelWidth),
                        for (var week = 0; week < usageHeatmapWeeks; week++)
                          SizedBox(
                            width: cell + gap,
                            child: OverflowBox(
                              alignment: Alignment.centerLeft,
                              maxWidth: 48,
                              child: Text(
                                monthLabels[week] ?? '',
                                maxLines: 1,
                                style: styles.xs.copyWith(
                                  color: cs.onSurface.withValues(alpha: 0.54),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    for (var day = 0; day < 7; day++)
                      Row(
                        children: [
                          SizedBox(
                            width: labelWidth,
                            child: day == 0 || day == 2 || day == 4
                                ? Padding(
                                    padding: const EdgeInsets.only(right: 4),
                                    child: Text(
                                      material.narrowWeekdays[(day + 1) % 7],
                                      maxLines: 1,
                                      textAlign: TextAlign.end,
                                      style: styles.xs.copyWith(
                                        color: cs.onSurface.withValues(
                                          alpha: 0.54,
                                        ),
                                      ),
                                    ),
                                  )
                                : null,
                          ),
                          for (var week = 0;
                              week < usageHeatmapWeeks;
                              week++)
                            Padding(
                              padding: const EdgeInsets.only(
                                right: gap,
                                bottom: gap,
                              ),
                              child: _cell(
                                span.weekDayStarts[week][day],
                                cell,
                                material,
                              ),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  String? _monthLabel(
    List<int> days,
    int weekIndex,
    DateFormat format,
  ) {
    for (final dayStart in days) {
      final date = DateTime.fromMillisecondsSinceEpoch(dayStart).toLocal();
      if (weekIndex == 0 || date.day == 1) {
        return format.format(date);
      }
    }
    return null;
  }

  Widget _cell(int dayStart, double cell, MaterialLocalizations material) {
    final future = dayStart > todayMs;
    final data = byDay[dayStart];
    final level = future
        ? 0
        : usageHeatmapLevel(_metricValue(data, metric), thresholds);
    return Tooltip(
      message: future ? '' : _tooltip(dayStart, data, material),
      waitDuration: const Duration(milliseconds: 150),
      child: Container(
        key: ValueKey('usageHeatmapCell-$dayStart'),
        width: cell,
        height: cell,
        decoration: BoxDecoration(
          color: future ? Colors.transparent : _heatColor(level, cs),
          borderRadius: BorderRadius.circular(3),
        ),
      ),
    );
  }

  String _tooltip(
    int dayStart,
    UsageHeatmapDay? data,
    MaterialLocalizations material,
  ) {
    final date = material.formatFullDate(
      DateTime.fromMillisecondsSinceEpoch(dayStart).toLocal(),
    );
    final hitRate = data?.cacheHitRate;
    return '$date\n'
        '${l10n.sessionUsageTotalTokens} ${formatUsageTokens(data?.tokens ?? 0)}\n'
        '${l10n.sessionUsageRequests} ${data?.requests ?? 0}\n'
        '${l10n.sessionUsageCost} ${formatUsageCost(data?.costMicroUsd ?? 0)}\n'
        '${l10n.sessionUsageHeatmapMetricHitRate} '
        '${hitRate == null ? '—' : formatUsagePercent(hitRate)}';
  }
}

double? _metricValue(UsageHeatmapDay? day, _HeatmapMetric metric) {
  if (day == null) return null;
  return switch (metric) {
    _HeatmapMetric.tokens => day.tokens > 0 ? day.tokens.toDouble() : null,
    _HeatmapMetric.requests =>
      day.requests > 0 ? day.requests.toDouble() : null,
    _HeatmapMetric.cost =>
      day.costMicroUsd > 0 ? day.costMicroUsd.toDouble() : null,
    _HeatmapMetric.hitRate => day.cacheHitRate,
  };
}

Color _heatColor(int level, ColorScheme cs) {
  return switch (level) {
    0 => cs.surfaceContainerHighest.withValues(alpha: 0.55),
    1 => cs.primary.withValues(alpha: 0.20),
    2 => cs.primary.withValues(alpha: 0.38),
    3 => cs.primary.withValues(alpha: 0.58),
    _ => cs.primary.withValues(alpha: 0.82),
  };
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `cd client && dart run tool/run_tests.dart test/pages/usage/usage_heatmap_card_test.dart`
Expected: PASS (6 tests). If `DateFormat.MMM` throws `LocaleDataException`, confirm the test wraps the card in `MaterialApp` with `AppLocalizations.localizationsDelegates` (it does) so intl symbols are initialized.

- [ ] **Step 6: Analyze and commit**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings lib/pages/usage/widgets/usage_heatmap_card.dart lib/pages/usage/widgets/usage_heatmap_layout.dart`
Expected: `No issues found!`

```bash
cd /home/hhoa/git/hhoa/teampilot
git add client/lib/l10n/app_en.arb client/lib/l10n/app_zh.arb \
  client/lib/l10n/app_localizations.dart \
  client/lib/l10n/app_localizations_en.dart \
  client/lib/l10n/app_localizations_zh.dart \
  client/lib/pages/usage/widgets/usage_heatmap_card.dart \
  client/test/pages/usage/usage_heatmap_card_test.dart
git commit -m "feat(usage): add the usage heatmap card"
```

---

### Task 4: Page integration and verification

**Files:**
- Modify: `client/lib/pages/usage/session_usage_page.dart` (imports + `_buildBody`)
- Test: `client/test/pages/usage/session_usage_page_test.dart` (add one assertion)

**Interfaces:**
- Consumes: `UsageHeatmapCard` from Task 3, `dashboard.heatmap` from Task 1.
- Produces: no new API.

- [ ] **Step 1: Write the failing assertion**

In `client/test/pages/usage/session_usage_page_test.dart`, add the import:

```dart
import 'package:teampilot/pages/usage/widgets/usage_heatmap_card.dart';
```

In the test that expects `Alpha`/`Beta` (the loaded-dashboard test), add after the `Total tokens` assertion:

```dart
    expect(find.byType(UsageHeatmapCard), findsOneWidget);
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/pages/usage/session_usage_page_test.dart`
Expected: FAIL — `UsageHeatmapCard` is never built.

- [ ] **Step 3: Insert the card**

In `client/lib/pages/usage/session_usage_page.dart`, add the import:

```dart
import 'widgets/usage_heatmap_card.dart';
```

In `_buildBody`, after `UsageCostCard(...)` and before the `LayoutBuilder` that hosts the trend chart, insert:

```dart
          const SizedBox(height: 14),
          UsageHeatmapCard(days: dashboard.heatmap, nowMs: nowMs),
```

The surrounding block becomes:

```dart
          UsageCostCard(
            summary: dashboard.summary,
            corrupted: state.pricingCorrupted,
            onManagePricing: () => _openPricing(cubit),
          ),
          const SizedBox(height: 14),
          UsageHeatmapCard(days: dashboard.heatmap, nowMs: nowMs),
          const SizedBox(height: 14),
          LayoutBuilder(
```

(remove the old single `const SizedBox(height: 14),` that followed `UsageCostCard`).

- [ ] **Step 4: Run the usage suite**

Run: `cd client && dart run tool/run_tests.dart test/pages/usage test/services/usage`
Expected: PASS.

- [ ] **Step 5: Analyze**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: no issues in any of the heatmap files; unrelated pre-existing issues in other dirty files are not this task's concern (report them if present).

- [ ] **Step 6: Run the full suite once**

Run: `cd client && dart run tool/run_tests.dart` (background if needed).
Expected: all tests pass except known pre-existing failures caused by unrelated uncommitted work in `test/widgets/managed_provider/managed_provider_usage_panel_test.dart`; report any usage/heatmap failure as a blocker and fix it.

- [ ] **Step 7: Commit**

```bash
cd /home/hhoa/git/hhoa/teampilot
git add client/lib/pages/usage/session_usage_page.dart \
  client/test/pages/usage/session_usage_page_test.dart
git commit -m "feat(usage): show the heatmap on the usage page"
```
