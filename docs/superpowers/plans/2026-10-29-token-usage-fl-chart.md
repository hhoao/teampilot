# Token Usage fl_chart Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the three hand-rolled usage-page charts with `fl_chart` while keeping every current label, empty state, filter and dimming behaviour.

**Architecture:** A single new dependency (`fl_chart`) backs three focused widgets. `UsageTrendChart` becomes a stacked `BarChart` with a custom multi-line tooltip and thinned day labels; `UsageSparkline` becomes an axis-less `BarChart`; `UsageCliBreakdown` becomes a stateful widget with a donut `PieChart` whose centre readout follows hover. Cubit, models and l10n stay untouched.

**Tech Stack:** Flutter 3.47 / Dart 3.8, `fl_chart` 1.3.0, `flutter_bloc` usage page, `shared_ui` `TpTextStyles`, `dart run tool/run_tests.dart`.

## Global Constraints

- Spec: `docs/superpowers/specs/2026-10-29-token-usage-fl-chart-design.md`.
- Add exactly one dependency: `fl_chart: ^1.3.0`; commit the resulting `pubspec.lock`.
- Never run `flutter test` directly; always `cd client && dart run tool/run_tests.dart <path>`.
- Text styles must come from `TpTextStyles` named getters; do not create `TextStyle(...)` or set `fontSize` / `fontWeight` via `copyWith`. Setting `color` via `copyWith` is allowed.
- The worktree already contains unrelated modified files. Stage only the paths named in each task; never `git add -A` / `git commit -a`.
- Public widget constructors must not change: `UsageTrendChart(days, nowMs, selectedCli)`, `UsageSparkline(days)`, `UsageCliBreakdown(slices, summary, selectedCli)`.
- fl_chart 1.3.0 facts that the code relies on:
  - `BarChart(data, duration: ..., curve: ...)`, `PieChart(data, duration: ..., curve: ...)`.
  - `BarChartRodData(toY:, width:, color:, borderRadius:, rodStackItems:)`; `BarChartRodStackItem(fromY, toY, color)`.
  - `BarTouchData(handleBuiltInTouches: true)` resolves the touched group and calls `BarTouchTooltipData.getTooltipItem(group, groupIndex, rod, rodIndex)`; `BarTooltipItem(text, style, children: [...])` supports multi-line `TextSpan`s.
  - `SideTitles(getTitlesWidget: (value, meta) => SideTitleWidget(meta: meta, space: 6, child: ...))`.
  - fl_chart 1.3 has **no** built-in `PieTouchTooltipData`; pie hover must be handled through `PieTouchData.touchCallback` plus local state.

---

## File Map

| File | Responsibility |
|------|----------------|
| `client/pubspec.yaml` | Add `fl_chart: ^1.3.0` |
| `client/lib/pages/usage/usage_format.dart` | Add pure `usageChartLabelStride` helper |
| `client/lib/pages/usage/widgets/usage_trend_chart.dart` | Stacked daily bar chart |
| `client/lib/pages/usage/widgets/usage_summary_cards.dart` | Replace `UsageSparkline` body with a mini bar chart |
| `client/lib/pages/usage/widgets/usage_cli_breakdown.dart` | Donut chart + hover centre readout + rows |
| `client/test/pages/usage/usage_format_test.dart` | New unit test for the stride helper |
| `client/test/pages/usage/usage_trend_chart_test.dart` | Chart rendering, empty state, 30-day range |
| `client/test/pages/usage/usage_summary_cards_test.dart` | Sparkline is a `BarChart` |
| `client/test/pages/usage/usage_cli_breakdown_test.dart` | New donut/empty/dimming/hover tests |

---

### Task 1: Add fl_chart and the label-stride helper

**Files:**
- Modify: `client/pubspec.yaml` (dependencies block, after `flutter_svg`)
- Modify: `client/lib/pages/usage/usage_format.dart` (append at end)
- Test: `client/test/pages/usage/usage_format_test.dart` (create)

