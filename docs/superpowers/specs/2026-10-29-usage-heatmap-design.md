# Usage heatmap (cc-switch style)

## Scope

Add a GitHub/cc-switch-style usage heatmap card to the session usage page:

- a 53-week rolling grid, Monday-first, with month labels, weekday labels and
  four metric modes (tokens / requests / cost / cache-hit rate);
- day-level hover (desktop) or long-press (touch) tooltip with tokens,
  requests, cost and hit rate;
- an earlier-history span expansion ("Show earlier") when the account predates
  the current 53-week window.

The heatmap ignores the page's time-range and search filters and follows only
the CLI filter. It never adds storage: the usage cubit already loads every
event, so the grid is derived from existing events.

## Decisions

| Question | Decision |
|----------|----------|
| Data placement | Extend `UsageDashboard` with a day-level series; no new cubit state |
| Time window | Fixed trailing 53 weeks (Monday-aligned); older years behind "Show earlier" |
| Filters | CLI filter only; ignore range and query |
| Metric | Local switch: tokens (default), requests, cost, cache hit rate |
| Colour scale | Quartiles over all non-empty visible days, 4 levels + empty |
| Tooltip | Material `Tooltip` per cell; full date + all four metrics |
| Placement | Full-width card between `UsageCostCard` and the trend/breakdown row |

## Model (`models/session_usage_dashboard.dart`)

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

  final int dayStartMs;      // local midnight
  final int tokens;          // billed total, same as usageTotalTokens
  final int requests;
  final int costMicroUsd;
  final double? cacheHitRate; // null when fresh input + cache read == 0
}
```

`UsageDashboard` gains `final List<UsageHeatmapDay> heatmap;` — ascending,
only days that have at least one event. `UsageDashboard` defaults to `const []`.

## Aggregation (`services/usage/usage_aggregator.dart`)

`buildUsageDashboard` already receives every event. Add a third pass that:

- filters by `filter.cli` only (not `rangeStart`, not `query`);
- buckets by local midnight of `event.timestampMs`, using the same
  `DateTime(y, m, d)` conversion as `_chart`;
- sums `usageTotalTokens`, request count and `calculateUsageCost(...).microUsd`
  (unpriced events add requests/tokens but no cost);
- accumulates fresh input and cache read per day, then sets
  `cacheHitRate = fresh + cacheRead == 0 ? null : cacheRead / (fresh + cacheRead)`.

Result is sorted ascending and returned as `List.unmodifiable`.

Cost is computed with the same pricing catalog already passed to the
aggregator, so heatmap cost matches the cost card.

## Layout math (`pages/usage/widgets/usage_heatmap_layout.dart`)

A pure, widget-free file so the calendar math is unit-testable:

```dart
const int usageHeatmapWeeks = 53;

final class UsageHeatmapSpan {
  final int startDayMs;     // Monday, local midnight
  final int endDayMs;       // today for span 0, otherwise the day before the next span
  final List<List<int>> weekDayStarts; // 53 weeks x 7 day-midnights
  final int tokens;
  final int requests;
  final int costMicroUsd;
}

