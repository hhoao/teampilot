# Token usage: replace hand-rolled charts with fl_chart

## Scope

Replace the three hand-built charts on the session usage page with
[`fl_chart`](https://pub.dev/packages/fl_chart) widgets:

- `UsageTrendChart` → stacked daily `BarChart` (CLI segments);
- `UsageSparkline` inside the summary card → axis-less mini `BarChart`;
- `UsageCliBreakdown` → donut `PieChart` plus the existing CLI rows.

No changes to the aggregator, dashboard models, cubit, filters, l10n keys, or
data flow. The public widget constructors stay the same, so
`session_usage_page.dart` only changes if a layout box needs adjusting.

## Dependency

Add to `client/pubspec.yaml`:

```yaml
fl_chart: ^1.3.0
```

Compatibility: fl_chart 1.3.0 needs Dart `>=3.6.2` and Flutter `>=3.27.4`; the
project is on Dart 3.8.1 / Flutter 3.47. It is pure Dart with no native
plugins, so Android/desktop builds are unaffected. `pubspec.lock` is updated by
`flutter pub get` and committed with the change.

## Current behaviour to preserve

- Chart card chrome: title, subtitle, total and average in the header.
- Empty state (`maxTotal == 0`) showing `sessionUsageNoData` in the same
  180px box.
- CLI legend below the chart: dot, `label · tokens`, dimmed rows when a CLI is
  selected.
- `selectedCli` dimming semantics (selected CLI full opacity, others 0.22).
- Breakdown card: title, CLI rows with dot / label / tokens / share, cache-read
  share footer, empty state.

## Trend chart (`pages/usage/widgets/usage_trend_chart.dart`)

Mapping:

- One `BarChartGroupData(x: index)` per `UsageChartDay`.
- One `BarChartRodData` per group with `rodStackItems` in `legendClis` order;
  skip CLIs whose token count is zero for that day. Segment colours come from
  `usageCliColor(cli)`; alpha is `0.92` when the CLI is selected or no filter is
  active, `0.22` otherwise.
- `toY` of the rod = day total; `barRodData.width` is
  `availableWidth / days.length * 0.46` clamped to `3..18` so 30-day bars stay
  narrow but still visible; `borderRadius` 3 on the top segment only.
- `maxY = maxTotal * 1.12` so the tallest bar has headroom.
- `duration: 260ms`, `curve: Curves.easeOutCubic` — changing the range animates
  bar heights.

Axes and grid:

- Left `SideTitles` with 3 ticks (`0`, `max/2`, `max`), `formatUsageTokens`,
  `reservedSize` ~34, low-alpha label colour from `cs.onSurface`.
- Bottom `SideTitles` with `formatUsageDayLabel(context, dayStartMs, nowMs)`.
  When `days.length > 7`, show every `usageChartLabelStride(days.length)`-th
  label. Labels are anchored to the newest day —
  `(days.length - 1 - index) % stride == 0` — so "today" is always labelled and
  thinning removes older labels, never the last one. The axis still keeps one
  slot per day so bars stay evenly spaced. `usageChartLabelStride` is a small
  pure helper in `usage_format.dart` (`max(1, (dayCount / 7).ceil())`) so the
  thinning rule is unit-testable.
- `FlGridData`: horizontal lines only, `cs.outlineVariant` at low alpha, no
  vertical lines. `FlBorderData(show: false)` with a single bottom axis line if
  it reads better against the card.

Touch:

- `BarTouchData(enabled: true, handleBuiltInTouches: true, touchTooltipData: …)`.
  fl_chart's built-in handler resolves the touched group/rod and asks
  `getTooltipItem` for content, so the tooltip can list **every CLI plus the
  total** for that day (the group index maps back to `days`).
- Content is a `BarTooltipItem` whose `text` is the day label and whose
  `children` are one `TextSpan` per CLI (`usageCliLabel`, `·`, tokens, coloured
  by `usageCliColor`) plus a total line. Styles come from `TpTextStyles`
  captured from `build`; `maxContentWidth` is raised from the 120 default to
  ~190 so rows do not wrap.
- `fitInsideHorizontally` / `fitInsideVertically` are true. Interaction is
  hover on desktop and tap-down / long-press on touch devices; the tooltip
  clears on tap-up or when the pointer leaves the chart.

Height grows from 160 to 180 to fit the axis labels. The header row, legend
wrap, and card decoration are unchanged.

## Summary sparkline (`pages/usage/widgets/usage_summary_cards.dart`)

`UsageSparkline` becomes an axis-less `BarChart`:

- One group per day, one rod whose height is the day total. Because strictly
  proportional rods make low-volume days disappear, the rod height is floored:
  zero days get `maxY * 0.12` at alpha `0.24`, non-zero days below
  `maxY * 0.10` get `maxY * 0.10`, everything else gets
  `tokens.toDouble()`. Colour is `cs.primary` alpha `0.56` (`maxY` is 1 when
  the range is all zero).
- `titlesData`, `gridData`, `borderData` and `barTouchData` disabled; fixed
  height 26, fixed 6px rod width (same as today).
- No animation needed (`duration: Duration.zero`) so the card does not move on
  rebuild.

## CLI breakdown (`pages/usage/widgets/usage_cli_breakdown.dart`)

- Add a centred donut above the rows: `PieChart` in a `SizedBox` of height
  150 and full card width, `PieChartData(centerSpaceRadius: 44)` with
  `sectionsSpace: slices.length > 1 ? 2 : 0` so a single-CLI ring has no notch.
- Sections come from `slices`: `value = totalTokens.toDouble()`, colour
  `usageCliColor`, `radius` 28 (30 while touched) so a large centre hole fits
  the readout. Segment alpha follows `selectedCli`.
- Centre overlay (`Stack` + `IgnorePointer`, one `FittedBox(scaleDown)` around
  the readout so tokens, label and share shrink together): three stacked lines.
  Untouched, it shows the donut total in `styles.mdBold`,
  `sessionUsageChartTitle` ("Last 7 days" / "近 7 天消耗") in `styles.xs` muted —
  it is the fixed seven-day slice total, not the range-filtered summary, so it
  must not reuse `sessionUsageTotalTokens`. When the pointer or a long-press is
  over a section, the centre switches to that CLI: tokens, label, and share.
- fl_chart 1.3 has no built-in pie tooltip, so hover is handled with
  `PieTouchData(touchCallback: …)` storing the touched **CLI** (mapped from the
  touched section index) in local state, so a re-sorted `slices` list keeps the
  highlight on the same tool. The touched section grows to radius 30 (44 + 30
  = 74, a 1px inset inside the 150px box); every other interaction (rows,
  colours) is unchanged.
- Remove `LinearProgressIndicator` from `_CliSliceRow`; the row keeps dot,
  label, tokens, and share.
- Keep the divider and cache-read share footer, and the empty state (no donut,
  same centred `sessionUsageNoData` text).
- Row dimming stays as `Opacity(0.42)` when another CLI is selected.

The breakdown card sits in a fixed 300px column on wide layouts, so the donut
is sized to fit that width minus padding. On narrow layouts it stacks under the
trend chart with no height changes to the page.

## Edge cases

- All-zero data: trend and breakdown keep their empty states; the sparkline
  shows the faint baseline.
- One CLI only: a single full segment; no gap artefacts from `sectionsSpace`.
- `days` empty: chart area shows the empty state, no axis callbacks are called.
- Very large numbers: axis and tooltip values stay on `formatUsageTokens`
  (`K` / `M`) and never render raw 7-digit integers.
- Text scaling: axis/tooltip text uses `TpTextStyles`, so a 1.4 scale must not
  overflow; the existing overflow tests are extended to cover it.

## Testing

- `test/pages/usage/usage_trend_chart_test.dart`
  - keep the two "fits" cases (default and 1.4 text scale);
  - assert `find.byType(BarChart)` is present and the empty state still renders
    for all-zero days;
  - add a 30-day case that pumps without exceptions and verifies label thinning
    through `usageChartLabelStride` (unit test) plus a widget smoke test;
  - settle animations with `pumpAndSettle` before assertions.
- `test/pages/usage/usage_format_test.dart` (new)
  - `usageChartLabelStride`: 7 days → 1, 14 → 2, 30 → 5, 1 → 1.
- `test/pages/usage/usage_summary_cards_test.dart`
  - assert the sparkline renders a `BarChart` and keeps its 26px height.
- `test/pages/usage/usage_cli_breakdown_test.dart` (new)
  - renders `PieChart` with slices, shows the centre total;
  - empty slices show `sessionUsageNoData` and no `PieChart`;
  - selecting a CLI dims the other rows (`Opacity` check);
  - tapping the donut ring updates the centre readout to that CLI's label.
- Commands: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
  then `dart run tool/run_tests.dart test/pages/usage`, followed by the full
  suite once before claiming done.

## Out of scope

- Click-to-filter by bar/segment (state changes stay in the toolbar).
- Chart theming in `shared_ui` or exporting chart primitives.
- Persisting chart preferences, zooming, or exporting images.