**Interfaces:**
- Consumes: nothing.
- Produces: `int usageChartLabelStride(int dayCount)` — used by Task 2.

- [ ] **Step 1: Write the failing test**

Create `client/test/pages/usage/usage_format_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/pages/usage/usage_format.dart';

void main() {
  test('usageChartLabelStride keeps about seven bottom labels', () {
    expect(usageChartLabelStride(0), 1);
    expect(usageChartLabelStride(1), 1);
    expect(usageChartLabelStride(7), 1);
    expect(usageChartLabelStride(14), 2);
    expect(usageChartLabelStride(30), 5);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/pages/usage/usage_format_test.dart`
Expected: FAIL — `usageChartLabelStride` is not defined.

- [ ] **Step 3: Implement the helper**

Append to `client/lib/pages/usage/usage_format.dart`:

```dart
/// Bottom-axis label stride for the usage trend chart.
///
/// Keeps at most about seven day labels visible for any selected range.
int usageChartLabelStride(int dayCount) {
  if (dayCount <= 0) return 1;
  return (dayCount / 7).ceil();
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd client && dart run tool/run_tests.dart test/pages/usage/usage_format_test.dart`
Expected: PASS (1 test).

- [ ] **Step 5: Add the dependency**

Run: `cd client && flutter pub add fl_chart:^1.3.0`
Expected: `pubspec.yaml` gains `fl_chart: ^1.3.0` under `dependencies`, and `pubspec.lock` records `fl_chart 1.3.0`.

- [ ] **Step 6: Commit**

```bash
cd /home/hhoa/git/hhoa/teampilot
git add client/pubspec.yaml client/pubspec.lock \
  client/lib/pages/usage/usage_format.dart \
  client/test/pages/usage/usage_format_test.dart
git commit -m "feat(usage): add fl_chart and day-label stride helper"
```

---

### Task 2: Rewrite the trend chart as a stacked BarChart

**Files:**
- Modify: `client/lib/pages/usage/widgets/usage_trend_chart.dart` (whole file)
- Test: `client/test/pages/usage/usage_trend_chart_test.dart` (whole file)

**Interfaces:**
- Consumes: `usageChartLabelStride(int)` from Task 1; `usageCliColor`, `usageCliLabel`, `formatUsageTokens`, `formatUsageDayLabel` from `usage_format.dart`; `UsageChartDay` from `session_usage_dashboard.dart`.
- Produces: unchanged public `UsageTrendChart({required List<UsageChartDay> days, required int nowMs, CliTool? selectedCli})`.

- [ ] **Step 1: Write the failing tests**

Replace `client/test/pages/usage/usage_trend_chart_test.dart` with:

```dart
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/session_usage_dashboard.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/pages/usage/widgets/usage_trend_chart.dart';

Widget _wrap(Widget child, {double textScale = 1.0}) {
  return MaterialApp(
    locale: const Locale('zh'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    builder: (context, appChild) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: appChild!,
    ),
    home: TpTheme(
      data: TpThemeData.fromColorScheme(
        ColorScheme.fromSeed(seedColor: Colors.indigo),
        scale: 1,
      ),
      child: Scaffold(body: child),
    ),
  );
}

List<UsageChartDay> _days(int nowMs, {int count = 7}) => [
  for (var i = count - 1; i >= 0; i--)
    UsageChartDay(
      dayStartMs: nowMs - i * Duration.millisecondsPerDay,
      tokensByCli: {CliTool.claude: 1000 * (i + 1), CliTool.codex: 500},
    ),
];

void main() {
  testWidgets('fits the tallest day inside the chart box', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final nowMs = DateTime(2026, 10, 28, 12).millisecondsSinceEpoch;
    await tester.pumpWidget(
      _wrap(
        SizedBox(
          width: 1000,
          child: UsageTrendChart(days: _days(nowMs), nowMs: nowMs),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(BarChart), findsOneWidget);
  });

  testWidgets('fits when day labels are taller than the reserved slot', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final nowMs = DateTime(2026, 10, 28, 12).millisecondsSinceEpoch;
    await tester.pumpWidget(
      _wrap(
        SizedBox(
          width: 1000,
          child: UsageTrendChart(days: _days(nowMs), nowMs: nowMs),
        ),
        textScale: 1.4,
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('shows the empty state instead of a chart for all-zero days', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final nowMs = DateTime(2026, 10, 28, 12).millisecondsSinceEpoch;
    await tester.pumpWidget(
      _wrap(
        SizedBox(
          width: 1000,
          child: UsageTrendChart(
            days: [UsageChartDay(dayStartMs: nowMs)],
            nowMs: nowMs,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(BarChart), findsNothing);
    expect(find.text('暂无数据'), findsOneWidget);
  });

  testWidgets('lays out a thirty-day range', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final nowMs = DateTime(2026, 10, 28, 12).millisecondsSinceEpoch;
    await tester.pumpWidget(
      _wrap(
        SizedBox(
          width: 1100,
          child: UsageTrendChart(days: _days(nowMs, count: 30), nowMs: nowMs),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(BarChart), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd client && dart run tool/run_tests.dart test/pages/usage/usage_trend_chart_test.dart`
Expected: FAIL — `find.byType(BarChart)` finds nothing (the old chart is hand-built).

- [ ] **Step 3: Replace the widget implementation**

Replace `client/lib/pages/usage/widgets/usage_trend_chart.dart` with:

```dart
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../l10n/l10n_extensions.dart';
import '../../../models/session_usage_dashboard.dart';
import '../../../models/team_config.dart';
import '../../../theme/workspace_surface_layers.dart';
import '../usage_format.dart';

const double _chartHeight = 180;
const Duration _chartAnimation = Duration(milliseconds: 260);

class UsageTrendChart extends StatelessWidget {
  const UsageTrendChart({
    required this.days,
    required this.nowMs,
    this.selectedCli,
    super.key,
  });

  final List<UsageChartDay> days;
  final int nowMs;
  final CliTool? selectedCli;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);
    final maxTotal = days.fold<int>(
      0,
      (max, day) => day.totalTokens > max ? day.totalTokens : max,
    );
    final chartTotal = days.fold<int>(0, (sum, day) => sum + day.totalTokens);
    final average = days.isEmpty ? 0 : chartTotal ~/ days.length;
    final totalsByCli = <CliTool, int>{};
    for (final day in days) {
      for (final entry in day.tokensByCli.entries) {
        totalsByCli[entry.key] = (totalsByCli[entry.key] ?? 0) + entry.value;
      }
    }
    final legendClis = totalsByCli.keys.toList()
      ..sort((a, b) => a.index.compareTo(b.index));

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: workspaceCardDecoration(
        cs,
        radius: 14,
      ).copyWith(color: cs.workspaceCard),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.sessionUsageChartTitle, style: styles.mdBold),
                    const SizedBox(height: 2),
                    Text(
                      l10n.sessionUsageChartSubtitle,
                      style: styles.xs.copyWith(
                        color: cs.onSurface.withValues(alpha: 0.56),
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    l10n.sessionUsageChartTotal(formatUsageTokens(chartTotal)),
                    style: styles.smMedium,
                  ),
                  Text(
                    l10n.sessionUsageChartAverage(formatUsageTokens(average)),
                    style: styles.xs.copyWith(
                      color: cs.onSurface.withValues(alpha: 0.56),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (maxTotal == 0)
            SizedBox(
              height: _chartHeight,
              child: Center(
                child: Text(
                  l10n.sessionUsageNoData,
                  style: styles.sm.copyWith(
                    color: cs.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ),
            )
          else
            SizedBox(
              height: _chartHeight,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final rodWidth = (constraints.maxWidth / days.length * 0.46)
                      .clamp(3.0, 18.0)
                      .toDouble();
                  final stride = usageChartLabelStride(days.length);
                  final tickInterval = maxTotal <= 2 ? 1.0 : maxTotal / 2;
                  final labelStyle = styles.xs.copyWith(
                    color: cs.onSurface.withValues(alpha: 0.54),
                  );
                  return BarChart(
                    BarChartData(
                      minY: 0,
                      maxY: maxTotal * 1.12,
                      alignment: BarChartAlignment.spaceEvenly,
                      barGroups: [
                        for (var index = 0; index < days.length; index++)
                          _chartGroup(
                            index: index,
                            day: days[index],
                            legendClis: legendClis,
                            rodWidth: rodWidth,
                            selectedCli: selectedCli,
                          ),
                      ],
                      titlesData: FlTitlesData(
                        topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        rightTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 40,
                            interval: tickInterval,
                            maxIncluded: false,
                            getTitlesWidget: (value, meta) => SideTitleWidget(
                              meta: meta,
                              space: 6,
                              child: Text(
                                formatUsageTokens(value.round()),
                                style: labelStyle,
                              ),
                            ),
                          ),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 26,
                            interval: 1,
                            getTitlesWidget: (value, meta) {
                              final index = value.round();
                              if (index < 0 ||
                                  index >= days.length ||
                                  index % stride != 0) {
                                return const SizedBox.shrink();
                              }
                              return SideTitleWidget(
                                meta: meta,
                                space: 6,
                                child: Text(
                                  formatUsageDayLabel(
                                    context,
                                    days[index].dayStartMs,
                                    nowMs,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: labelStyle,
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        horizontalInterval: tickInterval,
                        getDrawingHorizontalLine: (value) => FlLine(
                          color: cs.outlineVariant.withValues(alpha: 0.35),
                          strokeWidth: 1,
                        ),
                      ),
                      borderData: FlBorderData(show: false),
                      barTouchData: BarTouchData(
                        enabled: true,
                        touchTooltipData: BarTouchTooltipData(
                          tooltipBorderRadius: BorderRadius.circular(8),
                          tooltipPadding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          tooltipMargin: 8,
                          maxContentWidth: 190,
                          fitInsideHorizontally: true,
                          fitInsideVertically: true,
                          getTooltipColor: (_) => cs.surfaceContainerHighest,
                          tooltipBorder: BorderSide(
                            color: cs.outlineVariant.withValues(alpha: 0.5),
                          ),
                          getTooltipItem: (group, groupIndex, rod, rodIndex) {
                            final index = groupIndex < days.length
                                ? groupIndex
                                : days.length - 1;
                            return _chartTooltip(
                              context: context,
                              day: days[index],
                              legendClis: legendClis,
                              styles: styles,
                              cs: cs,
                              nowMs: nowMs,
                            );
                          },
                        ),
                      ),
                    ),
                    duration: _chartAnimation,
                    curve: Curves.easeOutCubic,
                  );
                },
              ),
            ),
          if (legendClis.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 14,
              runSpacing: 6,
              children: [
                for (final cli in legendClis)
                  _LegendDot(
                    color: usageCliColor(cli),
                    label:
                        '${usageCliLabel(cli)} · ${formatUsageTokens(totalsByCli[cli] ?? 0)}',
                    dimmed: selectedCli != null && selectedCli != cli,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

BarChartGroupData _chartGroup({
  required int index,
  required UsageChartDay day,
  required List<CliTool> legendClis,
  required double rodWidth,
  required CliTool? selectedCli,
}) {
  var stacked = 0.0;
  final stackItems = <BarChartRodStackItem>[];
  for (final cli in legendClis) {
    final tokens = day.tokensByCli[cli] ?? 0;
    if (tokens <= 0) continue;
    final color = usageCliColor(
      cli,
    ).withValues(alpha: selectedCli == null || selectedCli == cli ? 0.92 : 0.22);
    stackItems.add(BarChartRodStackItem(stacked, stacked + tokens, color));
    stacked += tokens;
  }
  return BarChartGroupData(
    x: index,
    barRods: [
      BarChartRodData(
        toY: day.totalTokens.toDouble(),
        width: rodWidth,
        color: Colors.transparent,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
        rodStackItems: stackItems,
      ),
    ],
  );
}

BarTooltipItem _chartTooltip({
  required BuildContext context,
  required UsageChartDay day,
  required List<CliTool> legendClis,
  required TpTextStyles styles,
  required ColorScheme cs,
  required int nowMs,
}) {
  final children = <TextSpan>[];
  for (final cli in legendClis) {
    final tokens = day.tokensByCli[cli] ?? 0;
    if (tokens <= 0) continue;
    children.add(
      TextSpan(
        text: '\n${usageCliLabel(cli)}  ${formatUsageTokens(tokens)}',
        style: styles.xs.copyWith(color: usageCliColor(cli)),
      ),
    );
  }
  children.add(
    TextSpan(
      text:
          '\n${context.l10n.sessionUsageChartTotal(formatUsageTokens(day.totalTokens))}',
      style: styles.xsSemibold.copyWith(color: cs.onSurface),
    ),
  );
  return BarTooltipItem(
    formatUsageDayLabel(context, day.dayStartMs, nowMs),
    styles.smMedium.copyWith(color: cs.onSurface),
    children: children,
  );
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({
    required this.color,
    required this.label,
    required this.dimmed,
  });

  final Color color;
  final String label;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final styles = TpTextStyles.of(context);
    final cs = Theme.of(context).colorScheme;
    return Opacity(
      opacity: dimmed ? 0.42 : 1,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: styles.xs.copyWith(
              color: cs.onSurface.withValues(alpha: 0.68),
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd client && dart run tool/run_tests.dart test/pages/usage/usage_trend_chart_test.dart`
Expected: PASS (4 tests). If a tooltip assertion fails because the built-in handler needs a frame, add `await tester.pump(const Duration(milliseconds: 300));` before the assertion.