int usageHeatmapSpanCount(List<UsageHeatmapDay> days, int nowMs);
List<UsageHeatmapSpan> usageHeatmapSpans({
  required List<UsageHeatmapDay> days,
  required int nowMs,
});
List<double> usageHeatmapThresholds(Iterable<double> values);
int usageHeatmapLevel(double? value, List<double> thresholds);
```

Rules:

- `today` = local midnight of `nowMs`; `thisMonday = today - (weekday - 1) days`
  (`DateTime.weekday`: Mon = 1).
- `spanStart(i) = thisMonday - ((52 + i * 53) * 7) days`; `spanStart(0)` is the
  Monday 52 weeks before this week, so span 0 has 53 columns ending with the
  current week.
- `spanCount`: 0 when `days` is empty; otherwise
  `1 + max(0, ceil(daysBetween(earliestDay, spanStart(0)) / (53 * 7)))`.
  Day distances use `DateTime.utc(y, m, d)` differences so DST cannot shift a
  week.
- Cells after `today` are marked future and excluded from span totals and level
  thresholds.
- Thresholds are computed over every span's non-future cells for the selected
  metric, independent of whether earlier spans are currently expanded, so
  colours do not change when "Show earlier" toggles.
- Thresholds: sort non-null values, take elements at `floor(n * 0.25/0.5/0.75)`
  (clamped to `n - 1`). Empty input returns `[inf, inf, inf]`.
- Levels: null → 0; `<= t0` → 1; `<= t1` → 2; `<= t2` → 3; else 4.

## Widget (`pages/usage/widgets/usage_heatmap_card.dart`)

`UsageHeatmapCard({required List<UsageHeatmapDay> days, required int nowMs})`,
stateful only for the selected metric and `_showEarlier`.

Header:

- title `sessionUsageHeatmapTitle`, subtitle `sessionUsageHeatmapSubtitle`;
- `TpSegmentedControl` (outlined, 4 segments, keyed by the selected metric) on
  the right; below the title when the card is narrower than 620px.

Body:

- one block per visible span, newest first; each block shows the date range
  (`MaterialLocalizations.formatShortDate`) and
  `sessionUsageHeatmapSpanSummary(tokens, requests, cost)`;
- month labels row: label a column when it contains day 1 of a month (first
  column always labelled), formatted with `DateFormat.MMM(localeName)` from
  `intl` (`localeName` = `Localizations.localeOf(context).toLanguageTag()`);
  the text may overflow its 6–14px column, painting over neighbours (no
  clipping);
- weekday labels: Monday / Wednesday / Friday from
  `MaterialLocalizations.narrowWeekdays` (rows 0, 2, 4 only), fixed
  Monday-first;
- cell size `((availableWidth - gaps) / 53).clamp(6, 14)`; if the resulting grid
  is wider than the card, the whole grid scrolls horizontally;
- cell decoration: 3px radius, empty `cs.surfaceContainerHighest`, level 1–4
  `cs.primary` at alpha `0.20 / 0.38 / 0.58 / 0.82`;
- each cell is a `Tooltip` whose message is the localized full date followed by
  `Tokens`, `Requests`, `Cost` and `Hit rate` lines; empty days show zeros and
  `—` for hit rate. `waitDuration` 150ms.

Footer: legend (`sessionUsageHeatmapLess` + 5 swatches + `More`) and, when
`spanCount > 1`, a text button toggling `sessionUsageHeatmapShowEarlier` /
`sessionUsageHeatmapShowLess`.

Metric values:

- tokens: `day.tokens > 0 ? day.tokens : null`;
- requests: `day.requests > 0 ? day.requests : null`;
- cost: `day.costMicroUsd > 0 ? day.costMicroUsd : null`;
- hit rate: `day.cacheHitRate` (null when absent).

Empty input renders the existing `sessionUsageNoData` message inside a 120px
box, with no grid or legend.

The page inserts the card in `_buildBody` after `UsageCostCard` with the same
14px spacing used between the other cards.

## i18n

Add to `client/lib/l10n/app_en.arb` and `app_zh.arb` only:

| Key | en | zh |
|-----|----|----|
| `sessionUsageHeatmapTitle` | Usage heatmap | 用量热力图 |
| `sessionUsageHeatmapSubtitle` | Last 53 weeks · hover or long-press a day | 近 53 周 · 悬停或长按查看当天明细 |
| `sessionUsageHeatmapMetricTokens` | Tokens | Token |
| `sessionUsageHeatmapMetricHitRate` | Hit rate | 命中率 |
| `sessionUsageHeatmapShowEarlier` | Show earlier | 显示更早 |
| `sessionUsageHeatmapShowLess` | Show less | 收起更早 |
| `sessionUsageHeatmapLess` | Less | 少 |
| `sessionUsageHeatmapMore` | More | 多 |
| `sessionUsageHeatmapSpanSummary` | {tokens} tokens · {requests} requests · {cost} | {tokens} Token · {requests} 请求 · {cost} |

Requests and cost segment labels reuse `sessionUsageRequests` and
`sessionUsageCost`. Generated localizations are rebuilt by the normal build.

## Testing

- `test/services/usage/usage_aggregator_test.dart` (extend): CLI filter,
  local-day bucketing across midnight, cost from pricing, hit rate null when
  there is no input, ascending order, empty events → empty heatmap.
- `test/pages/usage/usage_heatmap_layout_test.dart` (new): span count for 0 /
  1 / 53 weeks / 54 weeks / 2 years; span 0 starts on a Monday and ends today;
  future cells excluded; thresholds/levels for empty, single value and skewed
  distributions; DST-safe day arithmetic.
- `test/pages/usage/usage_heatmap_card_test.dart` (new): renders the expected
  number of cells for one span; metric switch changes cell colours/levels;
  empty days render the level-0 colour; tooltip text contains tokens,
  requests, cost and hit rate; `Show earlier` appears only with a second span
  and reveals it; 400px-wide layout does not overflow.
- `test/pages/usage/session_usage_page_test.dart` (extend): the heatmap card is
  present once data loads.

Commands: `flutter analyze --no-fatal-infos --no-fatal-warnings`, then
`dart run tool/run_tests.dart test/pages/usage test/services/usage`, then the
full suite once.

## Out of scope

- Range/query filters inside the heatmap.
- Clicking a day to filter the detail table.
- Persisting the selected metric or the expanded state.
- A separate account-level (Cursor) heatmap; this card reads the same
  `SessionUsageEvent` stream as the rest of the page.
