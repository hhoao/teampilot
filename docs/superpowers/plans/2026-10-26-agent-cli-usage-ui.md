# Agent CLI Usage UI Implementation Plan

> **For agentic workers:** Use `superpowers:subagent-driven-development`
> (recommended) or `superpowers:executing-plans`. Steps use `- [x]`.
> This plan starts after the foundation plan
> (`2026-10-26-agent-cli-usage-tracking.md`) is implemented.

**Goal:** Add the approved `Token 用量` workspace-home pane on top of the
foundation: cached-event load, manual sync, summary cards, 7-day stacked chart,
CLI distribution, grouped detail table, filters, search, and empty/error
states.

**Design spec:** `docs/superpowers/specs/2026-10-26-agent-cli-usage-tracking-design.md`
**HTML reference:** `docs/superpowers/designs/2026-10-26-agent-cli-usage-ui.html`

**Tech stack:** Flutter, `flutter_bloc`, `equatable`, existing
`shared_ui`/`TpTextStyles`, existing `WorkspacePaneHeader` patterns,
`dart run tool/run_tests.dart`.

---

## Before you start

- Work in `/home/hhoa/git/hhoa/teampilot` on the current branch.
- Never `git add -A`; every commit uses explicit paths or `-- <paths>`. The
  checkout has unrelated user changes (chat, floating workspace, work path
  projector, tests). Do not stage or edit them.
- Run tests only from `client/` with `dart run tool/run_tests.dart ...`.
- Use `flutter analyze --no-fatal-infos --no-fatal-warnings` after each task.
- No pricing/cost in this slice. No timer, no startup scan.

## File map

| File | Action | Responsibility |
|------|--------|----------------|
| `client/lib/models/session_usage_dashboard.dart` | create | UI view models: range/group enums, summary/group/chart rows, attribution |
| `client/lib/services/usage/usage_aggregator.dart` | create | Pure normalize/filter/group/chart functions |
| `client/lib/cubits/session_usage_cubit.dart` | create | Cached load, manual sync, filters, errors |
| `client/lib/app/session_usage_services.dart` | modify | Expose loaders and plane-live closures |
| `client/lib/app/app_shell.dart` | modify | Build/expose `SessionUsageCubit`, storage-change reload |
| `client/lib/main.dart` | modify | Provide the cubit to the widget tree |
| `client/lib/pages/usage/session_usage_page.dart` | create | Page shell, states, responsive layout |
| `client/lib/pages/usage/widgets/usage_summary_cards.dart` | create | Summary cards |
| `client/lib/pages/usage/widgets/usage_trend_chart.dart` | create | 7-day stacked chart |
| `client/lib/pages/usage/widgets/usage_cli_breakdown.dart` | create | CLI distribution |
| `client/lib/pages/usage/widgets/usage_detail_table.dart` | create | Grouped table + search/empty |
| `client/lib/pages/usage/usage_format.dart` | create | Token/percent/time formatting helpers |
| `client/lib/pages/home_workspace/home_workspace_global_section.dart` | modify | `HomeGlobalView.usage` |
| `client/lib/pages/home_workspace/home_workspace_sidebar.dart` | modify | Sidebar row |
| `client/lib/l10n/app_en.arb`, `client/lib/l10n/app_zh.arb` | modify | UI strings |
| `client/lib/utils/ui/app_keys.dart` | modify | Page/test keys |
| `client/test/services/usage/usage_aggregator_test.dart` | create | Aggregation tests |
| `client/test/cubits/session_usage_cubit_test.dart` | create | Load/sync/filter tests |
| `client/test/pages/usage/session_usage_page_test.dart` | create | Widget states/interactions |
| `client/test/pages/home_workspace/home_usage_navigation_test.dart` | create | Sidebar + deep link |

Keep files under ~400 lines; split widgets instead of growing the page.

---

## Task 1: View models, attribution, and pure aggregator

**Files:**
- Create: `client/lib/models/session_usage_dashboard.dart`
- Create: `client/lib/services/usage/usage_aggregator.dart`
- Create: `client/test/services/usage/usage_aggregator_test.dart`

### Step 1: Write failing aggregation tests

Cover:

- fresh input is used as-is; total semantics subtract cache (no double count).
- `total = fresh + output + cacheRead + cacheCreation`.
- cache hit rate = `cacheRead / (fresh + cacheRead)`; `0` when empty.
- range `today`/`7d`/`30d`/`all` starts at local midnight (inject `nowMs`).
- CLI filter; grouping by session/member/model/CLI.
- search applies to rows only, leaving `summary` and `chart` unchanged.
- simple member (`memberId == ''`) groups by session, not one shared bucket.
- unknown model/session/team/member fall back to readable labels.
- chart has exactly seven local-day buckets and uses all CLIs.
- CLI slices use the last seven days, independent of the range filter.

### Step 2: Implement

`session_usage_dashboard.dart`:

```dart
enum UsageRange { today, sevenDays, thirtyDays, all }
enum UsageGroupBy { session, member, model, cli }

@immutable
final class UsageAttribution {
  const UsageAttribution({
    this.sessionTitles = const {},
    this.teamNames = const {},
    this.memberNames = const {},
  });
  // memberNames keys: '<sessionId>\u0000<memberId>' and
  // '<teamId>\u0000<memberId>'.

  factory UsageAttribution.fromSessionsAndTeams({
    required List<AppSession> sessions,
    required List<TeamProfile> teams,
  });

  String sessionTitle(String sessionId);
  String teamName(String teamId);
  String memberName({
    required String sessionId,
    required String teamId,
    required String memberId,
  });
}

@immutable
final class UsageFilter {
  const UsageFilter({
    this.range = UsageRange.all,
    this.cli,
    this.groupBy = UsageGroupBy.session,
    this.query = '',
  });
}

@immutable
final class UsageSummary { /* total, freshInput, output, cacheRead,
  cacheCreation, requests, sessions, cacheHitRate */ }

@immutable
final class UsageGroup { /* key, label, subtitle, clis, total, freshInput,
  output, cacheRead, cacheCreation, requests, sessions, lastUsedMs */ }

@immutable
final class UsageChartDay { /* dayStartMs, tokensByCli */ }
@immutable
final class UsageCliSlice { /* cli, total, requests, share */ }

@immutable
final class UsageDashboard {
  final UsageSummary summary;
  final List<UsageGroup> rows;
  final List<UsageChartDay> chart;
  final List<UsageCliSlice> cliSlices;
  final int matchedEventCount;
  final int totalEventCount;
}
```

`usage_aggregator.dart` exposes one entry point plus small pure helpers:

```dart
UsageDashboard buildUsageDashboard({
  required List<SessionUsageEvent> events,
  required UsageAttribution attribution,
  required UsageFilter filter,
  required int nowMs,
});

int usageTotalTokens(SessionUsageEvent event);
int usageFreshInputTokens(SessionUsageEvent event);
int? usageRangeStartMs(UsageRange range, int nowMs);
String usageDayLabelKey(int dayStartMs); // UI localizes "今天"/date
```

Rules:

- `summary` is range + CLI filtered, not query filtered.
- `rows` is range + CLI + query filtered, then grouped by `filter.groupBy`.
- Member key: `memberId` empty → `'session:$sessionId'`; otherwise
  `'$teamId\u0000$memberId'`. Label via attribution, then `memberId`.
- Session label via attribution; model label `model` or unknown key; CLI label
  is the `cli.value` (UI maps brand names).
- `subtitle`: team name for member/session; session title for member; CLI
  brand list or "n sessions" for others. Keep aggregator free of l10n: use
  ids/brand names and a small enum/`String` sentinel for "unknown"/"simple";
  UI localizes sentinels.
- `chart` and `cliSlices` always use the last seven local days and all CLIs.
- Do not mutate event values; use `event.freshInputTokens`.

### Step 3: Run and commit

```bash
cd /home/hhoa/git/hhoa/teampilot/client
dart run tool/run_tests.dart test/services/usage/usage_aggregator_test.dart
flutter analyze --no-fatal-infos --no-fatal-warnings
```

Commit only the three files.

---

## Task 2: `SessionUsageCubit`

**Files:**
- Create: `client/lib/cubits/session_usage_cubit.dart`
- Create: `client/test/cubits/session_usage_cubit_test.dart`

### Contract