- [ ] **Step 5: Analyze the file**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings lib/pages/usage/widgets/usage_trend_chart.dart`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
cd /home/hhoa/git/hhoa/teampilot
git add client/lib/pages/usage/widgets/usage_trend_chart.dart \
  client/test/pages/usage/usage_trend_chart_test.dart
git commit -m "feat(usage): draw the trend chart with fl_chart stacked bars"
```

---

### Task 3: Replace the summary sparkline

**Files:**
- Modify: `client/lib/pages/usage/widgets/usage_summary_cards.dart` (imports + `UsageSparkline` class)
- Test: `client/test/pages/usage/usage_summary_cards_test.dart` (add one test)

**Interfaces:**
- Consumes: `UsageChartDay` only; no helper from earlier tasks.
- Produces: unchanged public `UsageSparkline({required List<UsageChartDay> days})` and `UsageSummaryCards(...)`.

- [ ] **Step 1: Write the failing test**

Add to `client/test/pages/usage/usage_summary_cards_test.dart` (append inside `main()`, after the existing tests):

```dart
  testWidgets('sparkline renders as a fl_chart bar chart', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_wrap(width: 700, fontSizeFactor: 1.0));
    await tester.pumpAndSettle();

    expect(find.byType(BarChart), findsOneWidget);
    expect(tester.getSize(find.byType(UsageSparkline)).height, 26);
  });
```

Add `import 'package:fl_chart/fl_chart.dart';` to the imports at the top of the file.

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/pages/usage/usage_summary_cards_test.dart`
Expected: FAIL — no `BarChart` in the tree.

- [ ] **Step 3: Replace `UsageSparkline`**

In `client/lib/pages/usage/widgets/usage_summary_cards.dart`, add the import:

```dart
import 'package:fl_chart/fl_chart.dart';
```

Replace the whole `UsageSparkline` class (currently lines 192-234) with:

```dart
class UsageSparkline extends StatelessWidget {
  const UsageSparkline({required this.days, super.key});