```dart
enum SessionUsageStatus { initial, loading, ready, error }

final class SessionUsageState extends Equatable {
  final SessionUsageStatus status;
  final UsageDashboard dashboard;
  final UsageRange range;
  final CliTool? cli;
  final UsageGroupBy groupBy;
  final String query;
  final bool isSyncing;
  final int? lastSyncAtMs;
  final UsageSyncResult? lastSyncResult;
  final List<UsageSyncError> syncErrors;
  final bool syncFailed;
  final String? errorMessage;
}

final class SessionUsageCubit extends Cubit<SessionUsageState> {
  SessionUsageCubit({
    required Future<List<SessionUsageEvent>> Function() loadEvents,
    required Future<UsageSyncResult> Function() syncAll,
    required Future<List<AppSession>> Function() loadSessions,
    required Future<List<TeamProfile>> Function() loadTeams,
    Stream<void>? storageChanges,
    DateTime Function()? now,
  });

  Future<void> ensureLoaded();
  Future<void> reload();
  Future<void> sync();
  void setRange(UsageRange range);
  void setCli(CliTool? cli);
  void setGroupBy(UsageGroupBy groupBy);
  void setQuery(String query);
  void resetFilters();
  void clearSyncErrors();
}
```

Behavior:

- `ensureLoaded()` is single-flight and only loads from `initial`.
- `reload()` reads events + sessions + teams, builds attribution, recomputes
  dashboard with current filters. It never scans transcripts.
- `sync()` is single-flight; sets `isSyncing`; calls `syncAll()`; always
  reloads cached events afterward; keeps data on partial/fatal errors.
- `storageChanges` subscription triggers `reload()` (plane swap).
- Filter/query changes recompute from cached events without I/O.
- No l10n and no widgets in the cubit.

### Tests

- initial → loading → ready with empty dashboard.
- events load and summary/rows are computed.
- range/CLI/group/search updates only recompute; loaders are not called again.
- sync success updates `lastSyncAtMs`, reloads, clears errors.
- partial sync errors keep data and expose `syncErrors`.
- fatal sync keeps old dashboard, sets `syncFailed`.
- storage change triggers reload.
- `ensureLoaded` does not double-load; `sync` does not double-run.

---

## Task 3: App wiring

**Files:**
- Modify: `client/lib/app/session_usage_services.dart`
- Modify: `client/lib/app/app_shell.dart`
- Modify: `client/lib/main.dart`
- Modify: `client/test/app/session_usage_services_test.dart`

### Steps

1. Make `SessionUsageServices` expose `syncAll`, `loadEvents`, `loadSessions`,
   `loadTeams`. Build the JSON store and sync service **per call** from the
   current `HomeStorage` so a home-plane swap is picked up automatically.
2. Construct one `SessionUsageCubit` in `buildAppShell` with
   `SessionUsageServices.forStorage(storage: homeStorage)` and
   `storageChanges: homeStorage.changes.map<void>((_) {})`.
3. Add `final SessionUsageCubit sessionUsageCubit` to `AppShell`; pass it in
   the constructor; add an optional injected cubit parameter if tests need it.
4. Provide `BlocProvider.value(value: shell.sessionUsageCubit)` in both
   `main.dart`'s app tree and `app_shell.dart`'s bootstrap provider block.
5. Extend the factory smoke test to assert `loadEvents()` is empty before any
   sync and still empty after a sync with no targets.

No widget page yet; analyzer and factory/cubit tests only.

---

## Task 4: Usage page and widgets

**Files:**
- Create: `client/lib/pages/usage/session_usage_page.dart`
- Create: `client/lib/pages/usage/usage_format.dart`
- Create: `client/lib/pages/usage/widgets/usage_summary_cards.dart`
- Create: `client/lib/pages/usage/widgets/usage_trend_chart.dart`
- Create: `client/lib/pages/usage/widgets/usage_cli_breakdown.dart`
- Create: `client/lib/pages/usage/widgets/usage_detail_table.dart`
- Modify: `client/lib/l10n/app_en.arb`, `app_zh.arb`
- Modify: `client/lib/utils/ui/app_keys.dart`
- Create: `client/test/pages/usage/session_usage_page_test.dart`

### Page structure

- `SessionUsagePage({this.embedded = false})`; on first frame call
  `ensureLoaded()`.
- Header: title, scope subtitle, last sync, sync button (disabled while
  syncing; spinner in the icon slot). Use the existing pane padding/typography.
- Sync error banner: dismissible; shows count and retry. Data remains.
- Toolbar: range `ChoiceChip`s, CLI `ChoiceChip`s, group-by `ChoiceChip`s.
- Summary cards: total, fresh input, output, cache read; subtexts include
  requests/sessions, share, cache hit rate, cache write, sparkline. Use a
  `Wrap` with responsive widths (4 across wide, 2 medium, 1 narrow).
- Chart card + CLI distribution card: `Row` wide, stacked narrow. Chart uses
  fixed seven local days and dims non-selected CLI segments when a CLI filter
  is active.
- Detail table: header + rows; horizontal scroll below ~900px; share bar;
  CLI badges; table-local search field; empty state with reset/sync.
- Footer: shown/total count, "JSONL 只读", "手动同步".
- Loading: spinner only when no cached events. Error with no data: retry.
- Empty: icon + title/body + sync/reset.

### L10n and keys

Add keys to both ARB files only. Suggested key family:
`sessionUsageNav`, `sessionUsageTitle`, `sessionUsageSubtitle`,
`sessionUsageScopeHint`, `sessionUsageSync`, `sessionUsageSyncing`,
`sessionUsageLastSync`, `sessionUsageNeverSynced`, `sessionUsageRange*`,
`sessionUsageCliAll`, `sessionUsageGroup*`, `sessionUsageTotalTokens`,
`sessionUsageInputTokens`, `sessionUsageOutputTokens`, `sessionUsageCacheRead`,
`sessionUsageCacheWrite`, `sessionUsageCacheHit`, `sessionUsageRequestsSessions`,
`sessionUsageChartTitle`, `sessionUsageChartSubtitle`,
`sessionUsageCliBreakdown`, `sessionUsageSearchHint`, `sessionUsageEmpty*`,
`sessionUsageResetFilters`, `sessionUsageSyncPartial`, `sessionUsageSyncFailed`,
`sessionUsageRetry`, `sessionUsageShare`, `sessionUsageShowing`,
`sessionUsageGroupCount`, `sessionUsageUnknownModel`, `sessionUsageSimpleSeat`.

Keys: `AppKeys.sessionUsagePage`, `sessionUsageSyncButton`,
`sessionUsageSearchField`, `sessionUsageErrorBanner`,
`sessionUsageEmptyState`, `sessionUsageTable`.

### Widget tests

- empty state renders and sync button calls `sync`.
- summary cards show formatted totals.
- range/CLI/group chips update the cubit.
- error banner shows on `syncErrors`/`syncFailed` and dismisses.
- search filters rows but not summary.
- sync button disabled while `isSyncing`.
- page does not scan on load (fake loader count).

---

## Task 5: Sidebar, global view, deep link

**Files:**
- Modify: `client/lib/pages/home_workspace/home_workspace_global_section.dart`
- Modify: `client/lib/pages/home_workspace/home_workspace_sidebar.dart`
- Create: `client/test/pages/home_workspace/home_usage_navigation_test.dart`

### Steps

1. Add `usage` to `HomeGlobalView` (its `routeSegment` is `usage`, so
   `/home-v2?global=usage` works through the existing enum).
2. Render `const SessionUsagePage(embedded: true)` for that view.
3. Add a sidebar `_ShortcutRow` with
   `Icons.insights_outlined`, `l10n.sessionUsageNav`, active state, directly
   after the provider `余额与用量` row. Do not reuse the provider bottom button.
4. Test: tapping the row shows the usage page; `HomeGlobalView.fromSegment
   ('usage')` and `homeLocation` round-trip; deep link builds the pane.

---

## Task 6: Verification

```bash
cd /home/hhoa/git/hhoa/teampilot/client
dart run tool/run_tests.dart \
  test/services/usage/usage_aggregator_test.dart \
  test/cubits/session_usage_cubit_test.dart \
  test/pages/usage/session_usage_page_test.dart \
  test/pages/home_workspace/home_usage_navigation_test.dart
flutter analyze --no-fatal-infos --no-fatal-warnings
```

Then run the full suite once in the background:
`dart run tool/run_tests.dart` (see `docs/DEVELOPMENT.md`). Report known
follow-ups: no scheduler, no pricing, no proxy, no ACP live meter, fixed
7-day chart context.