  final List<UsageChartDay> days;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final maxTotal = days.fold<int>(
      0,
      (max, day) => day.totalTokens > max ? day.totalTokens : max,
    );
    final maxY = maxTotal == 0 ? 1.0 : maxTotal * 1.05;
    return SizedBox(
      height: 26,
      child: BarChart(
        BarChartData(
          minY: 0,
          maxY: maxY,
          alignment: BarChartAlignment.spaceAround,
          barGroups: [
            for (var index = 0; index < days.length; index++)
              BarChartGroupData(
                x: index,
                barRods: [
                  BarChartRodData(
                    toY: days[index].totalTokens == 0
                        ? maxY * 0.06
                        : days[index].totalTokens.toDouble(),
                    width: 6,
                    color: cs.primary.withValues(
                      alpha: days[index].totalTokens == 0 ? 0.16 : 0.56,
                    ),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ],
              ),
          ],
          titlesData: const FlTitlesData(show: false),
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          barTouchData: BarTouchData(enabled: false),
        ),
        duration: Duration.zero,
      ),
    );
  }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd client && dart run tool/run_tests.dart test/pages/usage/usage_summary_cards_test.dart`
Expected: PASS (all existing layout tests plus the new one).

- [ ] **Step 5: Commit**

```bash
cd /home/hhoa/git/hhoa/teampilot
git add client/lib/pages/usage/widgets/usage_summary_cards.dart \
  client/test/pages/usage/usage_summary_cards_test.dart
git commit -m "feat(usage): draw the summary sparkline with fl_chart"
```

---

### Task 4: Replace the CLI breakdown with a donut chart

**Files:**
- Modify: `client/lib/pages/usage/widgets/usage_cli_breakdown.dart` (whole file)
- Test: `client/test/pages/usage/usage_cli_breakdown_test.dart` (create)

**Interfaces:**
- Consumes: `UsageCliSlice`, `UsageSummary`, `CliTool`; `usageCliColor`, `usageCliLabel`, `formatUsageTokens`, `formatUsagePercent`.
- Produces: unchanged public `UsageCliBreakdown({required List<UsageCliSlice> slices, required UsageSummary summary, CliTool? selectedCli})`.

- [ ] **Step 1: Write the failing tests**

Create `client/test/pages/usage/usage_cli_breakdown_test.dart`:

```dart
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/session_usage_dashboard.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/pages/usage/widgets/usage_cli_breakdown.dart';

const _summary = UsageSummary(
  totalTokens: 3000,
  freshInputTokens: 1000,
  outputTokens: 1000,
  cacheReadTokens: 1000,
  cacheCreationTokens: 0,
  requests: 10,
  sessions: 2,
  cacheHitRate: 0.33,
);

const _slices = <UsageCliSlice>[
  UsageCliSlice(
    cli: CliTool.claude,
    totalTokens: 2000,
    requests: 6,
    share: 2 / 3,
  ),
  UsageCliSlice(
    cli: CliTool.codex,
    totalTokens: 1000,
    requests: 4,
    share: 1 / 3,
  ),
];

Widget _wrap({
  List<UsageCliSlice> slices = _slices,
  CliTool? selectedCli,
}) {
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
        body: SizedBox(
          width: 300,
          child: UsageCliBreakdown(
            slices: slices,
            summary: _summary,
            selectedCli: selectedCli,
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('renders a donut with the total in the centre', (tester) async {
    tester.view.physicalSize = const Size(800, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_wrap());
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(PieChart), findsOneWidget);
    expect(find.text('3.0K'), findsOneWidget);
    expect(find.text('Total tokens'), findsOneWidget);
    expect(find.text('Claude Code'), findsOneWidget);
    expect(find.text('Codex'), findsOneWidget);
  });

  testWidgets('empty slices keep the no-data state', (tester) async {
    tester.view.physicalSize = const Size(800, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_wrap(slices: const []));
    await tester.pumpAndSettle();

    expect(find.byType(PieChart), findsNothing);
    expect(find.text('No data'), findsOneWidget);
  });

  testWidgets('dims the rows of unselected CLIs', (tester) async {
    tester.view.physicalSize = const Size(800, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_wrap(selectedCli: CliTool.codex));
    await tester.pumpAndSettle();

    final claudeRow = tester.widget<Opacity>(
      find
          .ancestor(
            of: find.text('Claude Code'),
            matching: find.byType(Opacity),
          )
          .first,
    );
    final codexRow = tester.widget<Opacity>(
      find
          .ancestor(of: find.text('Codex'), matching: find.byType(Opacity))
          .first,
    );
    expect(claudeRow.opacity, 0.42);
    expect(codexRow.opacity, 1);
  });

  testWidgets('hovering a section shows that CLI in the centre', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_wrap());
    await tester.pumpAndSettle();

    final rect = tester.getRect(find.byType(PieChart));
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: rect.center);
    addTearDown(gesture.removePointer);
    await tester.pump();
    await gesture.moveTo(rect.center + Offset(0, -rect.height * 0.36));
    await tester.pump();

    expect(find.text('Claude Code · 67%'), findsOneWidget);
    expect(find.text('2.0K'), findsNWidgets(2));
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd client && dart run tool/run_tests.dart test/pages/usage/usage_cli_breakdown_test.dart`
Expected: FAIL — `find.byType(PieChart)` finds nothing.

- [ ] **Step 3: Replace the widget implementation**

Replace `client/lib/pages/usage/widgets/usage_cli_breakdown.dart` with:

```dart
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../l10n/l10n_extensions.dart';
import '../../../models/session_usage_dashboard.dart';
import '../../../models/team_config.dart';
import '../../../theme/workspace_surface_layers.dart';
import '../usage_format.dart';

class UsageCliBreakdown extends StatefulWidget {
  const UsageCliBreakdown({
    required this.slices,
    required this.summary,
    this.selectedCli,
    super.key,
  });

  final List<UsageCliSlice> slices;
  final UsageSummary summary;
  final CliTool? selectedCli;

  @override
  State<UsageCliBreakdown> createState() => _UsageCliBreakdownState();
}

class _UsageCliBreakdownState extends State<UsageCliBreakdown> {
  int? _touchedIndex;

  void _handleTouch(FlTouchEvent event, PieTouchResponse? response) {
    final index = event.isInterestedForInteractions
        ? response?.touchedSection?.touchedSectionIndex ?? -1
        : -1;
    final next = index >= 0 && index < widget.slices.length ? index : null;
    if (next == _touchedIndex) return;
    setState(() => _touchedIndex = next);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);
    final slices = widget.slices;
    final total = slices.fold<int>(0, (sum, slice) => sum + slice.totalTokens);
    final cacheShare = widget.summary.totalTokens == 0
        ? 0.0
        : widget.summary.cacheReadTokens / widget.summary.totalTokens;
    final touched =
        _touchedIndex != null &&
            _touchedIndex! >= 0 &&
            _touchedIndex! < slices.length
        ? slices[_touchedIndex!]
        : null;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: workspaceCardDecoration(
        cs,
        radius: 14,
      ).copyWith(color: cs.workspaceCard),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.sessionUsageCliBreakdown, style: styles.mdBold),
          const SizedBox(height: 12),
          if (slices.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 26),
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
            SizedBox(
              height: 150,
              width: double.infinity,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  PieChart(
                    PieChartData(
                      startDegreeOffset: -90,
                      centerSpaceRadius: 44,
                      sectionsSpace: 2,
                      sections: [
                        for (var index = 0; index < slices.length; index++)
                          PieChartSectionData(
                            value: slices[index].totalTokens.toDouble(),
                            color: usageCliColor(slices[index].cli).withValues(
                              alpha:
                                  widget.selectedCli == null ||
                                      widget.selectedCli == slices[index].cli
                                  ? 0.92
                                  : 0.22,
                            ),
                            radius: _touchedIndex == index ? 31.0 : 28.0,
                            showTitle: false,
                          ),
                      ],
                      pieTouchData: PieTouchData(touchCallback: _handleTouch),
                    ),
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                  ),
                  IgnorePointer(
                    child: SizedBox(
                      width: 86,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            formatUsageTokens(touched?.totalTokens ?? total),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: styles.mdBold,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            touched == null
                                ? l10n.sessionUsageTotalTokens
                                : '${usageCliLabel(touched.cli)} · '
                                      '${formatUsagePercent(touched.share)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: styles.xs.copyWith(
                              color: cs.onSurface.withValues(alpha: 0.56),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            for (final slice in slices) ...[
              _CliSliceRow(
                slice: slice,
                dimmed:
                    widget.selectedCli != null &&
                    widget.selectedCli != slice.cli,
              ),
              const SizedBox(height: 12),
            ],
          ],
          const SizedBox(height: 10),
          Divider(color: cs.outlineVariant.withValues(alpha: 0.5), height: 18),
          Text(
            l10n.sessionUsageCacheReadShare(formatUsagePercent(cacheShare)),
            style: styles.xs.copyWith(
              color: cs.onSurface.withValues(alpha: 0.56),
            ),
          ),
        ],
      ),
    );
  }
}

class _CliSliceRow extends StatelessWidget {
  const _CliSliceRow({required this.slice, required this.dimmed});

  final UsageCliSlice slice;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final styles = TpTextStyles.of(context);
    final cs = Theme.of(context).colorScheme;
    final color = usageCliColor(slice.cli);
    return Opacity(
      opacity: dimmed ? 0.42 : 1,
      child: Row(
        children: [
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              usageCliLabel(slice.cli),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: styles.smMedium,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            formatUsageTokens(slice.totalTokens),
            style: styles.smMedium,
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 42,
            child: Text(
              formatUsagePercent(slice.share),
              textAlign: TextAlign.end,
              style: styles.xs.copyWith(
                color: cs.onSurface.withValues(alpha: 0.56),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd client && dart run tool/run_tests.dart test/pages/usage/usage_cli_breakdown_test.dart`
Expected: PASS (4 tests). The hover test needs the mouse pointer to enter the ring; if it fails, assert the ring rect first with `expect(rect, isNotNull);` and adjust the y offset to `-rect.height * 0.40`.

- [ ] **Step 5: Commit**

```bash
cd /home/hhoa/git/hhoa/teampilot
git add client/lib/pages/usage/widgets/usage_cli_breakdown.dart \
  client/test/pages/usage/usage_cli_breakdown_test.dart
git commit -m "feat(usage): draw the CLI breakdown as a fl_chart donut"
```

---

### Task 5: Page-level regression and full verification

**Files:**
- Test: `client/test/pages/usage/session_usage_page_test.dart` (read; adjust only if the new layout broke an assumption)

**Interfaces:**
- Consumes: all widgets from Tasks 2-4.
- Produces: no new API.

- [ ] **Step 1: Run the whole usage test folder**

Run: `cd client && dart run tool/run_tests.dart test/pages/usage`
Expected: PASS. If `session_usage_page_test.dart` fails, open it and fix the failing expectation without changing product behaviour (e.g. a fixed height assumption), then re-run this command.

- [ ] **Step 2: Analyze the client package**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: `No issues found!`

- [ ] **Step 3: Run the full suite once**

Run: `cd client && dart run tool/run_tests.dart` (this is slow; run it in the background and continue once it reports).
Expected: all tests pass.

- [ ] **Step 4: Commit any test-only fix**

Only if Step 1 required a change:

```bash
cd /home/hhoa/git/hhoa/teampilot
git add client/test/pages/usage/session_usage_page_test.dart
git commit -m "test(usage): align page test with the chart migration"
```

If Step 1 needed no change, skip this commit.
