# Cursor Multi-Account Usage Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a dedicated Cursor usage page that reports token usage and cost for any date range across every Cursor account, discovered automatically or added manually, and make those accounts count in the session usage totals.

**Architecture:** A new `services/cursor_usage/` feature reads Cursor's `get-filtered-usage-events` endpoint, fills only the uncovered parts of the requested range, and caches per-account day aggregates plus 90 days of raw events. A cubit drives a `pages/cursor_usage/` UI registered as a new home global view. The cache is also the single source for account-level Cursor rows in the session usage dashboard, replacing the old single-account CSV import path entirely.

**Tech Stack:** Flutter, `flutter_bloc` Cubit, `http`, `flutter_secure_storage` (via the existing `SecureKeyValueStore` interface), `equatable`, `crypto`.

**Spec:** [`docs/superpowers/specs/2026-10-28-cursor-usage-multi-account-design.md`](../specs/2026-10-28-cursor-usage-multi-account-design.md)

## Global Constraints

- Never invoke `flutter test`. Run tests as `cd client && dart run tool/run_tests.dart <path>`.
- Before claiming done: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && dart run tool/run_tests.dart`.
- Inject `Filesystem` / `HomeStorage`; never use `Directory.current`.
- l10n edits go to `client/lib/l10n/app_en.arb` and `app_zh.arb` only.
- State classes use `Equatable` + a manual `copyWith`. No Freezed. No `ChangeNotifier`.
- Diagnostics go through `AppLogger.instance.d/w/i`. No `print`.
- Soft file limits: `services/` ~600 lines, `cubits/` ~500, `pages/<domain>/` ~400-500.
- Tests use `test/support/in_memory_filesystem.dart`; no network in tests.
- Error text shown to users comes from l10n, never from an exception's `toString`.
- Account-level Cursor usage has exactly one source of truth: `cursor_usage/cache/<accountId>.json`. Nothing may read `usage/cursor_import.json` again.

---

### Task 1: Paths, enums, and models

**Files:**
- Modify: `client/lib/services/storage/app_paths.dart` (add Cursor usage paths near `usageCursorImportFile`, around line 362)
- Create: `client/lib/models/cursor_usage_account.dart`
- Create: `client/lib/models/cursor_usage_range.dart`
- Create: `client/lib/models/cursor_usage_report.dart`
- Test: `client/test/models/cursor_usage_models_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `AppPaths.cursorUsageDir`, `AppPaths.cursorUsageAccountsFile`, `AppPaths.cursorUsageUiStateFile`, `AppPaths.cursorUsageCacheFile(String accountId)`
  - `enum CursorAccountSource { discovered, manual }`
  - `final class CursorUsageAccount` with `accountId, userId, label, source, enabled, expiresAtMs, owningUser, teamId, hasCredential` + `copyWith` + `isExpired(int nowMs)`
  - `final class CursorAccountCredentials` with `accountId, userId, token, expiresAtMs` + `String get cookie`
  - `enum CursorUsagePreset { billingCycle, today, sevenDays, thirtyDays, lastMonth }`
  - `sealed class CursorUsageRange` / `CursorUsagePresetRange` / `CursorUsageCustomRange`
  - `final class CursorUsageWindow` with `startMs, endMs` + `contains`
  - `final class CursorUsageModelTotals`, `CursorUsageDay`, `CursorUsageEvent`, `CursorUsageCache`, `CursorUsageReport`

- [ ] **Step 1: Add the path helpers**

In `client/lib/services/storage/app_paths.dart`, directly after `usageCursorImportFile`:

```dart
  /// Account-level Cursor usage: account catalog, UI state, per-account cache.
  String get cursorUsageDir => _ctx.join(basePath, 'cursor_usage');

  String get cursorUsageAccountsFile =>
      _ctx.join(cursorUsageDir, 'accounts.json');

  String get cursorUsageUiStateFile => _ctx.join(cursorUsageDir, 'ui_state.json');

  String cursorUsageCacheFile(String accountId) =>
      _ctx.join(cursorUsageDir, 'cache', '$accountId.json');
```

- [ ] **Step 2: Write the failing model test**

Create `client/test/models/cursor_usage_models_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/cursor_usage_account.dart';
import 'package:teampilot/models/cursor_usage_report.dart';

void main() {
  test('cookie rebuilds the WorkosCursorSessionToken header', () {
    const credentials = CursorAccountCredentials(
      accountId: 'abc123',
      userId: 'user_01ABC',
      token: 'eyJ.payload.sig',
      expiresAtMs: 2000000000000,
    );
    expect(
      credentials.cookie,
      'WorkosCursorSessionToken=user_01ABC%3A%3AeyJ.payload.sig',
    );
  });

  test('isExpired treats a token inside the 60s guard as expired', () {
    const account = CursorUsageAccount(
      accountId: 'abc123',
      userId: 'user_01ABC',
      label: 'Cursor · abc123',
      source: CursorAccountSource.manual,
      expiresAtMs: 1000000,
    );
    expect(account.isExpired(939999), isFalse);
    expect(account.isExpired(940000), isTrue);
    expect(account.isExpired(2000000), isTrue);
  });

  test('day totals round-trip through json', () {
    const day = CursorUsageDay(
      dayMs: 1790000000000,
      inputTokens: 10,
      outputTokens: 20,
      cacheReadTokens: 30,
      cacheWriteTokens: 40,
      totalCents: 1.5,
      chargedCents: 0.5,
      eventCount: 2,
      models: {
        'cursor-grok-4.6-high': CursorUsageModelTotals(
          inputTokens: 10,
          outputTokens: 20,
          cacheReadTokens: 30,
          cacheWriteTokens: 40,
          totalCents: 1.5,
          chargedCents: 0.5,
          eventCount: 2,
        ),
      },
    );
    expect(CursorUsageDay.fromJson(day.toJson()), day);
  });
}
```

- [ ] **Step 3: Run the test to confirm it fails**

Run: `cd client && dart run tool/run_tests.dart test/models/cursor_usage_models_test.dart`
Expected: FAIL — `Error: Couldn't resolve the package 'teampilot/models/cursor_usage_account.dart'`.

- [ ] **Step 4: Create the account model**

`client/lib/models/cursor_usage_account.dart`:

```dart
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

enum CursorAccountSource { discovered, manual }

/// Metadata for one Cursor account. The session token is NOT part of this
/// class: it lives in secure storage and is read on demand, so a list render
/// can never leak it through `toString` or equality.
@immutable
final class CursorUsageAccount extends Equatable {
  const CursorUsageAccount({
    required this.accountId,
    required this.userId,
    required this.label,
    required this.source,
    this.enabled = true,
    this.expiresAtMs,
    this.owningUser,
    this.teamId = 0,
    this.hasCredential = false,
  });

  final String accountId;
  final String userId;
  final String label;
  final CursorAccountSource source;
  final bool enabled;
  final int? expiresAtMs;
  final String? owningUser;
  final int teamId;
  final bool hasCredential;

  /// Expired when the token would die inside the next minute.
  bool isExpired(int nowMs) {
    final expires = expiresAtMs;
    return expires == null || expires <= nowMs + 60000;
  }

  CursorUsageAccount copyWith({
    String? label,
    bool? enabled,
    int? expiresAtMs,
    String? owningUser,
    int? teamId,
    bool? hasCredential,
    CursorAccountSource? source,
  }) => CursorUsageAccount(
    accountId: accountId,
    userId: userId,
    label: label ?? this.label,
    source: source ?? this.source,
    enabled: enabled ?? this.enabled,
    expiresAtMs: expiresAtMs ?? this.expiresAtMs,
    owningUser: owningUser ?? this.owningUser,
    teamId: teamId ?? this.teamId,
    hasCredential: hasCredential ?? this.hasCredential,
  );

  Map<String, Object?> toJson() => {
    'accountId': accountId,
    'userId': userId,
    'label': label,
    'source': source.name,
    'enabled': enabled,
    'expiresAtMs': expiresAtMs,
    'owningUser': owningUser,
    'teamId': teamId,
  };

  factory CursorUsageAccount.fromJson(Map<String, Object?> json) {
    final source = CursorAccountSource.values.firstWhere(
      (value) => value.name == json['source'],
      orElse: () => CursorAccountSource.manual,
    );
    return CursorUsageAccount(
      accountId: json['accountId']?.toString() ?? '',
      userId: json['userId']?.toString() ?? '',
      label: json['label']?.toString() ?? '',
      source: source,
      enabled: json['enabled'] != false,
      expiresAtMs: (json['expiresAtMs'] as num?)?.toInt(),
      owningUser: json['owningUser']?.toString(),
      teamId: (json['teamId'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  List<Object?> get props => [
    accountId,
    userId,
    label,
    source,
    enabled,
    expiresAtMs,
    owningUser,
    teamId,
    hasCredential,
  ];
}

/// A resolvable credential. `cookie` is the only place the header is built.
@immutable
final class CursorAccountCredentials extends Equatable {
  const CursorAccountCredentials({
    required this.accountId,
    required this.userId,
    required this.token,
    required this.expiresAtMs,
  });

  final String accountId;
  final String userId;
  final String token;
  final int expiresAtMs;

  String get cookie => 'WorkosCursorSessionToken=$userId%3A%3A$token';

  @override
  List<Object?> get props => [accountId, userId, token, expiresAtMs];

  @override
  String toString() => 'CursorAccountCredentials($accountId)';
}
```

- [ ] **Step 5: Create the range model**

`client/lib/models/cursor_usage_range.dart`:

```dart
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

enum CursorUsagePreset {
  billingCycle,
  today,
  sevenDays,
  thirtyDays,
  lastMonth,
}

sealed class CursorUsageRange extends Equatable {
  const CursorUsageRange();
}

final class CursorUsagePresetRange extends CursorUsageRange {
  const CursorUsagePresetRange(this.preset);

  final CursorUsagePreset preset;

  @override
  List<Object?> get props => [preset];
}

final class CursorUsageCustomRange extends CursorUsageRange {
  const CursorUsageCustomRange({required this.startMs, required this.endMs});

  final int startMs;
  final int endMs;

  @override
  List<Object?> get props => [startMs, endMs];
}

@immutable
final class CursorUsageWindow extends Equatable {
  const CursorUsageWindow({required this.startMs, required this.endMs});

  final int startMs;
  final int endMs;

  bool contains(int ms) => ms >= startMs && ms <= endMs;

  int get durationMs => endMs - startMs;

  @override
  List<Object?> get props => [startMs, endMs];
}
```

- [ ] **Step 6: Create the report model**

`client/lib/models/cursor_usage_report.dart`:

```dart
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

@immutable
final class CursorUsageModelTotals extends Equatable {
  const CursorUsageModelTotals({
    this.inputTokens = 0,
    this.outputTokens = 0,
    this.cacheReadTokens = 0,
    this.cacheWriteTokens = 0,
    this.totalCents = 0,
    this.chargedCents = 0,
    this.eventCount = 0,
  });

  final int inputTokens;
  final int outputTokens;
  final int cacheReadTokens;
  final int cacheWriteTokens;
  final double totalCents;
  final double chargedCents;
  final int eventCount;

  int get totalTokens =>
      inputTokens + outputTokens + cacheReadTokens + cacheWriteTokens;

  CursorUsageModelTotals merge(CursorUsageModelTotals other) =>
      CursorUsageModelTotals(
        inputTokens: inputTokens + other.inputTokens,
        outputTokens: outputTokens + other.outputTokens,
        cacheReadTokens: cacheReadTokens + other.cacheReadTokens,
        cacheWriteTokens: cacheWriteTokens + other.cacheWriteTokens,
        totalCents: totalCents + other.totalCents,
        chargedCents: chargedCents + other.chargedCents,
        eventCount: eventCount + other.eventCount,
      );

  Map<String, Object?> toJson() => {
    'inputTokens': inputTokens,
    'outputTokens': outputTokens,
    'cacheReadTokens': cacheReadTokens,
    'cacheWriteTokens': cacheWriteTokens,
    'totalCents': totalCents,
    'chargedCents': chargedCents,
    'eventCount': eventCount,
  };

  factory CursorUsageModelTotals.fromJson(Map<String, Object?> json) =>
      CursorUsageModelTotals(
        inputTokens: (json['inputTokens'] as num?)?.toInt() ?? 0,
        outputTokens: (json['outputTokens'] as num?)?.toInt() ?? 0,
        cacheReadTokens: (json['cacheReadTokens'] as num?)?.toInt() ?? 0,
        cacheWriteTokens: (json['cacheWriteTokens'] as num?)?.toInt() ?? 0,
        totalCents: (json['totalCents'] as num?)?.toDouble() ?? 0,
        chargedCents: (json['chargedCents'] as num?)?.toDouble() ?? 0,
        eventCount: (json['eventCount'] as num?)?.toInt() ?? 0,
      );

  @override
  List<Object?> get props => [
    inputTokens,
    outputTokens,
    cacheReadTokens,
    cacheWriteTokens,
    totalCents,
    chargedCents,
    eventCount,
  ];
}

@immutable
final class CursorUsageDay extends Equatable {
  const CursorUsageDay({
    required this.dayMs,
    this.inputTokens = 0,
    this.outputTokens = 0,
    this.cacheReadTokens = 0,
    this.cacheWriteTokens = 0,
    this.totalCents = 0,
    this.chargedCents = 0,
    this.eventCount = 0,
    this.models = const {},
  });

  final int dayMs;
  final int inputTokens;
  final int outputTokens;
  final int cacheReadTokens;
  final int cacheWriteTokens;
  final double totalCents;
  final double chargedCents;
  final int eventCount;
  final Map<String, CursorUsageModelTotals> models;

  int get totalTokens =>
      inputTokens + outputTokens + cacheReadTokens + cacheWriteTokens;

  CursorUsageDay merge(CursorUsageDay other) {
    final mergedModels = <String, CursorUsageModelTotals>{...models};
    for (final entry in other.models.entries) {
      mergedModels[entry.key] =
          (mergedModels[entry.key] ?? const CursorUsageModelTotals()).merge(
            entry.value,
          );
    }
    return CursorUsageDay(
      dayMs: dayMs,
      inputTokens: inputTokens + other.inputTokens,
      outputTokens: outputTokens + other.outputTokens,
      cacheReadTokens: cacheReadTokens + other.cacheReadTokens,
      cacheWriteTokens: cacheWriteTokens + other.cacheWriteTokens,
      totalCents: totalCents + other.totalCents,
      chargedCents: chargedCents + other.chargedCents,
      eventCount: eventCount + other.eventCount,
      models: mergedModels,
    );
  }

  Map<String, Object?> toJson() => {
    'dayMs': dayMs,
    'inputTokens': inputTokens,
    'outputTokens': outputTokens,
    'cacheReadTokens': cacheReadTokens,
    'cacheWriteTokens': cacheWriteTokens,
    'totalCents': totalCents,
    'chargedCents': chargedCents,
    'eventCount': eventCount,
    'models': {
      for (final entry in models.entries) entry.key: entry.value.toJson(),
    },
  };

  factory CursorUsageDay.fromJson(Map<String, Object?> json) {
    final rawModels = json['models'];
    final models = <String, CursorUsageModelTotals>{};
    if (rawModels is Map) {
      for (final entry in rawModels.entries) {
        final value = entry.value;
        if (value is Map) {
          models[entry.key.toString()] = CursorUsageModelTotals.fromJson(
            Map<String, Object?>.from(value),
          );
        }
      }
    }
    return CursorUsageDay(
      dayMs: (json['dayMs'] as num?)?.toInt() ?? 0,
      inputTokens: (json['inputTokens'] as num?)?.toInt() ?? 0,
      outputTokens: (json['outputTokens'] as num?)?.toInt() ?? 0,
      cacheReadTokens: (json['cacheReadTokens'] as num?)?.toInt() ?? 0,
      cacheWriteTokens: (json['cacheWriteTokens'] as num?)?.toInt() ?? 0,
      totalCents: (json['totalCents'] as num?)?.toDouble() ?? 0,
      chargedCents: (json['chargedCents'] as num?)?.toDouble() ?? 0,
      eventCount: (json['eventCount'] as num?)?.toInt() ?? 0,
      models: models,
    );
  }

  @override
  List<Object?> get props => [
    dayMs,
    inputTokens,
    outputTokens,
    cacheReadTokens,
    cacheWriteTokens,
    totalCents,
    chargedCents,
    eventCount,
    models,
  ];
}

/// One raw usage event, trimmed down to what the UI renders.
@immutable
final class CursorUsageEvent extends Equatable {
  const CursorUsageEvent({
    required this.eventId,
    required this.timestampMs,
    required this.model,
    required this.kind,
    this.owningUser = '',
    this.inputTokens = 0,
    this.outputTokens = 0,
    this.cacheReadTokens = 0,
    this.cacheWriteTokens = 0,
    this.totalCents = 0,
    this.chargedCents = 0,
  });

  final String eventId;
  final int timestampMs;
  final String model;
  final String kind;

  /// Cursor's per-event account id. Used to detect a swapped session cookie.
  final String owningUser;
  final int inputTokens;
  final int outputTokens;
  final int cacheReadTokens;
  final int cacheWriteTokens;
  final double totalCents;
  final double chargedCents;

  int get totalTokens =>
      inputTokens + outputTokens + cacheReadTokens + cacheWriteTokens;

  CursorUsageModelTotals get totals => CursorUsageModelTotals(
    inputTokens: inputTokens,
    outputTokens: outputTokens,
    cacheReadTokens: cacheReadTokens,
    cacheWriteTokens: cacheWriteTokens,
    totalCents: totalCents,
    chargedCents: chargedCents,
    eventCount: 1,
  );

  Map<String, Object?> toJson() => {
    'eventId': eventId,
    'timestampMs': timestampMs,
    'model': model,
    'kind': kind,
    'owningUser': owningUser,
    'inputTokens': inputTokens,
    'outputTokens': outputTokens,
    'cacheReadTokens': cacheReadTokens,
    'cacheWriteTokens': cacheWriteTokens,
    'totalCents': totalCents,
    'chargedCents': chargedCents,
  };

  factory CursorUsageEvent.fromJson(Map<String, Object?> json) =>
      CursorUsageEvent(
        eventId: json['eventId']?.toString() ?? '',
        timestampMs: (json['timestampMs'] as num?)?.toInt() ?? 0,
        model: json['model']?.toString() ?? '',
        kind: json['kind']?.toString() ?? '',
        owningUser: json['owningUser']?.toString() ?? '',
        inputTokens: (json['inputTokens'] as num?)?.toInt() ?? 0,
        outputTokens: (json['outputTokens'] as num?)?.toInt() ?? 0,
        cacheReadTokens: (json['cacheReadTokens'] as num?)?.toInt() ?? 0,
        cacheWriteTokens: (json['cacheWriteTokens'] as num?)?.toInt() ?? 0,
        totalCents: (json['totalCents'] as num?)?.toDouble() ?? 0,
        chargedCents: (json['chargedCents'] as num?)?.toDouble() ?? 0,
      );

  @override
  List<Object?> get props => [
    eventId,
    timestampMs,
    model,
    kind,
    owningUser,
    inputTokens,
    outputTokens,
    cacheReadTokens,
    cacheWriteTokens,
    totalCents,
    chargedCents,
  ];
}

/// On-disk cache for one account.
@immutable
final class CursorUsageCache extends Equatable {
  const CursorUsageCache({
    required this.accountId,
    this.owningUser,
    this.coverage = const [],
    this.days = const [],
    this.events = const [],
  });

  final String accountId;
  final String? owningUser;
  final List<CursorUsageWindow> coverage;
  final List<CursorUsageDay> days;
  final List<CursorUsageEvent> events;

  bool isCovered(int startMs, int endMs) =>
      coverage.any((window) => window.startMs <= startMs && window.endMs >= endMs);

  CursorUsageCache copyWith({
    String? owningUser,
    List<CursorUsageWindow>? coverage,
    List<CursorUsageDay>? days,
    List<CursorUsageEvent>? events,
  }) => CursorUsageCache(
    accountId: accountId,
    owningUser: owningUser ?? this.owningUser,
    coverage: coverage ?? this.coverage,
    days: days ?? this.days,
    events: events ?? this.events,
  );

  Map<String, Object?> toJson() => {
    'version': 1,
    'accountId': accountId,
    'owningUser': owningUser,
    'coverage': [
      for (final window in coverage)
        {'startMs': window.startMs, 'endMs': window.endMs},
    ],
    'days': [for (final day in days) day.toJson()],
    'events': [for (final event in events) event.toJson()],
  };

  factory CursorUsageCache.fromJson(Map<String, Object?> json) {
    final rawCoverage = json['coverage'];
    final coverage = <CursorUsageWindow>[];
    if (rawCoverage is List) {
      for (final item in rawCoverage) {
        if (item is Map) {
          coverage.add(
            CursorUsageWindow(
              startMs: (item['startMs'] as num?)?.toInt() ?? 0,
              endMs: (item['endMs'] as num?)?.toInt() ?? 0,
            ),
          );
        }
      }
    }
    final rawDays = json['days'];
    final days = <CursorUsageDay>[];
    if (rawDays is List) {
      for (final item in rawDays) {
        if (item is Map) {
          days.add(CursorUsageDay.fromJson(Map<String, Object?>.from(item)));
        }
      }
    }
    final rawEvents = json['events'];
    final events = <CursorUsageEvent>[];
    if (rawEvents is List) {
      for (final item in rawEvents) {
        if (item is Map) {
          events.add(CursorUsageEvent.fromJson(Map<String, Object?>.from(item)));
        }
      }
    }
    return CursorUsageCache(
      accountId: json['accountId']?.toString() ?? '',
      owningUser: json['owningUser']?.toString(),
      coverage: coverage,
      days: days,
      events: events,
    );
  }

  @override
  List<Object?> get props => [accountId, owningUser, coverage, days, events];
}

/// What the page renders for one account and one range.
@immutable
final class CursorUsageReport extends Equatable {
  const CursorUsageReport({
    required this.accountId,
    required this.startMs,
    required this.endMs,
    this.inputTokens = 0,
    this.outputTokens = 0,
    this.cacheReadTokens = 0,
    this.cacheWriteTokens = 0,
    this.totalCents = 0,
    this.chargedCents = 0,
    this.eventCount = 0,
    this.days = const [],
    this.models = const {},
    this.events = const [],
    this.summaryOnly = false,
  });

  final String accountId;
  final int startMs;
  final int endMs;
  final int inputTokens;
  final int outputTokens;
  final int cacheReadTokens;
  final int cacheWriteTokens;
  final double totalCents;
  final double chargedCents;
  final int eventCount;
  final List<CursorUsageDay> days;
  final Map<String, CursorUsageModelTotals> models;
  final List<CursorUsageEvent> events;

  /// True when the range reaches further back than the raw-event retention
  /// window, so [events] is empty but [days] still has the numbers.
  final bool summaryOnly;

  int get totalTokens =>
      inputTokens + outputTokens + cacheReadTokens + cacheWriteTokens;

  @override
  List<Object?> get props => [
    accountId,
    startMs,
    endMs,
    inputTokens,
    outputTokens,
    cacheReadTokens,
    cacheWriteTokens,
    totalCents,
    chargedCents,
    eventCount,
    days,
    models,
    events,
    summaryOnly,
  ];
}
```

- [ ] **Step 7: Run the model test**

Run: `cd client && dart run tool/run_tests.dart test/models/cursor_usage_models_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 8: Analyze**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: no new issues.

- [ ] **Step 9: Commit**

```bash
git add client/lib/models/cursor_usage_account.dart client/lib/models/cursor_usage_range.dart client/lib/models/cursor_usage_report.dart client/lib/services/storage/app_paths.dart client/test/models/cursor_usage_models_test.dart
git commit -m "feat(cursor-usage): add account, range, and report models"
```

---

### Task 2: Range resolution and gap arithmetic

**Files:**
- Create: `client/lib/services/cursor_usage/cursor_usage_range_math.dart`
- Test: `client/test/services/cursor_usage/cursor_usage_range_math_test.dart`

**Interfaces:**
- Consumes: `CursorUsageRange`, `CursorUsagePreset`, `CursorUsagePresetRange`, `CursorUsageCustomRange`, `CursorUsageWindow`.
- Produces:
  - `int cursorUsageDayStartMs(int ms)`
  - `int cursorUsageDayEndMs(int ms)`
  - `CursorUsageWindow cursorUsageAlignWindow(CursorUsageWindow window)`
  - `CursorUsageWindow cursorUsageResolveRange({required CursorUsageRange range, required int nowMs, CursorUsageWindow? billingCycle})`
  - `List<CursorUsageWindow> cursorUsageMergeWindows(Iterable<CursorUsageWindow> windows)`
  - `List<CursorUsageWindow> cursorUsageMissingWindows({required Iterable<CursorUsageWindow> covered, required CursorUsageWindow requested})`

- [ ] **Step 1: Write the failing test**

Create `client/test/services/cursor_usage/cursor_usage_range_math_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/cursor_usage_range.dart';
import 'package:teampilot/services/cursor_usage/cursor_usage_range_math.dart';

int ms(int year, int month, int day, [int hour = 0]) =>
    DateTime(year, month, day, hour).millisecondsSinceEpoch;

void main() {
  group('cursorUsageResolveRange', () {
    test('billing cycle wins when supplied', () {
      final cycle = CursorUsageWindow(
        startMs: ms(2026, 10, 6),
        endMs: cursorUsageDayEndMs(ms(2026, 11, 6)),
      );
      final resolved = cursorUsageResolveRange(
        range: const CursorUsagePresetRange(CursorUsagePreset.billingCycle),
        nowMs: ms(2026, 10, 28, 12),
        billingCycle: cycle,
      );
      expect(resolved, cycle);
    });

    test('billing cycle falls back to the calendar month', () {
      final resolved = cursorUsageResolveRange(
        range: const CursorUsagePresetRange(CursorUsagePreset.billingCycle),
        nowMs: ms(2026, 10, 28, 12),
      );
      expect(resolved.startMs, ms(2026, 10, 1));
      expect(resolved.endMs, cursorUsageDayEndMs(ms(2026, 10, 28)));
    });

    test('sevenDays covers today plus six previous days', () {
      final resolved = cursorUsageResolveRange(
        range: const CursorUsagePresetRange(CursorUsagePreset.sevenDays),
        nowMs: ms(2026, 10, 28, 12),
      );
      expect(resolved.startMs, ms(2026, 10, 22));
      expect(resolved.endMs, cursorUsageDayEndMs(ms(2026, 10, 28)));
    });

    test('lastMonth covers the whole previous calendar month', () {
      final resolved = cursorUsageResolveRange(
        range: const CursorUsagePresetRange(CursorUsagePreset.lastMonth),
        nowMs: ms(2026, 3, 15, 9),
      );
      expect(resolved.startMs, ms(2026, 2, 1));
      expect(resolved.endMs, cursorUsageDayEndMs(ms(2026, 2, 28)));
    });

    test('custom range snaps to whole local days', () {
      final resolved = cursorUsageResolveRange(
        range: CursorUsageCustomRange(
          startMs: ms(2026, 9, 29, 13),
          endMs: ms(2026, 10, 28, 4),
        ),
        nowMs: ms(2026, 10, 28, 12),
      );
      expect(resolved.startMs, ms(2026, 9, 29));
      expect(resolved.endMs, cursorUsageDayEndMs(ms(2026, 10, 28)));
    });
  });

  group('cursorUsageMissingWindows', () {
    test('returns the whole request when nothing is covered', () {
      final requested = CursorUsageWindow(
        startMs: ms(2026, 10, 1),
        endMs: cursorUsageDayEndMs(ms(2026, 10, 3)),
      );
      expect(
        cursorUsageMissingWindows(covered: const [], requested: requested),
        [requested],
      );
    });

    test('returns nothing when the request is fully covered', () {
      final day = CursorUsageWindow(
        startMs: ms(2026, 10, 1),
        endMs: cursorUsageDayEndMs(ms(2026, 10, 2)),
      );
      expect(
        cursorUsageMissingWindows(covered: [day], requested: day),
        isEmpty,
      );
    });

    test('splits a request around a covered middle', () {
      final requested = CursorUsageWindow(
        startMs: ms(2026, 10, 1),
        endMs: cursorUsageDayEndMs(ms(2026, 10, 5)),
      );
      final covered = CursorUsageWindow(
        startMs: ms(2026, 10, 3),
        endMs: cursorUsageDayEndMs(ms(2026, 10, 3)),
      );
      final gaps = cursorUsageMissingWindows(
        covered: [covered],
        requested: requested,
      );
      expect(gaps.length, 2);
      expect(gaps[0].startMs, ms(2026, 10, 1));
      expect(gaps[0].endMs, cursorUsageDayEndMs(ms(2026, 10, 2)));
      expect(gaps[1].startMs, ms(2026, 10, 4));
      expect(gaps[1].endMs, cursorUsageDayEndMs(ms(2026, 10, 5)));
    });

    test('treats adjacent windows as contiguous', () {
      final merged = cursorUsageMergeWindows([
        CursorUsageWindow(
          startMs: ms(2026, 10, 1),
          endMs: cursorUsageDayEndMs(ms(2026, 10, 2)),
        ),
        CursorUsageWindow(
          startMs: ms(2026, 10, 3),
          endMs: cursorUsageDayEndMs(ms(2026, 10, 4)),
        ),
      ]);
      expect(merged.length, 1);
      expect(merged.single.startMs, ms(2026, 10, 1));
      expect(merged.single.endMs, cursorUsageDayEndMs(ms(2026, 10, 4)));
    });
  });
}
```

- [ ] **Step 2: Run the test to confirm it fails**

Run: `cd client && dart run tool/run_tests.dart test/services/cursor_usage/cursor_usage_range_math_test.dart`
Expected: FAIL — unresolved import.

- [ ] **Step 3: Implement the math**

`client/lib/services/cursor_usage/cursor_usage_range_math.dart`:

```dart
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
        local.day,
      ).add(const Duration(days: 1)).millisecondsSinceEpoch -
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
          return _windowFor(
            todayStart,
            DateTime(now.year, now.month, 1),
          );
        case CursorUsagePreset.today:
          return _windowFor(todayStart, todayStart);
        case CursorUsagePreset.sevenDays:
          return _windowFor(
            todayStart,
            todayStart.subtract(const Duration(days: 6)),
          );
        case CursorUsagePreset.thirtyDays:
          return _windowFor(
            todayStart,
            todayStart.subtract(const Duration(days: 29)),
          );
        case CursorUsagePreset.lastMonth:
          final firstOfThisMonth = DateTime(now.year, now.month, 1);
          final firstOfLastMonth = DateTime(now.year, now.month - 1, 1);
          final lastOfLastMonth = firstOfThisMonth.subtract(
            const Duration(days: 1),
          );
          return CursorUsageWindow(
            startMs: firstOfLastMonth.millisecondsSinceEpoch,
            endMs: _endOfDay(lastOfLastMonth),
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
    dayStart.add(const Duration(days: 1)).millisecondsSinceEpoch - 1;

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
```

- [ ] **Step 4: Run the tests**

Run: `cd client && dart run tool/run_tests.dart test/services/cursor_usage/cursor_usage_range_math_test.dart`
Expected: PASS (9 tests).

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/cursor_usage/cursor_usage_range_math.dart client/test/services/cursor_usage/cursor_usage_range_math_test.dart
git commit -m "feat(cursor-usage): add range resolution and coverage gap math"
```

---

### Task 3: Event API client

**Files:**
- Create: `client/lib/services/cursor_usage/cursor_usage_api_client.dart`
- Test: `client/test/services/cursor_usage/cursor_usage_api_client_test.dart`

**Interfaces:**
- Consumes: `CursorAccountCredentials`, `CursorUsageEvent`, `CursorUsageWindow`.
- Produces:
  - `enum CursorUsageApiError { login, rateLimited, network, http, invalidResponse }`
  - `class CursorUsageApiException implements Exception` with `code` and `message`
  - `final class CursorUsagePage` with `events`, `totalCount`
  - `abstract interface class CursorUsageApi` with `fetchPage` + `fetchBillingCycle` (the seam the coordinator and tests depend on)
  - `final class CursorUsageApiClient implements CursorUsageApi`, constructed as `CursorUsageApiClient({http.Client? client, Uri? eventsUri, Uri? summaryUri, Duration timeout})`
  - `Future<CursorUsagePage> fetchPage({required CursorAccountCredentials credentials, required int startMs, required int endMs, required int page, int pageSize = 500, int teamId = 0})`
  - `Future<CursorUsageWindow?> fetchBillingCycle({required CursorAccountCredentials credentials})`
  - `void close()`

- [ ] **Step 1: Write the failing test**

Create `client/test/services/cursor_usage/cursor_usage_api_client_test.dart`:

```dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:teampilot/models/cursor_usage_account.dart';
import 'package:teampilot/services/cursor_usage/cursor_usage_api_client.dart';

const _credentials = CursorAccountCredentials(
  accountId: 'abc',
  userId: 'user_01ABC',
  token: 'eyJ.payload.sig',
  expiresAtMs: 2000000000000,
);

http.Response _json(Object body, {int status = 200}) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

void main() {
  test('parses events and passes the session cookie and body', () async {
    late http.Request captured;
    final client = CursorUsageApiClient(
      client: MockClient((request) async {
        captured = request;
        return _json({
          'totalUsageEventsCount': 1,
          'usageEventsDisplay': [
            {
              'timestamp': '1793106557868',
              'model': 'cursor-grok-4.6-high',
              'kind': 'USAGE_EVENT_KIND_INCLUDED_IN_PRO',
              'tokenUsage': {
                'inputTokens': 9598,
                'outputTokens': 4642,
                'cacheReadTokens': 335488,
                'cacheWriteTokens': 7,
                'totalCents': 21.5,
              },
              'owningUser': '380653899',
              'chargedCents': 0.0,
              'usageEventId': 'evt-1',
            },
          ],
        });
      }),
    );

    final page = await client.fetchPage(
      credentials: _credentials,
      startMs: 1000,
      endMs: 2000,
      page: 2,
    );

    expect(captured.headers['Cookie'], contains('WorkosCursorSessionToken='));
    expect(captured.headers['Origin'], 'https://cursor.com');
    final body = jsonDecode(captured.body) as Map<String, Object?>;
    expect(body['teamId'], 0);
    expect(body['startDate'], '1000');
    expect(body['endDate'], '2000');
    expect(body['page'], 2);
    expect(body['pageSize'], 500);

    expect(page.totalCount, 1);
    final event = page.events.single;
    expect(event.eventId, 'evt-1');
    expect(event.timestampMs, 1793106557868);
    expect(event.cacheWriteTokens, 7);
    expect(event.totalCents, 21.5);
  });

  test('maps 401 to login', () async {
    final client = CursorUsageApiClient(
      client: MockClient((_) async => _json(const {}, status: 401)),
    );
    await expectLater(
      client.fetchPage(
        credentials: _credentials,
        startMs: 0,
        endMs: 1,
        page: 1,
      ),
      throwsA(
        isA<CursorUsageApiException>().having(
          (error) => error.code,
          'code',
          CursorUsageApiError.login,
        ),
      ),
    );
  });

  test('maps 429 to rateLimited', () async {
    final client = CursorUsageApiClient(
      client: MockClient((_) async => _json(const {}, status: 429)),
    );
    await expectLater(
      client.fetchPage(
        credentials: _credentials,
        startMs: 0,
        endMs: 1,
        page: 1,
      ),
      throwsA(
        isA<CursorUsageApiException>().having(
          (error) => error.code,
          'code',
          CursorUsageApiError.rateLimited,
        ),
      ),
    );
  });

  test('a non-json body is invalidResponse', () async {
    final client = CursorUsageApiClient(
      client: MockClient((_) async => http.Response('<html></html>', 200)),
    );
    await expectLater(
      client.fetchPage(
        credentials: _credentials,
        startMs: 0,
        endMs: 1,
        page: 1,
      ),
      throwsA(
        isA<CursorUsageApiException>().having(
          (error) => error.code,
          'code',
          CursorUsageApiError.invalidResponse,
        ),
      ),
    );
  });

  test('fetchBillingCycle parses the ISO bounds', () async {
    final client = CursorUsageApiClient(
      client: MockClient(
        (_) async => _json({
          'billingCycleStart': '2026-10-06T07:05:16.000Z',
          'billingCycleEnd': '2026-11-06T07:05:16.000Z',
        }),
      ),
    );
    final cycle = await client.fetchBillingCycle(credentials: _credentials);
    expect(cycle, isNotNull);
    expect(cycle!.startMs, DateTime.utc(2026, 10, 6, 7, 5, 16).millisecondsSinceEpoch);
    expect(cycle.endMs, DateTime.utc(2026, 11, 6, 7, 5, 16).millisecondsSinceEpoch);
  });

  test('fetchBillingCycle returns null when the fields are absent', () async {
    final client = CursorUsageApiClient(
      client: MockClient((_) async => _json(const {'membershipType': 'pro'})),
    );
    expect(await client.fetchBillingCycle(credentials: _credentials), isNull);
  });
}
```

- [ ] **Step 2: Run the test to confirm it fails**

Run: `cd client && dart run tool/run_tests.dart test/services/cursor_usage/cursor_usage_api_client_test.dart`
Expected: FAIL — unresolved import.

- [ ] **Step 3: Implement the client**

`client/lib/services/cursor_usage/cursor_usage_api_client.dart`:

```dart
import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../models/cursor_usage_account.dart';
import '../../models/cursor_usage_range.dart';
import '../../models/cursor_usage_report.dart';

enum CursorUsageApiError {
  login,
  rateLimited,
  network,
  http,
  invalidResponse,
}

class CursorUsageApiException implements Exception {
  const CursorUsageApiException(this.code, this.message);

  final CursorUsageApiError code;
  final String message;

  @override
  String toString() => message;
}

final class CursorUsagePage {
  const CursorUsagePage({required this.events, required this.totalCount});

  final List<CursorUsageEvent> events;
  final int totalCount;
}

/// The transport seam. Fakes in tests implement this, never the concrete
/// client — `CursorUsageApiClient` is `final` on purpose.
abstract interface class CursorUsageApi {
  Future<CursorUsagePage> fetchPage({
    required CursorAccountCredentials credentials,
    required int startMs,
    required int endMs,
    required int page,
    int pageSize,
    int teamId,
  });

  Future<CursorUsageWindow?> fetchBillingCycle({
    required CursorAccountCredentials credentials,
  });
}

final class CursorUsageApiClient implements CursorUsageApi {
  CursorUsageApiClient({
    http.Client? client,
    Uri? eventsUri,
    Uri? summaryUri,
    Duration timeout = const Duration(seconds: 30),
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null,
       _eventsUri =
           eventsUri ??
           Uri.parse(
             'https://cursor.com/api/dashboard/get-filtered-usage-events',
           ),
       _summaryUri =
           summaryUri ?? Uri.parse('https://cursor.com/api/usage-summary'),
       _timeout = timeout;

  final http.Client _client;
  final bool _ownsClient;
  final Uri _eventsUri;
  final Uri _summaryUri;
  final Duration _timeout;

  Map<String, String> get _baseHeaders => {
    'Accept': '*/*',
    'Content-Type': 'application/json',
    'Origin': 'https://cursor.com',
    'Referer': 'https://cursor.com/dashboard/usage',
    'User-Agent': 'TeamPilot',
  };

  Future<CursorUsagePage> fetchPage({
    required CursorAccountCredentials credentials,
    required int startMs,
    required int endMs,
    required int page,
    int pageSize = 500,
    int teamId = 0,
  }) async {
    final response = await _post(
      _eventsUri,
      credentials,
      {
        'teamId': teamId,
        'startDate': '$startMs',
        'endDate': '$endMs',
        'page': page,
        'pageSize': pageSize,
      },
    );
    final json = _decodeObject(response);
    final rawEvents = json['usageEventsDisplay'];
    final events = <CursorUsageEvent>[];
    if (rawEvents is List) {
      for (final item in rawEvents) {
        if (item is! Map) continue;
        final event = _parseEvent(Map<String, Object?>.from(item));
        if (event != null) events.add(event);
      }
    }
    return CursorUsagePage(
      events: events,
      totalCount: (json['totalUsageEventsCount'] as num?)?.toInt() ?? events.length,
    );
  }

  Future<CursorUsageWindow?> fetchBillingCycle({
    required CursorAccountCredentials credentials,
  }) async {
    final http.Response response;
    try {
      response = await _client
          .get(_summaryUri, headers: {..._baseHeaders, 'Cookie': credentials.cookie})
          .timeout(_timeout);
    } on TimeoutException {
      throw const CursorUsageApiException(
        CursorUsageApiError.network,
        'Cursor usage summary timed out',
      );
    } on http.ClientException catch (error) {
      throw CursorUsageApiException(
        CursorUsageApiError.network,
        'Cursor usage summary failed: $error',
      );
    }
    _throwForStatus(response);
    final json = _decodeObject(response);
    final start = DateTime.tryParse(      json['billingCycleStart']?.toString() ?? '',
    );
    final end = DateTime.tryParse(json['billingCycleEnd']?.toString() ?? '');
    if (start == null || end == null) return null;
    return CursorUsageWindow(
      startMs: start.millisecondsSinceEpoch,
      endMs: end.millisecondsSinceEpoch,
    );
  }

  void close() {
    if (_ownsClient) _client.close();
  }

  Future<http.Response> _post(
    Uri uri,
    CursorAccountCredentials credentials,
    Map<String, Object?> body,
  ) async {
    final http.Response response;
    try {
      response = await _client
          .post(
            uri,
            headers: {..._baseHeaders, 'Cookie': credentials.cookie},
            body: jsonEncode(body),
          )
          .timeout(_timeout);
    } on TimeoutException {
      throw const CursorUsageApiException(
        CursorUsageApiError.network,
        'Cursor usage request timed out',
      );
    } on http.ClientException catch (error) {
      throw CursorUsageApiException(
        CursorUsageApiError.network,
        'Cursor usage request failed: $error',
      );
    }
    _throwForStatus(response);
    return response;
  }

  void _throwForStatus(http.Response response) {
    final status = response.statusCode;
    if (status == 401 || status == 403) {
      throw const CursorUsageApiException(
        CursorUsageApiError.login,
        'Cursor rejected the session',
      );
    }
    if (status == 429) {
      throw const CursorUsageApiException(
        CursorUsageApiError.rateLimited,
        'Cursor rate-limited the usage request',
      );
    }
    if (status < 200 || status >= 300) {
      throw CursorUsageApiException(
        CursorUsageApiError.http,
        'Cursor returned HTTP $status',
      );
    }
  }

  Map<String, Object?> _decodeObject(http.Response response) {
    final body = response.body.trimLeft();
    if (body.isEmpty) return const {};
    if (body.startsWith('<')) {
      throw const CursorUsageApiException(
        CursorUsageApiError.login,
        'Cursor returned a login page',
      );
    }
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map) {
        throw const CursorUsageApiException(
          CursorUsageApiError.invalidResponse,
          'Cursor returned an unexpected payload',
        );
      }
      return Map<String, Object?>.from(decoded);
    } on CursorUsageApiException {
      rethrow;
    } on FormatException {
      throw const CursorUsageApiException(
        CursorUsageApiError.invalidResponse,
        'Cursor returned malformed json',
      );
    }
  }

  CursorUsageEvent? _parseEvent(Map<String, Object?> json) {
    final eventId = json['usageEventId']?.toString() ?? '';
    if (eventId.isEmpty) return null;
    final timestampRaw = json['timestamp']?.toString() ?? '';
    final timestamp = int.tryParse(timestampRaw);
    if (timestamp == null) return null;
    final usage = json['tokenUsage'];
    final tokens = usage is Map ? Map<String, Object?>.from(usage) : const {};
    return CursorUsageEvent(
      eventId: eventId,
      timestampMs: timestamp,
      model: json['model']?.toString() ?? '',
      kind: json['kind']?.toString() ?? '',
      owningUser: json['owningUser']?.toString() ?? '',
      inputTokens: (tokens['inputTokens'] as num?)?.toInt() ?? 0,
      outputTokens: (tokens['outputTokens'] as num?)?.toInt() ?? 0,
      cacheReadTokens: (tokens['cacheReadTokens'] as num?)?.toInt() ?? 0,
      cacheWriteTokens: (tokens['cacheWriteTokens'] as num?)?.toInt() ?? 0,
      totalCents: (tokens['totalCents'] as num?)?.toDouble() ?? 0,
      chargedCents: (json['chargedCents'] as num?)?.toDouble() ?? 0,
    );
  }
}
```

- [ ] **Step 4: Run the tests**

Run: `cd client && dart run tool/run_tests.dart test/services/cursor_usage/cursor_usage_api_client_test.dart`
Expected: PASS (6 tests).

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/cursor_usage/cursor_usage_api_client.dart client/test/services/cursor_usage/cursor_usage_api_client_test.dart
git commit -m "feat(cursor-usage): add filtered usage events client"
```

---

### Task 4: Credential parsing and secure storage

**Files:**
- Create: `client/lib/services/cursor_usage/cursor_account_credential_store.dart`
- Test: `client/test/services/cursor_usage/cursor_account_credential_store_test.dart`

**Interfaces:**
- Consumes: `SecureKeyValueStore` from `repositories/ssh_credential_store.dart`, `CursorAccountCredentials`, `CursorAccountSource` is not needed here.
- Produces:
  - `CursorAccountCredentials? parseCursorSessionToken(String raw, {int? nowMs})`
  - `String cursorAccountIdFor(String sub)`
  - `CursorAccountCredentialStore({required SecureKeyValueStore store, DateTime Function()? now})` with `read(accountId)`, `write(credentials)`, `delete(accountId)`

- [ ] **Step 1: Write the failing test**

Create `client/test/services/cursor_usage/cursor_account_credential_store_test.dart`:

```dart
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/repositories/ssh_credential_store.dart';
import 'package:teampilot/services/cursor_usage/cursor_account_credential_store.dart';

class _MemoryStore implements SecureKeyValueStore {
  final values = <String, String>{};

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

String _jwt({required int exp, String sub = 'auth0|user_01ABC'}) {
  final header = base64Url.encode(utf8.encode('{"alg":"HS256"}')).replaceAll('=', '');
  final payload = base64Url
      .encode(utf8.encode(jsonEncode({'sub': sub, 'exp': exp})))
      .replaceAll('=', '');
  return '$header.$payload.signature';
}

void main() {
  final exp = DateTime.utc(2027, 1, 1).millisecondsSinceEpoch ~/ 1000;
  final nowMs = DateTime.utc(2026, 10, 28).millisecondsSinceEpoch;

  group('parseCursorSessionToken', () {
    test('accepts the bare JWT', () {
      final token = _jwt(exp: exp);
      final parsed = parseCursorSessionToken(token, nowMs: nowMs);
      expect(parsed, isNotNull);
      expect(parsed!.userId, 'user_01ABC');
      expect(parsed.token, token);
      expect(parsed.accountId, cursorAccountIdFor('auth0|user_01ABC'));
      expect(parsed.expiresAtMs, exp * 1000);
    });

    test('accepts a full cookie header', () {
      final token = _jwt(exp: exp);
      final parsed = parseCursorSessionToken(
        'WorkosCursorSessionToken=user_01ABC%3A%3A$token',
        nowMs: nowMs,
      );
      expect(parsed?.token, token);
      expect(parsed?.userId, 'user_01ABC');
    });

    test('accepts the userId::jwt form', () {
      final token = _jwt(exp: exp);
      final parsed = parseCursorSessionToken('user_01ABC::$token', nowMs: nowMs);
      expect(parsed?.userId, 'user_01ABC');
    });

    test('rejects a token inside the expiry guard', () {
      final token = _jwt(exp: nowMs ~/ 1000 + 10);
      expect(parseCursorSessionToken(token, nowMs: nowMs), isNull);
    });

    test('rejects garbage', () {
      expect(parseCursorSessionToken('not-a-token', nowMs: nowMs), isNull);
      expect(parseCursorSessionToken('a.b.c', nowMs: nowMs), isNull);
    });
  });

  test('accountId is the first 16 chars of sha256(sub)', () {
    final expected = sha256
        .convert(utf8.encode('auth0|user_01ABC'))
        .toString()
        .substring(0, 16);
    expect(cursorAccountIdFor('auth0|user_01ABC'), expected);
  });

  test('store round-trips credentials under a namespaced key', () async {
    final backend = _MemoryStore();
    final store = CursorAccountCredentialStore(store: backend);
    const credentials = CursorAccountCredentials(
      accountId: 'abc',
      userId: 'user_01ABC',
      token: 'eyJ.payload.sig',
      expiresAtMs: 2000000000000,
    );
    await store.write(credentials);
    expect(backend.values.keys.single, 'teampilot.cursor_usage.v1.abc.token');
    expect(await store.read('abc'), credentials);
    await store.delete('abc');
    expect(await store.read('abc'), isNull);
  });
}
```

- [ ] **Step 2: Run the test to confirm it fails**

Run: `cd client && dart run tool/run_tests.dart test/services/cursor_usage/cursor_account_credential_store_test.dart`
Expected: FAIL — unresolved import.

- [ ] **Step 3: Implement parsing and storage**

`client/lib/services/cursor_usage/cursor_account_credential_store.dart`:

```dart
import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../models/cursor_usage_account.dart';
import '../../repositories/ssh_credential_store.dart';

/// Cursor hashes the JWT `sub` into a stable account id; the same formula is
/// used by `CursorUsageAuthResolver`, so discovered and manual entries merge.
String cursorAccountIdFor(String sub) =>
    sha256.convert(utf8.encode(sub)).toString().substring(0, 16);

/// Parses any of the three paste shapes:
/// `WorkosCursorSessionToken=user_x%3A%3A<jwt>`, `user_x::<jwt>`, or `<jwt>`.
/// Returns null when the token is malformed or already inside the 60s guard.
CursorAccountCredentials? parseCursorSessionToken(String raw, {int? nowMs}) {
  var value = raw.trim();
  if (value.isEmpty) return null;
  const prefix = 'WorkosCursorSessionToken=';
  if (value.toLowerCase().startsWith(prefix.toLowerCase())) {
    value = value.substring(prefix.length);
  }
  try {
    value = Uri.decodeComponent(value);
  } on ArgumentError {
    // Not percent-encoded; keep the raw value.
  }
  final separator = value.indexOf('::');
  var token = separator >= 0 ? value.substring(separator + 2) : value;
  token = token.trim();
  final parts = token.split('.');
  if (parts.length != 3) return null;
  final Map<String, Object?> claims;
  try {
    final decoded = jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
    );
    if (decoded is! Map) return null;
    claims = Map<String, Object?>.from(decoded);
  } on Object {
    return null;
  }
  final exp = (claims['exp'] as num?)?.toInt();
  final sub = claims['sub']?.toString().trim() ?? '';
  if (exp == null || sub.isEmpty) return null;
  final clock = nowMs ?? DateTime.now().millisecondsSinceEpoch;
  if (exp * 1000 <= clock + 60000) return null;
  final userId = sub.split('|').where((part) => part.isNotEmpty).last;
  if (!RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(userId)) return null;
  return CursorAccountCredentials(
    accountId: cursorAccountIdFor(sub),
    userId: userId,
    token: token,
    expiresAtMs: exp * 1000,
  );
}

final class CursorAccountCredentialStore {
  CursorAccountCredentialStore({required SecureKeyValueStore store})
    : _store = store;

  static const namespace = 'teampilot.cursor_usage.v1';

  final SecureKeyValueStore _store;

  String _key(String accountId) => '$namespace.$accountId.token';

  Future<CursorAccountCredentials?> read(String accountId) async {
    final raw = await _store.read(_key(accountId));
    if (raw == null || raw.isEmpty) return null;
    return parseCursorSessionToken(raw);
  }

  Future<void> write(CursorAccountCredentials credentials) =>
      _store.write(_key(credentials.accountId), credentials.token);

  Future<void> delete(String accountId) => _store.delete(_key(accountId));
}
```

- [ ] **Step 4: Run the tests**

Run: `cd client && dart run tool/run_tests.dart test/services/cursor_usage/cursor_account_credential_store_test.dart`
Expected: PASS (7 tests).

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/cursor_usage/cursor_account_credential_store.dart client/test/services/cursor_usage/cursor_account_credential_store_test.dart
git commit -m "feat(cursor-usage): parse session tokens and store them securely"
```

---

### Task 5: Account registry

**Files:**
- Create: `client/lib/services/cursor_usage/cursor_account_registry.dart`
- Test: `client/test/services/cursor_usage/cursor_account_registry_test.dart`

**Interfaces:**
- Consumes: `CursorAccountCredentialStore`, `CursorUsageAccount`, `CursorAccountCredentials`, `cursorAccountIdFor`, `CursorUsageAuth` (from `cursor_usage_auth_resolver.dart`), `Filesystem`, `ManagedProviderStorageLock`.
- Produces:
  - `abstract interface class CursorAccountDirectory` — `list()`, `credentialFor(accountId)`, `upsertManual(credentials, {label, teamId})`, `remove(accountId)`, `update(accountId, {label, enabled, teamId, owningUser})`
  - `final class CursorAccountRegistry implements CursorAccountDirectory`, constructed as `CursorAccountRegistry({required Filesystem fs, required String accountsPath, required CursorAccountCredentialStore credentials, required Future<List<CursorUsageAuth>> Function() resolveAuths, DateTime Function()? now})`

Taking `resolveAuths` as a function instead of the `CursorUsageAuthResolver` object keeps the registry testable: the resolver is a `final class` and cannot be implemented by a test fake.

- [ ] **Step 1: Write the failing test**

Create `client/test/services/cursor_usage/cursor_account_registry_test.dart`:

```dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/cursor_usage_account.dart';
import 'package:teampilot/repositories/ssh_credential_store.dart';
import 'package:teampilot/services/cursor_usage/cursor_account_credential_store.dart';
import 'package:teampilot/services/cursor_usage/cursor_account_registry.dart';
import 'package:teampilot/services/io/filesystem.dart';
import 'package:teampilot/services/cli/cursor/provider/cursor_usage_auth_resolver.dart';

import '../../support/in_memory_filesystem.dart';

class _MemoryStore implements SecureKeyValueStore {
  final values = <String, String>{};

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

void main() {
  late Filesystem fs;
  late _MemoryStore backend;
  late List<CursorUsageAuth> discovered;
  late CursorAccountRegistry registry;
  final nowMs = DateTime.utc(2026, 10, 28).millisecondsSinceEpoch;

  CursorUsageAuth auth(String sub, {required int modifiedAtMs}) =>
      CursorUsageAuth(
        token: 'token-$sub',
        account: cursorAccountIdFor(sub),
        userId: 'user_01ABC',
        expiresAtMs: DateTime.utc(2027, 1, 1).millisecondsSinceEpoch,
        modifiedAtMs: modifiedAtMs,
      );

  setUp(() async {
    fs = inMemoryFilesystem();
    backend = _MemoryStore();
    discovered = [auth('auth0|a', modifiedAtMs: 1)];
    registry = CursorAccountRegistry(
      fs: fs,
      accountsPath: '/root/cursor_usage/accounts.json',
      credentials: CursorAccountCredentialStore(store: backend),
      resolveAuths: () async => discovered,
      now: () => DateTime.fromMillisecondsSinceEpoch(nowMs),
    );
  });

  test('lists discovered accounts with hasCredential true', () async {
    final accounts = await registry.list();
    expect(accounts.length, 1);
    expect(accounts.single.accountId, cursorAccountIdFor('auth0|a'));
    expect(accounts.single.source, CursorAccountSource.discovered);
    expect(accounts.single.hasCredential, isTrue);
  });

  test('manual entry adds a second account and is readable back', () async {
    final credentials = CursorAccountCredentials(
      accountId: cursorAccountIdFor('auth0|b'),
      userId: 'user_02DEF',
      token: 'manual-token',
      expiresAtMs: DateTime.utc(2027, 2, 1).millisecondsSinceEpoch,
    );
    await registry.upsertManual(credentials, label: 'Work');

    final accounts = await registry.list();
    expect(accounts.length, 2);
    final manual = accounts.firstWhere(
      (account) => account.accountId == credentials.accountId,
    );
    expect(manual.source, CursorAccountSource.manual);
    expect(manual.label, 'Work');
    expect(manual.hasCredential, isTrue);
    expect(await registry.credentialFor(credentials.accountId), credentials);
  });

  test('a manual label wins over the discovered default', () async {
    final discoveredId = cursorAccountIdFor('auth0|a');
    await registry.update(discoveredId, label: 'Team account');
    final accounts = await registry.list();
    expect(accounts.single.label, 'Team account');
  });

  test('removing a manual account also drops its secret', () async {
    final credentials = CursorAccountCredentials(
      accountId: cursorAccountIdFor('auth0|b'),
      userId: 'user_02DEF',
      token: 'manual-token',
      expiresAtMs: DateTime.utc(2027, 2, 1).millisecondsSinceEpoch,
    );
    await registry.upsertManual(credentials);
    await registry.remove(credentials.accountId);
    expect(await registry.credentialFor(credentials.accountId), isNull);
    expect(backend.values.keys, isEmpty);
  });

  test('corrupted accounts.json degrades to discovered only', () async {
    await fs.ensureDir('/root/cursor_usage');
    await fs.writeString('/root/cursor_usage/accounts.json', '{not json');
    final accounts = await registry.list();
    expect(accounts.length, 1);
    expect(accounts.single.source, CursorAccountSource.discovered);
  });
}
```

- [ ] **Step 2: Add `resolveAll()` to the existing resolver**

In `client/lib/services/cli/cursor/provider/cursor_usage_auth_resolver.dart`, replace `resolve()` (lines 63-77) with:

```dart
  /// Every unexpired token, newest first, one entry per account.
  Future<List<CursorUsageAuth>> resolveAll() async {
    final candidates = await _candidatePaths();
    final byAccount = <String, CursorUsageAuth>{};
    for (final path in candidates) {
      final auth = await _readAuth(path);
      if (auth == null) continue;
      final existing = byAccount[auth.account];
      if (existing == null ||
          auth.modifiedAtMs > existing.modifiedAtMs ||
          (auth.modifiedAtMs == existing.modifiedAtMs &&
              auth.expiresAtMs > existing.expiresAtMs)) {
        byAccount[auth.account] = auth;
      }
    }
    final values = byAccount.values.toList()
      ..sort((a, b) => b.modifiedAtMs.compareTo(a.modifiedAtMs));
    return values;
  }

  /// The newest unexpired token, kept for the session usage page.
  Future<CursorUsageAuth?> resolve() async {
    final all = await resolveAll();
    return all.isEmpty ? null : all.first;
  }
```

- [ ] **Step 3: Implement the registry**

`client/lib/services/cursor_usage/cursor_account_registry.dart`:

```dart
import 'dart:convert';

import '../../models/cursor_usage_account.dart';
import '../../repositories/managed_provider_storage_lock.dart';
import '../cli/cursor/provider/cursor_usage_auth_resolver.dart';
import '../io/filesystem.dart';
import 'cursor_account_credential_store.dart';

/// Merges auto-discovered Cursor logins with manually pasted ones.
///
/// Precedence on the same [CursorUsageAccount.accountId]: the manual entry owns
/// `label`, `enabled`, `teamId`, and `owningUser`; the token always comes from
/// whichever credential is still valid, so a stale pasted token cannot shadow a
/// fresh provider-home token.
abstract interface class CursorAccountDirectory {
  Future<List<CursorUsageAccount>> list();

  Future<CursorAccountCredentials?> credentialFor(String accountId);

  Future<void> upsertManual(
    CursorAccountCredentials credentials, {
    String? label,
    int teamId,
  });

  Future<void> remove(String accountId);

  Future<void> update(
    String accountId, {
    String? label,
    bool? enabled,
    int? teamId,
    String? owningUser,
  });
}

final class CursorAccountRegistry implements CursorAccountDirectory {
  CursorAccountRegistry({
    required Filesystem fs,
    required String accountsPath,
    required CursorAccountCredentialStore credentials,
    required Future<List<CursorUsageAuth>> Function() resolveAuths,
    DateTime Function()? now,
  }) : _fs = fs,
       _path = accountsPath,
       _credentials = credentials,
       _resolveAuths = resolveAuths,
       _now = now ?? DateTime.now;

  final Filesystem _fs;
  final String _path;
  final CursorAccountCredentialStore _credentials;
  final Future<List<CursorUsageAuth>> Function() _resolveAuths;
  final DateTime Function() _now;

  @override
  Future<List<CursorUsageAccount>> list() async {
    final stored = await _readAccounts();
    final discoveredAccounts = await _resolveAuths();
    final out = <String, CursorUsageAccount>{};

    for (final auth in discoveredAccounts) {
      final override = stored[auth.account];
      out[auth.account] = CursorUsageAccount(
        accountId: auth.account,
        userId: auth.userId,
        label: override?.label ?? _defaultLabel(auth.account),
        source: override?.source ?? CursorAccountSource.discovered,
        enabled: override?.enabled ?? true,
        expiresAtMs: auth.expiresAtMs,
        owningUser: override?.owningUser,
        teamId: override?.teamId ?? 0,
        hasCredential: true,
      );
    }

    for (final entry in stored.entries) {
      if (out.containsKey(entry.key)) continue;
      final manual = await _credentials.read(entry.key);
      out[entry.key] = CursorUsageAccount(
        accountId: entry.key,
        userId: manual?.userId ?? entry.value.userId,
        label: entry.value.label.isEmpty
            ? _defaultLabel(entry.key)
            : entry.value.label,
        source: CursorAccountSource.manual,
        enabled: entry.value.enabled,
        expiresAtMs: manual?.expiresAtMs,
        owningUser: entry.value.owningUser,
        teamId: entry.value.teamId,
        hasCredential: manual != null,
      );
    }

    return out.values.toList()
      ..sort((a, b) {
        if (a.enabled != b.enabled) return a.enabled ? -1 : 1;
        return a.label.toLowerCase().compareTo(b.label.toLowerCase());
      });
  }

  @override
  Future<CursorAccountCredentials?> credentialFor(String accountId) async {
    final stored = await _credentials.read(accountId);
    final discoveredAccounts = await _resolveAuths();
    final match = discoveredAccounts
        .where((auth) => auth.account == accountId)
        .firstOrNull;
    final discoveredExpires = match?.expiresAtMs ?? 0;
    if (stored != null && stored.expiresAtMs >= discoveredExpires) {
      return stored;
    }
    if (match == null) return stored;
    return CursorAccountCredentials(
      accountId: match.account,
      userId: match.userId,
      token: match.token,
      expiresAtMs: match.expiresAtMs,
    );
  }

  Future<void> upsertManual(
    CursorAccountCredentials credentials, {
    String? label,
    int teamId = 0,
  }) async {
    await _credentials.write(credentials);
    await _mutate((accounts) {
      final previous = accounts[credentials.accountId];
      accounts[credentials.accountId] = CursorUsageAccount(
        accountId: credentials.accountId,
        userId: credentials.userId,
        label: label ?? previous?.label ?? _defaultLabel(credentials.accountId),
        source: CursorAccountSource.manual,
        enabled: true,
        expiresAtMs: credentials.expiresAtMs,
        owningUser: previous?.owningUser,
        teamId: teamId,
        hasCredential: true,
      );
    });
  }

  Future<void> update(
    String accountId, {
    String? label,
    bool? enabled,
    int? teamId,
    String? owningUser,
  }) async {
    await _mutate((accounts) {
      final previous =
          accounts[accountId] ??
          CursorUsageAccount(
            accountId: accountId,
            userId: '',
            label: _defaultLabel(accountId),
            source: CursorAccountSource.discovered,
          );
      accounts[accountId] = previous.copyWith(
        label: label,
        enabled: enabled,
        teamId: teamId,
        owningUser: owningUser,
      );
    });
  }

  Future<void> remove(String accountId) async {
    await _credentials.delete(accountId);
    await _mutate((accounts) => accounts.remove(accountId));
  }

  Future<Map<String, CursorUsageAccount>> _readAccounts() async {
    final raw = await _fs.readString(_path);
    if (raw == null || raw.trim().isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      final accounts = decoded['accounts'];
      if (accounts is! Map) return {};
      final out = <String, CursorUsageAccount>{};
      for (final entry in accounts.entries) {
        final value = entry.value;
        if (value is! Map) continue;
        final account = CursorUsageAccount.fromJson(
          Map<String, Object?>.from(value),
        );
        if (account.accountId.isEmpty) continue;
        out[account.accountId] = account;
      }
      return out;
    } on Object {
      return {};
    }
  }

  Future<void> _mutate(
    void Function(Map<String, CursorUsageAccount> accounts) change,
  ) async {
    await ManagedProviderStorageLock.run(_path, () async {
      final accounts = await _readAccounts();
      change(accounts);
      await _fs.ensureDir(_fs.pathContext.dirname(_path));
      await _fs.atomicWrite(
        _path,
        const JsonEncoder.withIndent('  ').convert({
          'version': 1,
          'accounts': {
            for (final entry in accounts.entries)
              entry.key: entry.value.toJson(),
          },
        }),
      );
    });
  }

  static String _defaultLabel(String accountId) =>
      'Cursor · ${accountId.length >= 6 ? accountId.substring(0, 6) : accountId}';
}
```

Note: `firstOrNull` needs `import 'package:collection/collection.dart';`
(`collection: ^1.19.0` is already a direct dependency in `client/pubspec.yaml`).

- [ ] **Step 4: Run the tests**

Run: `cd client && dart run tool/run_tests.dart test/services/cursor_usage/cursor_account_registry_test.dart`
Expected: PASS (5 tests).

- [ ] **Step 5: Confirm the existing resolver tests still pass**

Run: `cd client && dart run tool/run_tests.dart test/services/cli/cursor/provider/cursor_usage_auth_resolver_test.dart`
Expected: PASS — `resolve()` keeps its old behaviour (`resolveAll().first`) so the session usage page is unaffected.

- [ ] **Step 6: Commit**

```bash
git add client/lib/services/cursor_usage/cursor_account_registry.dart client/lib/services/cli/cursor/provider/cursor_usage_auth_resolver.dart client/test/services/cursor_usage/cursor_account_registry_test.dart
git commit -m "feat(cursor-usage): merge discovered and manual accounts"
```

---

### Task 6: Cache store and aggregation

**Files:**
- Create: `client/lib/services/cursor_usage/cursor_usage_cache.dart`
- Create: `client/lib/services/cursor_usage/cursor_usage_cache_store.dart`
- Test: `client/test/services/cursor_usage/cursor_usage_cache_test.dart`

**Interfaces:**
- Consumes: `CursorUsageCache`, `CursorUsageDay`, `CursorUsageEvent`, `CursorUsageReport`, `CursorUsageWindow`, `cursorUsageDayStartMs`, `cursorUsageMergeWindows`.
- Produces:
  - `CursorUsageCache applyCursorUsageEvents(CursorUsageCache cache, List<CursorUsageEvent> incoming, {required CursorUsageWindow window, String? owningUser})`
  - `CursorUsageCache trimCursorUsageCache(CursorUsageCache cache, {required int nowMs, int retentionDays = 90})`
  - `CursorUsageReport buildCursorUsageReport(CursorUsageCache cache, {required CursorUsageWindow window})`
  - `CursorUsageCacheStore({required Filesystem fs, required String Function(String accountId) pathFor})` with `Int64`-free `load`, `save`

- [ ] **Step 1: Write the failing test**

Create `client/test/services/cursor_usage/cursor_usage_cache_test.dart`:

```dart
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
    final window = CursorUsageWindow(
      startMs: ms(1),
      endMs: ms(2) + 86399999,
    );
    var cache = applyCursorUsageEvents(
      CursorUsageCache(accountId: 'a'),
      [event('e1', 1), event('e2', 2)],
      window: window,
    );
    cache = applyCursorUsageEvents(
      cache,
      [event('e1', 1), event('e3', 2)],
      window: window,
    );

    final report = buildCursorUsageReport(cache, window: window);
    expect(report.eventCount, 2);
    expect(report.inputTokens, 20);
    expect(cache.events.map((e) => e.eventId), containsAll(['e1', 'e3']));
    expect(cache.events.any((e) => e.eventId == 'e2'), isFalse);
  });

  test('aggregates days and models for the requested window', () {
    final window = CursorUsageWindow(
      startMs: ms(1),
      endMs: ms(3) + 86399999,
    );
    final cache = applyCursorUsageEvents(
      CursorUsageCache(accountId: 'a'),
      [
        event('e1', 1, input: 10),
        event('e2', 1, model: 'composer-2.5-fast', input: 4),
        event('e3', 3, input: 6),
      ],
      window: window,
    );

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
      coverage: [
        CursorUsageWindow(startMs: ms(1), endMs: ms(2) + 86399999),
      ],
      days: [
        CursorUsageDay(dayMs: ms(1), inputTokens: 99, eventCount: 1),
      ],
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
    final cache = applyCursorUsageEvents(
      CursorUsageCache(accountId: 'a'),
      [event('old', 1), event('new', 19)],
      window: CursorUsageWindow(startMs: ms(1), endMs: ms(19) + 86399999),
    );
    final trimmed = trimCursorUsageCache(cache, nowMs: nowMs, retentionDays: 5);
    expect(trimmed.events.map((e) => e.eventId), ['new']);
    expect(trimmed.days.length, 2);
  });
}
```

- [ ] **Step 2: Run the test to confirm it fails**

Run: `cd client && dart run tool/run_tests.dart test/services/cursor_usage/cursor_usage_cache_test.dart`
Expected: FAIL — unresolved import.

- [ ] **Step 3: Implement aggregation**

`client/lib/services/cursor_usage/cursor_usage_cache.dart`:

```dart
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
    final previous =
        daysByStart[dayMs] ?? CursorUsageDay(dayMs: dayMs);
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
    DateTime.fromMillisecondsSinceEpoch(nowMs)
        .subtract(Duration(days: retentionDays))
        .millisecondsSinceEpoch,
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
      models[entry.key] =
          (models[entry.key] ?? const CursorUsageModelTotals()).merge(
            entry.value,
          );
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
```

- [ ] **Step 4: Implement the store**

`client/lib/services/cursor_usage/cursor_usage_cache_store.dart`:

```dart
import 'dart:convert';

import '../../models/cursor_usage_report.dart';
import '../io/filesystem.dart';

final class CursorUsageCacheStore {
  CursorUsageCacheStore({
    required Filesystem fs,
    required String Function(String accountId) pathFor,
  }) : _fs = fs,
       _pathFor = pathFor;

  final Filesystem _fs;
  final String Function(String accountId) _pathFor;

  Future<CursorUsageCache> load(String accountId) async {
    final raw = await _fs.readString(_pathFor(accountId));
    if (raw == null || raw.trim().isEmpty) {
      return CursorUsageCache(accountId: accountId);
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return CursorUsageCache(accountId: accountId);
      return CursorUsageCache.fromJson(Map<String, Object?>.from(decoded));
    } on Object {
      return CursorUsageCache(accountId: accountId);
    }
  }

  Future<void> save(CursorUsageCache cache) async {
    final path = _pathFor(cache.accountId);
    await _fs.ensureDir(_fs.pathContext.dirname(path));
    await _fs.atomicWrite(
      path,
      const JsonEncoder.withIndent('  ').convert(cache.toJson()),
    );
  }
}
```

- [ ] **Step 5: Run the tests**

Run: `cd client && dart run tool/run_tests.dart test/services/cursor_usage/cursor_usage_cache_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 6: Commit**

```bash
git add client/lib/services/cursor_usage/cursor_usage_cache.dart client/lib/services/cursor_usage/cursor_usage_cache_store.dart client/test/services/cursor_usage/cursor_usage_cache_test.dart
git commit -m "feat(cursor-usage): cache day aggregates and trim raw events"
```

---

### Task 7: Sync coordinator

**Files:**
- Create: `client/lib/services/cursor_usage/cursor_usage_coordinator.dart`
- Test: `client/test/services/cursor_usage/cursor_usage_coordinator_test.dart`

**Interfaces:**
- Consumes: `CursorUsageApi` (the interface, not the concrete client), `CursorUsageApiException`, `CursorUsageApiError`, `CursorAccountDirectory`, `CursorUsageCacheStore`, all cache math, all range math.
- Produces:
  - `enum CursorUsageFailure { login, rateLimited, network, http, invalidResponse, accountMismatch, rangeTooLarge, noCredential }`
  - `class CursorUsageException implements Exception` with `failure`
  - `CursorUsageCoordinator({required CursorAccountDirectory registry, required CursorUsageCacheStore cacheStore, required CursorUsageApi api, DateTime Function()? now, int maxPages = 40, int pageSize = 500})`
  - `Future<CursorUsageReport> load({required String accountId, required CursorUsageRange range, CursorUsageWindow? billingCycle, bool forceRefresh = false})`
  - `Future<CursorUsageWindow?> billingCycleFor(String accountId)`
  - `Future<void> bindOwningUser(String accountId, String owningUser)`

- [ ] **Step 1: Write the failing test**

Create `client/test/services/cursor_usage/cursor_usage_coordinator_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/cursor_usage_account.dart';
import 'package:teampilot/models/cursor_usage_range.dart';
import 'package:teampilot/models/cursor_usage_report.dart';
import 'package:teampilot/services/cursor_usage/cursor_usage_api_client.dart';
import 'package:teampilot/services/cursor_usage/cursor_usage_cache_store.dart';
import 'package:teampilot/services/cursor_usage/cursor_usage_coordinator.dart';
import 'package:teampilot/services/io/filesystem.dart';

import '../../support/in_memory_filesystem.dart';

int ms(int day) => DateTime(2026, 10, day).millisecondsSinceEpoch;

CursorUsageEvent event(String id, int day, {String owner = '111'}) =>
    CursorUsageEvent(
      eventId: id,
      timestampMs: ms(day) + 1000,
      model: 'cursor-grok-4.6-high',
      kind: 'USAGE_EVENT_KIND_INCLUDED_IN_PRO',
      owningUser: owner,
      inputTokens: 10,
      totalCents: 1,
    );

class _FakeApi implements CursorUsageApi {
  _FakeApi({this.pages = const [], this.pageSizeTotal = 0});

  final List<CursorUsagePage> pages;
  final int pageSizeTotal;
  final calls = <(int, int, int)>[];
  Object? throwOnFetch;

  @override
  Future<CursorUsagePage> fetchPage({
    required CursorAccountCredentials credentials,
    required int startMs,
    required int endMs,
    required int page,
    int pageSize = 500,
    int teamId = 0,
  }) async {
    calls.add((startMs, endMs, page));
    final error = throwOnFetch;
    if (error != null) throw error;
    final index = page - 1;
    if (index >= pages.length) {
      return const CursorUsagePage(events: [], totalCount: 0);
    }
    return pages[index];
  }

  @override
  Future<CursorUsageWindow?> fetchBillingCycle({
    required CursorAccountCredentials credentials,
  }) async => null;
}

class _FakeRegistry implements CursorAccountDirectory {
  _FakeRegistry(this.credential, {this.owningUser});

  final CursorAccountCredentials? credential;
  String? owningUser;
  int bindCalls = 0;

  @override
  Future<CursorAccountCredentials?> credentialFor(String accountId) async =>
      credential;

  @override
  Future<void> update(
    String accountId, {
    String? label,
    bool? enabled,
    int? teamId,
    String? owningUser,
  }) async {
    bindCalls++;
    this.owningUser = owningUser ?? this.owningUser;
  }

  @override
  Future<List<CursorUsageAccount>> list() async => const [];

  @override
  Future<void> upsertManual(
    CursorAccountCredentials credentials, {
    String? label,
    int teamId = 0,
  }) async {}

  @override
  Future<void> remove(String accountId) async {}
}

const _credentials = CursorAccountCredentials(
  accountId: 'acct',
  userId: 'user_01ABC',
  token: 'tok',
  expiresAtMs: 2000000000000,
);

void main() {
  late Filesystem fs;
  late CursorUsageCacheStore cacheStore;

  setUp(() {
    fs = inMemoryFilesystem();
    cacheStore = CursorUsageCacheStore(
      fs: fs,
      pathFor: (accountId) => '/root/cursor_usage/cache/$accountId.json',
    );
  });

  CursorUsageCoordinator coordinator({
    required CursorUsageApiClient api,
    required _FakeRegistry registry,
  }) => CursorUsageCoordinator(
    registry: registry,
    cacheStore: cacheStore,
    api: api,
    now: () => DateTime.fromMillisecondsSinceEpoch(ms(28) + 3600000),
  );

  test('fetches every page until the total is reached', () async {
    final api = _FakeApi(
      pages: [
        CursorUsagePage(events: [event('e1', 28)], totalCount: 2),
        CursorUsagePage(events: [event('e2', 28)], totalCount: 2),
      ],
    );
    final report = await coordinator(
      api: api,
      registry: _FakeRegistry(_credentials),
    ).load(
      accountId: 'acct',
      range: CursorUsageCustomRange(startMs: ms(28), endMs: ms(28)),
    );

    expect(api.calls.length, 2);
    expect(api.calls[1].$3, 2);
    expect(report.eventCount, 2);
  });

  test('a second load inside the covered range makes no request', () async {
    final api = _FakeApi(
      pages: [
        CursorUsagePage(events: [event('e1', 28)], totalCount: 1),
      ],
    );
    final coord = coordinator(api: api, registry: _FakeRegistry(_credentials));
    final range = CursorUsageCustomRange(startMs: ms(28), endMs: ms(28));
    await coord.load(accountId: 'acct', range: range);
    await coord.load(accountId: 'acct', range: range);
    expect(api.calls.length, 1);
  });

  test('stops at the page cap and reports rangeTooLarge', () async {
    final api = _FakeApi(
      pages: [
        CursorUsagePage(events: [event('e1', 28)], totalCount: 99999),
      ],
    );
    await expectLater(
      coordinator(api: api, registry: _FakeRegistry(_credentials)).load(
        accountId: 'acct',
        range: CursorUsageCustomRange(startMs: ms(1), endMs: ms(28)),
      ),
      throwsA(
        isA<CursorUsageException>().having(
          (error) => error.failure,
          'failure',
          CursorUsageFailure.rangeTooLarge,
        ),
      ),
    );
    expect(api.calls.length, 40);
  });

  test('binds owningUser on first fetch and rejects a later swap', () async {
    final registry = _FakeRegistry(_credentials, owningUser: '111');
    final api = _FakeApi(
      pages: [
        CursorUsagePage(events: [event('e1', 28)], totalCount: 1),
      ],
    );
    final coord = coordinator(api: api, registry: registry);
    await coord.load(
      accountId: 'acct',
      range: CursorUsageCustomRange(startMs: ms(28), endMs: ms(28)),
    );
    expect(registry.bindCalls, 1);
    expect(registry.owningUser, '111');

    final swapped = _FakeApi(
      pages: [
        CursorUsagePage(events: [event('e2', 27, owner: '222')], totalCount: 1),
      ],
    );
    await expectLater(
      coordinator(api: swapped, registry: registry).load(
        accountId: 'acct',
        range: CursorUsageCustomRange(startMs: ms(27), endMs: ms(27)),
      ),
      throwsA(
        isA<CursorUsageException>().having(
          (error) => error.failure,
          'failure',
          CursorUsageFailure.accountMismatch,
        ),
      ),
    );
  });

  test('missing credential fails before any request', () async {
    final api = _FakeApi();
    await expectLater(
      coordinator(api: api, registry: _FakeRegistry(null)).load(
        accountId: 'acct',
        range: CursorUsageCustomRange(startMs: ms(28), endMs: ms(28)),
      ),
      throwsA(
        isA<CursorUsageException>().having(
          (error) => error.failure,
          'failure',
          CursorUsageFailure.noCredential,
        ),
      ),
    );
    expect(api.calls, isEmpty);
  });
}
```

- [ ] **Step 2: Run the test to confirm it fails**

Run: `cd client && dart run tool/run_tests.dart test/services/cursor_usage/cursor_usage_coordinator_test.dart`
Expected: FAIL — unresolved import.

- [ ] **Step 3: Implement the coordinator**

`client/lib/services/cursor_usage/cursor_usage_coordinator.dart`:

```dart
import 'dart:async';

import '../../models/cursor_usage_range.dart';
import '../../models/cursor_usage_report.dart';
import 'cursor_account_credential_store.dart';
import 'cursor_usage_api_client.dart';
import 'cursor_usage_cache.dart';
import 'cursor_usage_cache_store.dart';
import 'cursor_usage_range_math.dart';

enum CursorUsageFailure {
  login,
  rateLimited,
  network,
  http,
  invalidResponse,
  accountMismatch,
  rangeTooLarge,
  noCredential,
}

class CursorUsageException implements Exception {
  const CursorUsageException(this.failure, this.message);

  final CursorUsageFailure failure;
  final String message;

  @override
  String toString() => message;
}

final class CursorUsageCoordinator {
  CursorUsageCoordinator({
    required CursorAccountDirectory registry,
    required CursorUsageCacheStore cacheStore,
    required CursorUsageApi api,
    DateTime Function()? now,
    int maxPages = 40,
    int pageSize = 500,
  }) : _registry = registry,
       _cacheStore = cacheStore,
       _api = api,
       _now = now ?? DateTime.now,
       _maxPages = maxPages,
       _pageSize = pageSize;

  final CursorAccountDirectory _registry;
  final CursorUsageCacheStore _cacheStore;
  final CursorUsageApi _api;
  final DateTime Function() _now;
  final int _maxPages;
  final int _pageSize;

  Future<CursorUsageWindow?> billingCycleFor(String accountId) async {
    final credentials = await _registry.credentialFor(accountId);
    if (credentials == null) return null;
    try {
      return await _api.fetchBillingCycle(credentials: credentials);
    } on CursorUsageApiException {
      return null;
    }
  }

  Future<CursorUsageReport> load({
    required String accountId,
    required CursorUsageRange range,
    CursorUsageWindow? billingCycle,
    bool forceRefresh = false,
  }) async {
    final credentials = await _registry.credentialFor(accountId);
    if (credentials == null) {
      throw const CursorUsageException(
        CursorUsageFailure.noCredential,
        'No live Cursor credential for this account',
      );
    }
    final nowMs = _now().millisecondsSinceEpoch;
    final resolved = cursorUsageResolveRange(
      range: range,
      nowMs: nowMs,
      billingCycle: billingCycle,
    );
    final window = CursorUsageWindow(
      startMs: resolved.startMs,
      endMs: resolved.endMs > nowMs ? nowMs : resolved.endMs,
    );

    var cache = await _cacheStore.load(accountId);
    final gaps = forceRefresh
        ? [cursorUsageAlignWindow(window)]
        : cursorUsageMissingWindows(covered: cache.coverage, requested: window);

    for (final gap in gaps) {
      cache = await _fillGap(
        cache: cache,
        credentials: credentials,
        gap: gap,
        teamId: 0,
      );
    }
    return buildCursorUsageReport(cache, window: window);
  }

  Future<CursorUsageCache> _fillGap({
    required CursorUsageCache cache,
    required CursorAccountCredentials credentials,
    required CursorUsageWindow gap,
    required int teamId,
  }) async {
    final collected = <CursorUsageEvent>[];
    var boundOwningUser = cache.owningUser;
    var page = 1;
    var total = 1;
    while (page <= _maxPages) {
      final CursorUsagePage response;
      try {
        response = await _api.fetchPage(
          credentials: credentials,
          startMs: gap.startMs,
          endMs: gap.endMs,
          page: page,
          pageSize: _pageSize,
          teamId: teamId,
        );
      } on CursorUsageApiException catch (error) {
        throw CursorUsageException(_failureFor(error.code), error.message);
      }
      total = response.totalCount;
      collected.addAll(response.events);
      if (response.events.isEmpty) break;
      if (collected.length >= total) break;
      page++;
    }
    if (collected.length < total && page > _maxPages) {
      throw const CursorUsageException(
        CursorUsageFailure.rangeTooLarge,
        'The selected range has too many events',
      );
    }
    if (teamId == 0) {
      final owners = collected
          .map(_owningUserOf)
          .whereType<String>()
          .toSet();
      if (owners.length > 1) {
        throw const CursorUsageException(
          CursorUsageFailure.accountMismatch,
          'Cursor returned events for more than one user',
        );
      }
      final owner = owners.firstOrNull;
      if (owner != null) {
        if (boundOwningUser != null && boundOwningUser != owner) {
          throw const CursorUsageException(
            CursorUsageFailure.accountMismatch,
            'The Cursor session belongs to a different account',
          );
        }
        boundOwningUser = owner;
        await _registry.update(cache.accountId, owningUser: owner);
      }
    }

    final next = applyCursorUsageEvents(
      cache,
      collected,
      window: gap,
      owningUser: boundOwningUser,
    );
    final trimmed = trimCursorUsageCache(
      next,
      nowMs: _now().millisecondsSinceEpoch,
    );
    await _cacheStore.save(trimmed);
    return trimmed;
  }

  static String? _owningUserOf(CursorUsageEvent event) =>
      event.owningUser.isEmpty ? null : event.owningUser;

  static CursorUsageFailure _failureFor(CursorUsageApiError code) =>
      switch (code) {
        CursorUsageApiError.login => CursorUsageFailure.login,
        CursorUsageApiError.rateLimited => CursorUsageFailure.rateLimited,
        CursorUsageApiError.network => CursorUsageFailure.network,
        CursorUsageApiError.http => CursorUsageFailure.http,
        CursorUsageApiError.invalidResponse => CursorUsageFailure.invalidResponse,
      };
}
```

Imports for this file: `cursor_account_registry.dart` (for
`CursorAccountDirectory`), `cursor_account_credential_store.dart`,
`cursor_usage_api_client.dart`, `cursor_usage_cache.dart`,
`cursor_usage_cache_store.dart`, `cursor_usage_range_math.dart`, plus the two
model files.

- [ ] **Step 4: Run the tests**

Run: `cd client && dart run tool/run_tests.dart test/services/cursor_usage/`
Expected: PASS for all four files in the directory.

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/cursor_usage/cursor_usage_coordinator.dart client/lib/services/cursor_usage/cursor_usage_api_client.dart client/lib/models/cursor_usage_report.dart client/test/services/cursor_usage/cursor_usage_coordinator_test.dart
git commit -m "feat(cursor-usage): fill coverage gaps and guard account binding"
```

---

### Task 8: Cubit

**Files:**
- Create: `client/lib/cubits/cursor_usage_cubit.dart`
- Create: `client/lib/services/cursor_usage/cursor_usage_range_preference.dart`
- Test: `client/test/cubits/cursor_usage_cubit_test.dart`

**Interfaces:**
- Consumes: `CursorUsageCoordinator`, `CursorUsageAccount`, `CursorUsageRange`, `CursorUsageReport`, `CursorUsageFailure`, `CursorUsageException`.
- Produces:
  - `CursorUsageStatus { initial, loading, ready, error }`
  - `final class CursorUsageState` with `status, accounts, selectedAccountId, range, reports (Map<String, CursorUsageReport>), failures (Map<String, CursorUsageFailure>), syncing (Set<String>), billingCycles (Map<String, CursorUsageWindow>), selectedReport, isSyncing`
  - `CursorUsageCubit({required Future<List<CursorUsageAccount>> Function() loadAccounts, required Future<void> Function(String accountId) refreshAccount, required Future<CursorUsageWindow?> Function(String accountId) billingCycleFor, required Future<CursorUsageReport> Function({required String accountId, required CursorUsageRange range, CursorUsageWindow? billingCycle, bool forceRefresh}) loadReport, required Future<void> Function(CursorUsageRange range) saveRange, required Future<bool> Function(String rawToken, String? label) addAccount, required Future<void> Function(String accountId) removeAccount, required CursorUsageRange initialRange})`
  - `ensureLoaded()`, `selectAccount(String?)`, `setRange(CursorUsageRange)`, `refresh({bool force})`, `addAccount(String rawToken, {String? label}) -> Future<bool>`, `removeAccount(String accountId)`

- [ ] **Step 1: Write the failing test**

Create `client/test/cubits/cursor_usage_cubit_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/cursor_usage_cubit.dart';
import 'package:teampilot/models/cursor_usage_account.dart';
import 'package:teampilot/models/cursor_usage_range.dart';
import 'package:teampilot/models/cursor_usage_report.dart';

const _accountA = CursorUsageAccount(
  accountId: 'a',
  userId: 'user_a',
  label: 'A',
  source: CursorAccountSource.discovered,
);
const _accountB = CursorUsageAccount(
  accountId: 'b',
  userId: 'user_b',
  label: 'B',
  source: CursorAccountSource.manual,
);

void main() {
  test('loads accounts then reports for every account', () async {
    final loaded = <String>[];
    final cubit = CursorUsageCubit(
      loadAccounts: () async => [_accountA, _accountB],
      refreshAccount: (_) async {},
      billingCycleFor: (_) async => null,
      loadReport:
          ({
            required accountId,
            required range,
            billingCycle,
            forceRefresh = false,
          }) async {
            loaded.add(accountId);
            return CursorUsageReport(
              accountId: accountId,
              startMs: 0,
              endMs: 1,
              inputTokens: accountId == 'a' ? 10 : 20,
            );
          },
      saveRange: (_) async {},
      initialRange: const CursorUsagePresetRange(CursorUsagePreset.billingCycle),
    );

    await cubit.ensureLoaded();

    expect(cubit.state.status, CursorUsageStatus.ready);
    expect(cubit.state.accounts.length, 2);
    expect(loaded, ['a', 'b']);
    expect(cubit.state.reports['a']!.inputTokens, 10);
    expect(cubit.state.isSyncing, isFalse);
  });

  test('one failing account does not block the other', () async {
    final cubit = CursorUsageCubit(
      loadAccounts: () async => [_accountA, _accountB],
      refreshAccount: (_) async {},
      billingCycleFor: (_) async => null,
      loadReport:
          ({
            required accountId,
            required range,
            billingCycle,
            forceRefresh = false,
          }) async {
            if (accountId == 'a') throw StateError('boom');
            return CursorUsageReport(accountId: accountId, startMs: 0, endMs: 1);
          },
      saveRange: (_) async {},
      initialRange: const CursorUsagePresetRange(CursorUsagePreset.today),
    );

    await cubit.ensureLoaded();

    expect(cubit.state.failures['a'], CursorUsageFailure.network);
    expect(cubit.state.reports['b'], isNotNull);
  });

  test('changing the range persists it and reloads', () async {
    final saved = <CursorUsageRange>[];
    var loads = 0;
    final cubit = CursorUsageCubit(
      loadAccounts: () async => [_accountA],
      refreshAccount: (_) async {},
      billingCycleFor: (_) async => const CursorUsageWindow(
        startMs: 100,
        endMs: 200,
      ),
      loadReport:
          ({
            required accountId,
            required range,
            billingCycle,
            forceRefresh = false,
          }) async {
            loads++;
            return CursorUsageReport(accountId: accountId, startMs: 0, endMs: 1);
          },
      saveRange: (range) async => saved.add(range),
      initialRange: const CursorUsagePresetRange(CursorUsagePreset.billingCycle),
    );

    await cubit.ensureLoaded();
    await cubit.setRange(
      CursorUsageCustomRange(startMs: 1000, endMs: 2000),
    );

    expect(saved.length, 1);
    expect(loads, 2);
    expect(cubit.state.range, isA<CursorUsageCustomRange>());
    expect(cubit.state.billingCycles['a']!.startMs, 100);
  });

  test('selecting an account exposes its report', () async {
    final cubit = CursorUsageCubit(
      loadAccounts: () async => [_accountA, _accountB],
      refreshAccount: (_) async {},
      billingCycleFor: (_) async => null,
      loadReport:
          ({
            required accountId,
            required range,
            billingCycle,
            forceRefresh = false,
          }) async => CursorUsageReport(
            accountId: accountId,
            startMs: 0,
            endMs: 1,
            inputTokens: accountId == 'a' ? 10 : 20,
          ),
      saveRange: (_) async {},
      initialRange: const CursorUsagePresetRange(CursorUsagePreset.today),
    );

    await cubit.ensureLoaded();
    cubit.selectAccount('b');

    expect(cubit.state.selectedAccountId, 'b');
    expect(cubit.state.selectedReport!.inputTokens, 20);
  });
}
```

- [ ] **Step 2: Run the test to confirm it fails**

Run: `cd client && dart run tool/run_tests.dart test/cubits/cursor_usage_cubit_test.dart`
Expected: FAIL — unresolved import.

- [ ] **Step 3: Implement the range preference**

`client/lib/services/cursor_usage/cursor_usage_range_preference.dart`:

```dart
import 'dart:convert';

import '../../models/cursor_usage_range.dart';
import '../io/filesystem.dart';

/// Persists the last selected range as a single string.
final class CursorUsageRangePreference {
  CursorUsageRangePreference({required Filesystem fs, required String path})
    : _fs = fs,
      _path = path;

  final Filesystem _fs;
  final String _path;

  Future<CursorUsageRange> load() async {
    final raw = await _fs.readString(_path);
    if (raw == null || raw.trim().isEmpty) {
      return const CursorUsagePresetRange(CursorUsagePreset.billingCycle);
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return const CursorUsagePresetRange(CursorUsagePreset.billingCycle);
      }
      return decodeCursorUsageRange(Map<String, Object?>.from(decoded));
    } on Object {
      return const CursorUsagePresetRange(CursorUsagePreset.billingCycle);
    }
  }

  Future<void> save(CursorUsageRange range) async {
    await _fs.ensureDir(_fs.pathContext.dirname(_path));
    await _fs.atomicWrite(_path, jsonEncode(encodeCursorUsageRange(range)));
  }
}

Map<String, Object?> encodeCursorUsageRange(CursorUsageRange range) =>
    switch (range) {
      CursorUsagePresetRange(:final preset) => {'preset': preset.name},
      CursorUsageCustomRange(:final startMs, :final endMs) => {
        'startMs': startMs,
        'endMs': endMs,
      },
    };

CursorUsageRange decodeCursorUsageRange(Map<String, Object?> json) {
  final startMs = (json['startMs'] as num?)?.toInt();
  final endMs = (json['endMs'] as num?)?.toInt();
  if (startMs != null && endMs != null) {
    return CursorUsageCustomRange(startMs: startMs, endMs: endMs);
  }
  final preset = CursorUsagePreset.values.firstWhere(
    (value) => value.name == json['preset'],
    orElse: () => CursorUsagePreset.billingCycle,
  );
  return CursorUsagePresetRange(preset);
}
```

- [ ] **Step 4: Implement the cubit**

`client/lib/cubits/cursor_usage_cubit.dart`:

```dart
import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/cursor_usage_account.dart';
import '../models/cursor_usage_range.dart';
import '../models/cursor_usage_report.dart';
import '../services/cursor_usage/cursor_usage_coordinator.dart';

enum CursorUsageStatus { initial, loading, ready, error }

final class CursorUsageState extends Equatable {
  const CursorUsageState({
    this.status = CursorUsageStatus.initial,
    this.accounts = const [],
    this.selectedAccountId,
    this.range = const CursorUsagePresetRange(CursorUsagePreset.billingCycle),
    this.reports = const {},
    this.failures = const {},
    this.syncing = const {},
    this.billingCycles = const {},
  });

  final CursorUsageStatus status;
  final List<CursorUsageAccount> accounts;
  final String? selectedAccountId;
  final CursorUsageRange range;
  final Map<String, CursorUsageReport> reports;
  final Map<String, CursorUsageFailure> failures;
  final Set<String> syncing;
  final Map<String, CursorUsageWindow> billingCycles;

  bool get isSyncing => syncing.isNotEmpty;

  CursorUsageReport? get selectedReport =>
      selectedAccountId == null ? null : reports[selectedAccountId];

  CursorUsageAccount? get selectedAccount {
    final id = selectedAccountId;
    if (id == null) return null;
    for (final account in accounts) {
      if (account.accountId == id) return account;
    }
    return null;
  }

  CursorUsageState copyWith({
    CursorUsageStatus? status,
    List<CursorUsageAccount>? accounts,
    String? selectedAccountId,
    bool clearSelection = false,
    CursorUsageRange? range,
    Map<String, CursorUsageReport>? reports,
    Map<String, CursorUsageFailure>? failures,
    Set<String>? syncing,
    Map<String, CursorUsageWindow>? billingCycles,
  }) => CursorUsageState(
    status: status ?? this.status,
    accounts: accounts ?? this.accounts,
    selectedAccountId: clearSelection
        ? null
        : selectedAccountId ?? this.selectedAccountId,
    range: range ?? this.range,
    reports: reports ?? this.reports,
    failures: failures ?? this.failures,
    syncing: syncing ?? this.syncing,
    billingCycles: billingCycles ?? this.billingCycles,
  );

  @override
  List<Object?> get props => [
    status,
    accounts,
    selectedAccountId,
    range,
    reports,
    failures,
    syncing,
    billingCycles,
  ];
}

final class CursorUsageCubit extends Cubit<CursorUsageState> {
  CursorUsageCubit({
    required Future<List<CursorUsageAccount>> Function() loadAccounts,
    required Future<void> Function(String accountId) refreshAccount,
    required Future<CursorUsageWindow?> Function(String accountId)
    billingCycleFor,
    required Future<CursorUsageReport> Function({
      required String accountId,
      required CursorUsageRange range,
      CursorUsageWindow? billingCycle,
      bool forceRefresh,
    })
    loadReport,
    required Future<void> Function(CursorUsageRange range) saveRange,
    required Future<bool> Function(String rawToken, String? label) addAccount,
    required Future<void> Function(String accountId) removeAccount,
    Future<CursorUsageRange> Function()? loadRange,
    required CursorUsageRange initialRange,
  }) : _loadAccounts = loadAccounts,
       _refreshAccount = refreshAccount,
       _billingCycleFor = billingCycleFor,
       _loadReport = loadReport,
       _saveRange = saveRange,
       _addAccount = addAccount,
       _removeAccount = removeAccount,
       _loadRange = loadRange,
       super(CursorUsageState(range: initialRange));

  final Future<List<CursorUsageAccount>> Function() _loadAccounts;
  final Future<void> Function(String accountId) _refreshAccount;
  final Future<CursorUsageWindow?> Function(String accountId) _billingCycleFor;
  final Future<CursorUsageReport> Function({
    required String accountId,
    required CursorUsageRange range,
    CursorUsageWindow? billingCycle,
    bool forceRefresh,
  })
  _loadReport;
  final Future<void> Function(CursorUsageRange range) _saveRange;
  final Future<bool> Function(String rawToken, String? label) _addAccount;
  final Future<void> Function(String accountId) _removeAccount;
  final Future<CursorUsageRange> Function()? _loadRange;

  Future<void>? _loadFlight;

  Future<void> ensureLoaded() => _loadFlight ??= _load().whenComplete(() {
    _loadFlight = null;
  });

  Future<void> _load({bool force = false}) async {
    if (state.status == CursorUsageStatus.initial) {
      final loader = _loadRange;
      if (loader != null) {
        final saved = await loader();
        if (!isClosed && saved != state.range) {
          emit(state.copyWith(range: saved));
        }
      }
    }
    if (!isClosed) emit(state.copyWith(status: CursorUsageStatus.loading));
    final List<CursorUsageAccount> accounts;
    try {
      accounts = await _loadAccounts();
    } on Object {
      if (!isClosed) emit(state.copyWith(status: CursorUsageStatus.error));
      return;
    }
    final selected = state.selectedAccountId;
    final keep = accounts.any((account) => account.accountId == selected);
    if (!isClosed) {
      emit(
        state.copyWith(
          status: CursorUsageStatus.ready,
          accounts: accounts,
          clearSelection: !keep,
          selectedAccountId: keep ? selected : accounts.firstOrNull?.accountId,
        ),
      );
    }
    await _loadAll(force: force);
  }

  Future<void> _loadAll({bool force = false}) async {
    final accounts = state.accounts.where((account) => account.enabled).toList();
    if (accounts.isEmpty) return;
    final syncing = {...state.syncing, for (final a in accounts) a.accountId};
    if (!isClosed) emit(state.copyWith(syncing: syncing));

    final reports = {...state.reports};
    final failures = {...state.failures};
    final cycles = {...state.billingCycles};

    for (final account in accounts) {
      try {
        await _refreshAccount(account.accountId);
        final cycle =
            cycles[account.accountId] ??
            await _billingCycleFor(account.accountId);
        if (cycle != null) cycles[account.accountId] = cycle;
        reports[account.accountId] = await _loadReport(
          accountId: account.accountId,
          range: state.range,
          billingCycle: cycle,
          forceRefresh: force,
        );
        failures.remove(account.accountId);
      } on CursorUsageException catch (error) {
        failures[account.accountId] = error.failure;
      } on Object {
        failures[account.accountId] = CursorUsageFailure.network;
      }
      if (isClosed) return;
      emit(
        state.copyWith(
          syncing: {...state.syncing}..remove(account.accountId),
          reports: Map.unmodifiable(reports),
          failures: Map.unmodifiable(failures),
          billingCycles: Map.unmodifiable(cycles),
        ),
      );
    }
  }

  void selectAccount(String? accountId) {
    if (accountId == null) {
      emit(state.copyWith(clearSelection: true));
    } else {
      emit(state.copyWith(selectedAccountId: accountId));
    }
  }

  Future<void> setRange(CursorUsageRange range) async {
    if (range == state.range) return;
    emit(state.copyWith(range: range, reports: const {}));
    await _saveRange(range);
    await _loadAll();
  }

  Future<void> refresh({bool force = false}) => _loadAll(force: force);

  Future<bool> addAccount(String rawToken, {String? label}) async {
    final ok = await _addAccount(rawToken, label);
    if (ok) await _load();
    return ok;
  }

  Future<void> removeAccount(String accountId) async {
    await _removeAccount(accountId);
    await _load();
  }
}
```

`accounts.firstOrNull` needs `import 'package:collection/collection.dart';`.

- [ ] **Step 5: Run the tests**

Run: `cd client && dart run tool/run_tests.dart test/cubits/cursor_usage_cubit_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 6: Commit**

```bash
git add client/lib/cubits/cursor_usage_cubit.dart client/lib/services/cursor_usage/cursor_usage_range_preference.dart client/test/cubits/cursor_usage_cubit_test.dart
git commit -m "feat(cursor-usage): add accounts/range cubit"
```

---

### Task 9: Page shell, range picker, account list

**Files:**
- Create: `client/lib/pages/cursor_usage/cursor_usage_page.dart`
- Create: `client/lib/pages/cursor_usage/widgets/range_picker.dart`
- Create: `client/lib/pages/cursor_usage/widgets/account_list.dart`
- Create: `client/lib/pages/cursor_usage/widgets/add_account_dialog.dart`
- Modify: `client/lib/utils/ui/app_keys.dart` (add three keys near the `sessionUsage*` block, line ~328)
- Test: `client/test/pages/cursor_usage/cursor_usage_page_test.dart`

**Interfaces:**
- Consumes: `CursorUsageCubit`, `CursorUsageState`, `CursorUsageAccount`, `CursorUsageRange`, `CursorUsageWindow`.
- Produces: `CursorUsagePage({bool embedded = false})`, `CursorUsageRangePicker`, `CursorUsageAccountList`, `showAddCursorAccountDialog`.

- [ ] **Step 1: Add widget keys**

In `client/lib/utils/ui/app_keys.dart`, after `sessionUsagePage`:

```dart
  static const cursorUsagePage = Key('cursor-usage-page');
  static const cursorUsageAddAccount = Key('cursor-usage-add-account');
  static const cursorUsageRefresh = Key('cursor-usage-refresh');
  static const cursorUsageRangePicker = Key('cursor-usage-range-picker');
```

- [ ] **Step 2: Write the failing widget test**

Create `client/test/pages/cursor_usage/cursor_usage_page_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/cursor_usage_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/cursor_usage_account.dart';
import 'package:teampilot/models/cursor_usage_range.dart';
import 'package:teampilot/models/cursor_usage_report.dart';
import 'package:teampilot/pages/cursor_usage/cursor_usage_page.dart';
import 'package:teampilot/utils/ui/app_keys.dart';

import '../../support/post_frame_test_harness.dart';

void main() {
  setUpTestAppStorage();
  tearDownTestAppStorage();

  CursorUsageCubit buildCubit() => CursorUsageCubit(
    loadAccounts: () async => const [
      CursorUsageAccount(
        accountId: 'a',
        userId: 'user_a',
        label: 'Work',
        source: CursorAccountSource.discovered,
      ),
    ],
    refreshAccount: (_) async {},
    billingCycleFor: (_) async => null,
    loadReport:
        ({
          required accountId,
          required range,
          billingCycle,
          forceRefresh = false,
        }) async => const CursorUsageReport(
          accountId: 'a',
          startMs: 0,
          endMs: 1,
          inputTokens: 1200,
          outputTokens: 300,
          totalCents: 42,
          eventCount: 3,
        ),
    saveRange: (_) async {},
    addAccount: (_, __) async => true,
    removeAccount: (_) async {},
    initialRange: const CursorUsagePresetRange(CursorUsagePreset.billingCycle),
  );

  testWidgets('renders the account and its totals', (tester) async {
    final cubit = buildCubit();
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: BlocProvider<CursorUsageCubit>.value(
          value: cubit,
          child: const Scaffold(body: CursorUsagePage()),
        ),
      ),
    );
    await cubit.ensureLoaded();
    await tester.pumpAndSettle();

    expect(find.byKey(AppKeys.cursorUsagePage), findsOneWidget);
    expect(find.text('Work'), findsOneWidget);
    expect(find.byKey(AppKeys.cursorUsageAddAccount), findsOneWidget);
  });
}
```

- [ ] **Step 3: Run the test to confirm it fails**

Run: `cd client && dart run tool/run_tests.dart test/pages/cursor_usage/cursor_usage_page_test.dart`
Expected: FAIL — unresolved import.

- [ ] **Step 4: Implement the range picker**

`client/lib/pages/cursor_usage/widgets/range_picker.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../l10n/l10n_extensions.dart';
import '../../../models/cursor_usage_range.dart';
import '../../../utils/ui/app_keys.dart';

class CursorUsageRangePicker extends StatelessWidget {
  const CursorUsageRangePicker({
    required this.range,
    required this.onChanged,
    super.key,
  });

  final CursorUsageRange range;
  final ValueChanged<CursorUsageRange> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final styles = TpTextStyles.of(context);
    final selected = switch (range) {
      CursorUsagePresetRange(:final preset) => preset,
      CursorUsageCustomRange() => null,
    };

    return Wrap(
      key: AppKeys.cursorUsageRangePicker,
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final preset in CursorUsagePreset.values)
          ChoiceChip(
            label: Text(_label(context, preset), style: styles.xs),
            selected: selected == preset,
            onSelected: (_) =>
                onChanged(CursorUsagePresetRange(preset)),
          ),
        OutlinedButton.icon(
          icon: const Icon(Icons.date_range_outlined, size: 16),
          label: Text(
            range is CursorUsageCustomRange
                ? l10n.cursorUsageRangeCustomActive
                : l10n.cursorUsageRangeCustom,
            style: styles.xs,
          ),
          onPressed: () async {
            final picked = await showDateRangePicker(
              context: context,
              firstDate: DateTime(2024),
              lastDate: DateTime.now(),
              initialDateRange: range is CursorUsageCustomRange
                  ? DateTimeRange(
                      start: DateTime.fromMillisecondsSinceEpoch(
                        (range as CursorUsageCustomRange).startMs,
                      ),
                      end: DateTime.fromMillisecondsSinceEpoch(
                        (range as CursorUsageCustomRange).endMs,
                      ),
                    )
                  : null,
            );
            if (picked == null) return;
            onChanged(
              CursorUsageCustomRange(
                startMs: DateTime(
                  picked.start.year,
                  picked.start.month,
                  picked.start.day,
                ).millisecondsSinceEpoch,
                endMs: DateTime(
                      picked.end.year,
                      picked.end.month,
                      picked.end.day,
                    ).add(const Duration(days: 1)).millisecondsSinceEpoch -
                    1,
              ),
            );
          },
        ),
      ],
    );
  }

  String _label(BuildContext context, CursorUsagePreset preset) {
    final l10n = context.l10n;
    return switch (preset) {
      CursorUsagePreset.billingCycle => l10n.cursorUsageRangeCycle,
      CursorUsagePreset.today => l10n.cursorUsageRangeToday,
      CursorUsagePreset.sevenDays => l10n.cursorUsageRangeSevenDays,
      CursorUsagePreset.thirtyDays => l10n.cursorUsageRangeThirtyDays,
      CursorUsagePreset.lastMonth => l10n.cursorUsageRangeLastMonth,
    };
  }
}
```

- [ ] **Step 5: Implement the account list**

`client/lib/pages/cursor_usage/widgets/account_list.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../l10n/l10n_extensions.dart';
import '../../../models/cursor_usage_account.dart';
import '../../../models/cursor_usage_range.dart';
import '../../../services/cursor_usage/cursor_usage_coordinator.dart';

class CursorUsageAccountList extends StatelessWidget {
  const CursorUsageAccountList({
    required this.accounts,
    required this.selectedAccountId,
    required this.syncing,
    required this.failures,
    required this.billingCycles,
    required this.onSelect,
    super.key,
  });

  final List<CursorUsageAccount> accounts;
  final String? selectedAccountId;
  final Set<String> syncing;
  final Map<String, CursorUsageFailure> failures;
  final Map<String, CursorUsageWindow> billingCycles;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final styles = TpTextStyles.of(context);
    final cs = Theme.of(context).colorScheme;
    if (accounts.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text(
          l10n.cursorUsageNoAccounts,
          style: styles.smColored(cs.onSurface.withValues(alpha: 0.6)),
        ),
      );
    }
    return Column(
      children: [
        for (final account in accounts)
          ListTile(
            dense: true,
            selected: account.accountId == selectedAccountId,
            onTap: () => onSelect(account.accountId),
            leading: _statusDot(context, account),
            title: Text(account.label, style: styles.md),
            subtitle: Text(
              _subtitle(context, account),
              style: styles.xsColored(cs.onSurface.withValues(alpha: 0.6)),
            ),
          ),
      ],
    );
  }

  Widget _statusDot(BuildContext context, CursorUsageAccount account) {
    final cs = Theme.of(context).colorScheme;
    final failure = failures[account.accountId];
    final expired = account.isExpired(DateTime.now().millisecondsSinceEpoch);
    final color = syncing.contains(account.accountId)
        ? cs.primary
        : expired || failure != null
        ? cs.error
        : cs.tertiary;
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }

  String _subtitle(BuildContext context, CursorUsageAccount account) {
    final l10n = context.l10n;
    final parts = <String>[
      account.source == CursorAccountSource.manual
          ? l10n.cursorUsageSourceManual
          : l10n.cursorUsageSourceAuto,
    ];
    if (account.teamId != 0) parts.add('team ${account.teamId}');
    if (account.isExpired(DateTime.now().millisecondsSinceEpoch)) {
      parts.add(l10n.cursorUsageStatusExpired);
    }
    final failure = failures[account.accountId];
    if (failure != null) parts.add(_failureLabel(context, failure));
    return parts.join(' · ');
  }

  String _failureLabel(BuildContext context, CursorUsageFailure failure) {
    final l10n = context.l10n;
    return switch (failure) {
      CursorUsageFailure.login => l10n.cursorUsageErrorLogin,
      CursorUsageFailure.rateLimited => l10n.cursorUsageErrorRateLimited,
      CursorUsageFailure.network => l10n.cursorUsageErrorNetwork,
      CursorUsageFailure.http => l10n.cursorUsageErrorHttp,
      CursorUsageFailure.invalidResponse => l10n.cursorUsageErrorInvalid,
      CursorUsageFailure.accountMismatch => l10n.cursorUsageErrorMismatch,
      CursorUsageFailure.rangeTooLarge => l10n.cursorUsageErrorRangeTooLarge,
      CursorUsageFailure.noCredential => l10n.cursorUsageErrorNoCredential,
    };
  }
}
```

- [ ] **Step 6: Implement the add dialog**

`client/lib/pages/cursor_usage/widgets/add_account_dialog.dart`:

```dart
import 'package:flutter/material.dart';

import '../../../l10n/l10n_extensions.dart';

/// Returns the pasted value and an optional label, or null when cancelled.
Future<(String, String?)?> showAddCursorAccountDialog(BuildContext context) {
  final tokenController = TextEditingController();
  final labelController = TextEditingController();
  return showDialog<(String, String?)>(
    context: context,
    builder: (context) {
      final l10n = context.l10n;
      return AlertDialog(
        title: Text(l10n.cursorUsageAddAccountTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: tokenController,
              minLines: 3,
              maxLines: 6,
              decoration: InputDecoration(
                labelText: l10n.cursorUsageAddAccountField,
                helperText: l10n.cursorUsageAddAccountHint,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: labelController,
              decoration: InputDecoration(
                labelText: l10n.cursorUsageAddAccountLabel,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () {
              final raw = tokenController.text.trim();
              if (raw.isEmpty) return;
              final label = labelController.text.trim();
              Navigator.of(context).pop((raw, label.isEmpty ? null : label));
            },
            child: Text(l10n.cursorUsageAddAccountConfirm),
          ),
        ],
      );
    },
  );
}
```

- [ ] **Step 7: Implement the page shell**

`client/lib/pages/cursor_usage/cursor_usage_page.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/cursor_usage_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../services/cursor_usage/cursor_usage_coordinator.dart';
import '../../utils/ui/app_keys.dart';
import '../../widgets/app_toast/app_toast.dart';
import '../../widgets/settings/workspace_pane_insets.dart';
import 'widgets/account_list.dart';
import 'widgets/add_account_dialog.dart';
import 'widgets/range_picker.dart';
import 'widgets/usage_detail.dart';

class CursorUsagePage extends StatefulWidget {
  const CursorUsagePage({this.embedded = false, super.key});

  final bool embedded;

  @override
  State<CursorUsagePage> createState() => _CursorUsagePageState();
}

class _CursorUsagePageState extends State<CursorUsagePage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<CursorUsageCubit>().ensureLoaded();
    });
  }

  @override
  Widget build(BuildContext context) {
    final content = BlocBuilder<CursorUsageCubit, CursorUsageState>(
      builder: (context, state) {
        final cubit = context.read<CursorUsageCubit>();
        final styles = TpTextStyles.of(context);
        final cs = Theme.of(context).colorScheme;
        return KeyedSubtree(
          key: AppKeys.cursorUsagePage,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      context.l10n.cursorUsageTitle,
                      style: styles.xl.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  IconButton(
                    key: AppKeys.cursorUsageRefresh,
                    tooltip: context.l10n.cursorUsageRefresh,
                    onPressed: state.isSyncing
                        ? null
                        : () => cubit.refresh(force: true),
                    icon: state.isSyncing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh),
                  ),
                  IconButton(
                    key: AppKeys.cursorUsageAddAccount,
                    tooltip: context.l10n.cursorUsageAddAccount,
                    onPressed: () => _addAccount(cubit),
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              CursorUsageRangePicker(
                range: state.range,
                onChanged: cubit.setRange,
              ),
              const SizedBox(height: 16),
              Expanded(
                child: state.status == CursorUsageStatus.loading &&
                        state.accounts.isEmpty
                    ? const Center(child: CircularProgressIndicator())
                    : state.status == CursorUsageStatus.error
                    ? Center(
                        child: Text(
                          context.l10n.cursorUsageLoadFailed,
                          style: styles.smColored(cs.error),
                        ),
                      )
                    : SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            CursorUsageAccountList(
                              accounts: state.accounts,
                              selectedAccountId: state.selectedAccountId,
                              syncing: state.syncing,
                              failures: state.failures,
                              billingCycles: state.billingCycles,
                              onSelect: cubit.selectAccount,
                            ),
                            const SizedBox(height: 12),
                            if (state.selectedReport case final report?)
                              CursorUsageDetail(
                                report: report,
                                account: state.selectedAccount,
                                cycle: state.billingCycles[
                                    state.selectedAccountId],
                              ),
                          ],
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
    if (widget.embedded) return content;
    return Padding(padding: WorkspacePaneInsets.page, child: content);
  }

  Future<void> _addAccount(CursorUsageCubit cubit) async {
    final result = await showAddCursorAccountDialog(context);
    if (result == null || !mounted) return;
    final ok = await cubit.addAccount(result.$1, label: result.$2);
    if (!mounted) return;
    AppToast.show(
      context,
      message: ok
          ? context.l10n.cursorUsageAddAccountSuccess
          : context.l10n.cursorUsageAddAccountInvalid,
      variant: ok ? TpToastVariant.success : TpToastVariant.error,
    );
  }
}
```

`CursorUsageDetail` is declared in Task 10; import it here with
`import 'widgets/usage_detail.dart';` and keep the task order — Task 10 must be
implemented before this page compiles. If you are executing strictly in order,
add a temporary placeholder file `widgets/usage_detail.dart` in this task with
the minimal signature:

```dart
import 'package:flutter/material.dart';

import '../../../models/cursor_usage_account.dart';
import '../../../models/cursor_usage_range.dart';
import '../../../models/cursor_usage_report.dart';

class CursorUsageDetail extends StatelessWidget {
  const CursorUsageDetail({
    required this.report,
    required this.account,
    required this.cycle,
    super.key,
  });

  final CursorUsageReport report;
  final CursorUsageAccount? account;
  final CursorUsageWindow? cycle;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
```

Task 10 replaces that body.

- [ ] **Step 8: Run the test**

Run: `cd client && dart run tool/run_tests.dart test/pages/cursor_usage/cursor_usage_page_test.dart`
Expected: PASS (1 test).

- [ ] **Step 9: Commit**

```bash
git add client/lib/pages/cursor_usage client/lib/utils/ui/app_keys.dart client/test/pages/cursor_usage/cursor_usage_page_test.dart
git commit -m "feat(cursor-usage): add page shell, range picker, and account list"
```

---

### Task 10: Detail widgets

**Files:**
- Create: `client/lib/pages/cursor_usage/cursor_usage_format.dart`
- Create: `client/lib/pages/cursor_usage/widgets/usage_detail.dart`
- Create: `client/lib/pages/cursor_usage/widgets/usage_totals.dart`
- Create: `client/lib/pages/cursor_usage/widgets/model_breakdown.dart`
- Create: `client/lib/pages/cursor_usage/widgets/event_table.dart`
- Test: `client/test/pages/cursor_usage/cursor_usage_detail_test.dart`

**Interfaces:**
- Consumes: `CursorUsageReport`, `CursorUsageDay`, `CursorUsageModelTotals`, `CursorUsageEvent`, `CursorUsageWindow`.
- Produces: `CursorUsageDetail({required report, required account, required cycle})`, `CursorUsageTotals`, `CursorUsageModelBreakdown`, `CursorUsageEventTable`.

- [ ] **Step 1: Write the failing test**

Create `client/test/pages/cursor_usage/cursor_usage_detail_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/cursor_usage_range.dart';
import 'package:teampilot/models/cursor_usage_report.dart';
import 'package:teampilot/pages/cursor_usage/widgets/model_breakdown.dart';
import 'package:teampilot/pages/cursor_usage/widgets/usage_totals.dart';

void main() {
  const report = CursorUsageReport(
    accountId: 'a',
    startMs: 0,
    endMs: 1,
    inputTokens: 1500,
    outputTokens: 2500,
    cacheReadTokens: 10000,
    cacheWriteTokens: 0,
    totalCents: 1234,
    eventCount: 7,
    models: {
      'cursor-grok-4.6-high': CursorUsageModelTotals(
        inputTokens: 1500,
        outputTokens: 2500,
        cacheReadTokens: 10000,
        totalCents: 1000,
        eventCount: 5,
      ),
      '': CursorUsageModelTotals(totalCents: 234, eventCount: 2),
    },
  );

  testWidgets('totals render the token buckets', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const CursorUsageTotals(report: report),
      ),
    );
    expect(find.textContaining('15'), findsWidgets);
  });

  testWidgets('model breakdown folds the empty model into unattributed', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const CursorUsageModelBreakdown(report: report),
      ),
    );
    expect(find.textContaining('cursor-grok-4.6-high'), findsOneWidget);
  });

  test('unattributed slice is merged from the empty model key', () {
    final slices = cursorUsageModelSlices(report);
    expect(slices.length, 2);
    expect(slices.first.model, 'cursor-grok-4.6-high');
    expect(slices.map((slice) => slice.model), contains(cursorUsageUnattributedModel));
  });
}
```

- [ ] **Step 2: Run the test to confirm it fails**

Run: `cd client && dart run tool/run_tests.dart test/pages/cursor_usage/cursor_usage_detail_test.dart`
Expected: FAIL — unresolved import.

- [ ] **Step 3: Add the money and date formatters, then the totals widget**

`client/lib/pages/cursor_usage/cursor_usage_format.dart` — `formatUsageCost`
takes **micro-USD**, so cents multiply by 10 000:

```dart
import '../usage/usage_format.dart';

/// `report.totalCents` is USD cents; the shared formatter wants micro-USD.
String formatCursorUsageUsd(double cents) =>
    formatUsageCost((cents * 10000).round());

String formatCursorUsageDate(int ms) {
  final date = DateTime.fromMillisecondsSinceEpoch(ms).toLocal();
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '${date.year}-$month-$day';
}

String formatCursorUsageTimestamp(int ms) {
  final date = DateTime.fromMillisecondsSinceEpoch(ms).toLocal();
  final hour = date.hour.toString().padLeft(2, '0');
  final minute = date.minute.toString().padLeft(2, '0');
  return '${formatCursorUsageDate(ms)} $hour:$minute';
}
```

`client/lib/pages/cursor_usage/widgets/usage_totals.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../l10n/l10n_extensions.dart';
import '../../../models/cursor_usage_report.dart';
import '../../../pages/usage/usage_format.dart';
import '../cursor_usage_format.dart';

class CursorUsageTotals extends StatelessWidget {
  const CursorUsageTotals({required this.report, super.key});

  final CursorUsageReport report;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final styles = TpTextStyles.of(context);
    final cs = Theme.of(context).colorScheme;
    final cells = <(String, String)>[
      (l10n.cursorUsageInput, formatUsageTokens(report.inputTokens)),
      (l10n.cursorUsageOutput, formatUsageTokens(report.outputTokens)),
      (l10n.cursorUsageCacheRead, formatUsageTokens(report.cacheReadTokens)),
      (l10n.cursorUsageCacheWrite, formatUsageTokens(report.cacheWriteTokens)),
      (l10n.cursorUsageCost, formatCursorUsageUsd(report.totalCents)),
      (l10n.cursorUsageEvents, '${report.eventCount}'),
    ];
    return Wrap(
      spacing: 24,
      runSpacing: 12,
      children: [
        for (final cell in cells)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                cell.$1,
                style: styles.xsColored(cs.onSurface.withValues(alpha: 0.55)),
              ),
              const SizedBox(height: 2),
              Text(cell.$2, style: styles.mdSemibold),
            ],
          ),
      ],
    );
  }
}
```

The shared `formatUsageTokens` / `formatUsageCost` helpers live in
`client/lib/pages/usage/usage_format.dart`. Do not add new formatters there —
`cursor_usage_format.dart` is the only addition.

- [ ] **Step 4: Implement model breakdown**

`client/lib/pages/cursor_usage/widgets/model_breakdown.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../l10n/l10n_extensions.dart';
import '../../../models/cursor_usage_report.dart';
import '../../usage/usage_format.dart';

const cursorUsageUnattributedModel = 'unattributed';

@immutable
final class CursorUsageModelSlice {
  const CursorUsageModelSlice({
    required this.model,
    required this.totals,
    required this.share,
  });

  final String model;
  final CursorUsageModelTotals totals;
  final double share;
}

List<CursorUsageModelSlice> cursorUsageModelSlices(CursorUsageReport report) {
  final merged = <String, CursorUsageModelTotals>{};
  for (final entry in report.models.entries) {
    final key = entry.key.trim().isEmpty
        ? cursorUsageUnattributedModel
        : entry.key;
    merged[key] =
        (merged[key] ?? const CursorUsageModelTotals()).merge(entry.value);
  }
  final total = merged.values.fold<int>(
    0,
    (sum, value) => sum + value.totalTokens,
  );
  final slices = merged.entries
      .map(
        (entry) => CursorUsageModelSlice(
          model: entry.key,
          totals: entry.value,
          share: total == 0 ? 0 : entry.value.totalTokens / total,
        ),
      )
      .toList()
    ..sort((a, b) => b.totals.totalTokens.compareTo(a.totals.totalTokens));
  return slices;
}

class CursorUsageModelBreakdown extends StatelessWidget {
  const CursorUsageModelBreakdown({required this.report, super.key});

  final CursorUsageReport report;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final styles = TpTextStyles.of(context);
    final cs = Theme.of(context).colorScheme;
    final slices = cursorUsageModelSlices(report);
    if (slices.isEmpty) {
      return Text(
        l10n.cursorUsageNoData,
        style: styles.smColored(cs.onSurface.withValues(alpha: 0.6)),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final slice in slices)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    slice.model == cursorUsageUnattributedModel
                        ? l10n.cursorUsageUnattributed
                        : slice.model,
                    style: styles.xs,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '${formatUsageTokens(slice.totals.totalTokens)}  '
                  '${(slice.share * 100).toStringAsFixed(0)}%',
                  style: styles.xsColored(cs.onSurface.withValues(alpha: 0.6)),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
```

- [ ] **Step 5: Implement the event table**

`client/lib/pages/cursor_usage/widgets/event_table.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../l10n/l10n_extensions.dart';
import '../../../models/cursor_usage_report.dart';
import '../../usage/usage_format.dart';
import '../cursor_usage_format.dart';

class CursorUsageEventTable extends StatelessWidget {
  const CursorUsageEventTable({required this.report, super.key});

  final CursorUsageReport report;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final styles = TpTextStyles.of(context);
    final cs = Theme.of(context).colorScheme;
    if (report.summaryOnly) {
      return Text(
        l10n.cursorUsageSummaryOnly,
        style: styles.xsColored(cs.onSurface.withValues(alpha: 0.6)),
      );
    }
    if (report.events.isEmpty) {
      return Text(
        l10n.cursorUsageNoData,
        style: styles.xsColored(cs.onSurface.withValues(alpha: 0.6)),
      );
    }
    return Column(
      children: [
        for (final event in report.events.take(200))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                SizedBox(
                  width: 132,
                  child: Text(
                    formatCursorUsageTimestamp(event.timestampMs),
                    style: styles.xsColored(
                      cs.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    event.model.isEmpty
                        ? l10n.cursorUsageUnattributed
                        : event.model,
                    style: styles.xs,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  formatUsageTokens(event.totalTokens),
                  style: styles.xs,
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 68,
                  child: Text(
                    formatCursorUsageUsd(event.totalCents),
                    textAlign: TextAlign.right,
                    style: styles.xs,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
```

- [ ] **Step 6: Implement the detail container**

Replace the placeholder `client/lib/pages/cursor_usage/widgets/usage_detail.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../l10n/l10n_extensions.dart';
import '../../../models/cursor_usage_account.dart';
import '../../../models/cursor_usage_range.dart';
import '../../../models/cursor_usage_report.dart';
import '../cursor_usage_format.dart';
import 'event_table.dart';
import 'model_breakdown.dart';
import 'usage_totals.dart';

class CursorUsageDetail extends StatelessWidget {
  const CursorUsageDetail({
    required this.report,
    required this.account,
    required this.cycle,
    super.key,
  });

  final CursorUsageReport report;
  final CursorUsageAccount? account;
  final CursorUsageWindow? cycle;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final styles = TpTextStyles.of(context);
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.cursorUsageTotals, style: styles.mdSemibold),
        const SizedBox(height: 8),
        CursorUsageTotals(report: report),
        const SizedBox(height: 20),
        Text(l10n.cursorUsageByModel, style: styles.mdSemibold),
        const SizedBox(height: 8),
        CursorUsageModelBreakdown(report: report),
        const SizedBox(height: 20),
        Text(l10n.cursorUsageEvents, style: styles.mdSemibold),
        const SizedBox(height: 8),
        CursorUsageEventTable(report: report),
        if (cycle != null) ...[
          const SizedBox(height: 16),
          Text(
            l10n.cursorUsageCycleRange(
              formatCursorUsageDate(cycle!.startMs),
              formatCursorUsageDate(cycle!.endMs),
            ),
            style: styles.xsColored(cs.onSurface.withValues(alpha: 0.6)),
          ),
        ],
      ],
    );
  }
}
```

- [ ] **Step 7: Run the tests**

Run: `cd client && dart run tool/run_tests.dart test/pages/cursor_usage/`
Expected: PASS (2 files).

- [ ] **Step 8: Commit**

```bash
git add client/lib/pages/cursor_usage/widgets client/test/pages/cursor_usage/cursor_usage_detail_test.dart
git commit -m "feat(cursor-usage): add totals, model split, and event table"
```

---

### Task 11: Wiring, localization, and final verification

**Files:**
- Modify: `client/lib/pages/home_workspace/home_workspace_global_section.dart` (enum + switch)
- Modify: `client/lib/pages/home_workspace/home_workspace_sidebar.dart` (shortcut row, after the session usage row at line ~213)
- Modify: `client/lib/app/app_shell.dart` (construct registry, coordinator, cubit; provide it)
- Modify: `client/lib/l10n/app_en.arb`, `client/lib/l10n/app_zh.arb`
- Test: `client/test/services/cursor_usage/cursor_usage_paths_test.dart`

**Interfaces:**
- Consumes: everything above.
- Produces: `HomeGlobalView.cursorUsage`, `CursorUsageCubit` provided at the home shell.

- [ ] **Step 1: Write the failing path test**

Create `client/test/services/cursor_usage/cursor_usage_paths_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/storage/app_paths.dart';

void main() {
  test('cursor usage paths live under the teampilot root', () {
    const paths = AppPaths('/root/teampilot');
    expect(paths.cursorUsageDir, '/root/teampilot/cursor_usage');
    expect(
      paths.cursorUsageAccountsFile,
      '/root/teampilot/cursor_usage/accounts.json',
    );
    expect(
      paths.cursorUsageCacheFile('abc'),
      '/root/teampilot/cursor_usage/cache/abc.json',
    );
  });
}
```

- [ ] **Step 2: Run it**

Run: `cd client && dart run tool/run_tests.dart test/services/cursor_usage/cursor_usage_paths_test.dart`
Expected: PASS (1 test).

- [ ] **Step 3: Add the enum value and page mapping**

In `home_workspace_global_section.dart`:

```dart
enum HomeGlobalView {
  ...
  usage,
  cursorUsage,
  automations;
```

and in the `switch`:

```dart
      HomeGlobalView.usage => const SessionUsagePage(embedded: true),
      HomeGlobalView.cursorUsage => const CursorUsagePage(embedded: true),
```

with `import '../cursor_usage/cursor_usage_page.dart';`.

- [ ] **Step 4: Add the sidebar row**

After the `sessionUsageNav` row in `home_workspace_sidebar.dart`:

```dart
        const SizedBox(height: 4),
        _ShortcutRow(
          icon: Icons.token_outlined,
          label: l10n.cursorUsageNav,
          active: activeGlobalView == HomeGlobalView.cursorUsage,
          onTap: () => onGlobal?.call(HomeGlobalView.cursorUsage),
        ),
```

- [ ] **Step 5: Add the l10n keys**

Append to `client/lib/l10n/app_en.arb` (before the closing brace, comma-separated):

```json
  "cursorUsageNav": "Cursor usage",
  "cursorUsageTitle": "Cursor usage",
  "cursorUsageRefresh": "Refresh",
  "cursorUsageAddAccount": "Add account",
  "cursorUsageAddAccountTitle": "Add a Cursor account",
  "cursorUsageAddAccountField": "Session token",
  "cursorUsageAddAccountHint": "Paste WorkosCursorSessionToken=... from cursor.com, or just the token.",
  "cursorUsageAddAccountLabel": "Label (optional)",
  "cursorUsageAddAccountConfirm": "Add",
  "cursorUsageAddAccountSuccess": "Cursor account added",
  "cursorUsageAddAccountInvalid": "That token is invalid or already expired",
  "cursorUsageNoAccounts": "No Cursor account found. Sign in with the Cursor CLI, or add one manually.",
  "cursorUsageSourceAuto": "Auto",
  "cursorUsageSourceManual": "Manual",
  "cursorUsageStatusExpired": "Expired",
  "cursorUsageTotals": "Totals",
  "cursorUsageByModel": "By model",
  "cursorUsageUnattributed": "Unattributed",
  "cursorUsageSummaryOnly": "Only summary totals are kept for this range.",
  "cursorUsageNoData": "No usage in this range.",
  "cursorUsageInput": "Input",
  "cursorUsageOutput": "Output",
  "cursorUsageCacheRead": "Cache read",
  "cursorUsageCacheWrite": "Cache write",
  "cursorUsageCost": "Cost",
  "cursorUsageEvents": "Events",
  "cursorUsageRangeCycle": "Billing cycle",
  "cursorUsageRangeToday": "Today",
  "cursorUsageRangeSevenDays": "7 days",
  "cursorUsageRangeThirtyDays": "30 days",
  "cursorUsageRangeLastMonth": "Last month",
  "cursorUsageRangeCustom": "Custom",
  "cursorUsageRangeCustomActive": "Custom range",
  "cursorUsageLoadFailed": "Could not load Cursor accounts.",
  "cursorUsageErrorLogin": "Sign in again",
  "cursorUsageErrorRateLimited": "Rate limited",
  "cursorUsageErrorNetwork": "Network error",
  "cursorUsageErrorHttp": "Cursor error",
  "cursorUsageErrorInvalid": "Unexpected response",
  "cursorUsageErrorMismatch": "Token belongs to another account",
  "cursorUsageErrorRangeTooLarge": "Range too large",
  "cursorUsageErrorNoCredential": "No credential",
  "cursorUsageCycleRange": "Billing cycle: {start} – {end}",
  "@cursorUsageCycleRange": {
    "placeholders": {
      "start": { "type": "String" },
      "end": { "type": "String" }
    }
  }
```

Append the matching Chinese block to `app_zh.arb` with the same keys.

- [ ] **Step 6: Wire the services and cubit in `app_shell.dart`**

Next to the `sessionUsageServices` block (line ~1589):

```dart
    final cursorAccountCredentialStore = CursorAccountCredentialStore(
      store: const FlutterSecureKeyValueStore(),
    );
    final cursorUsageCacheStore = CursorUsageCacheStore(
      fs: homeStorage.fs,
      pathFor: (accountId) => homeStorage.paths.cursorUsageCacheFile(accountId),
    );
    final cursorUsageApiClient = CursorUsageApiClient();
    final cursorAccountRegistry = CursorAccountRegistry(
      fs: homeStorage.fs,
      accountsPath: homeStorage.paths.cursorUsageAccountsFile,
      credentials: cursorAccountCredentialStore,
      resolveAuths: CursorUsageAuthResolver(
        fs: homeStorage.fs,
        basePath: homeStorage.paths.basePath,
        home: homeStorage.home,
      ).resolveAll,
    );
    final cursorUsageCoordinator = CursorUsageCoordinator(
      registry: cursorAccountRegistry,
      cacheStore: cursorUsageCacheStore,
      api: cursorUsageApiClient,
    );
    final cursorUsageRangePreference = CursorUsageRangePreference(
      fs: homeStorage.fs,
      path: homeStorage.paths.cursorUsageUiStateFile,
    );
    final cursorUsageCubit = CursorUsageCubit(
      loadAccounts: cursorAccountRegistry.list,
      refreshAccount: (accountId) async {},
      billingCycleFor: cursorUsageCoordinator.billingCycleFor,
      loadReport: ({
        required accountId,
        required range,
        billingCycle,
        forceRefresh = false,
      }) => cursorUsageCoordinator.load(
        accountId: accountId,
        range: range,
        billingCycle: billingCycle,
        forceRefresh: forceRefresh,
      ),
      saveRange: cursorUsageRangePreference.save,
      loadRange: cursorUsageRangePreference.load,
      addAccount: (raw, label) async {
        final credentials = parseCursorSessionToken(raw);
        if (credentials == null) return false;
        await cursorAccountRegistry.upsertManual(credentials, label: label);
        return true;
      },
      removeAccount: cursorAccountRegistry.remove,
      initialRange: const CursorUsagePresetRange(
        CursorUsagePreset.billingCycle,
      ),
    );
```

Imports to add to `app_shell.dart`: `cubits/cursor_usage_cubit.dart`,
`models/cursor_usage_range.dart`, `repositories/ssh_credential_store.dart`
(`FlutterSecureKeyValueStore`), `services/cli/cursor/provider/cursor_usage_auth_resolver.dart`,
`services/cursor_usage/cursor_account_credential_store.dart`,
`services/cursor_usage/cursor_account_registry.dart`,
`services/cursor_usage/cursor_usage_api_client.dart`,
`services/cursor_usage/cursor_usage_cache_store.dart`,
`services/cursor_usage/cursor_usage_coordinator.dart`,
`services/cursor_usage/cursor_usage_range_preference.dart`.

`refreshAccount` stays a no-op: credential refresh already happens inside
`CursorAccountRegistry.credentialFor`.

Then add `BlocProvider<CursorUsageCubit>.value(value: cursorUsageCubit)` to the
`MultiBlocProvider` at line ~3556, and close the cubit and API client in the
shell's dispose path next to `sessionUsageCubit.close()`.

- [ ] **Step 7: Compile and analyze**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: no new issues. Fix every `cursorUsage`-related issue before continuing.

- [ ] **Step 8: Run the whole feature's tests**

Run: `cd client && dart run tool/run_tests.dart test/services/cursor_usage/ test/cubits/cursor_usage_cubit_test.dart test/pages/cursor_usage/`
Expected: PASS.

- [ ] **Step 9: Full suite in the background**

Run: `cd client && dart run tool/run_tests.dart`
Expected: PASS. This is the slow outer loop; run it once, in the background.

- [ ] **Step 10: Commit**

```bash
git add client/lib/pages/home_workspace/home_workspace_global_section.dart client/lib/pages/home_workspace/home_workspace_sidebar.dart client/lib/app/app_shell.dart client/lib/l10n/app_en.arb client/lib/l10n/app_zh.arb client/test/services/cursor_usage/cursor_usage_paths_test.dart
git commit -m "feat(cursor-usage): wire the page into the home shell"
```

---

### Task 12: Feed account usage into the session usage totals

**Files:**
- Create: `client/lib/services/cursor_usage/cursor_usage_event_source.dart`
- Modify: `client/lib/app/session_usage_services.dart` (`loadEvents` at line ~189, `forStorage` params at line ~67)
- Modify: `client/lib/pages/usage/usage_format.dart:101`
- Modify: `client/lib/pages/cursor_usage/widgets/account_list.dart` (totals row)
- Modify: `client/lib/pages/cursor_usage/cursor_usage_page.dart` (pass reports)
- Modify: `client/lib/l10n/app_en.arb`, `app_zh.arb` (one key)
- Modify: `client/lib/app/app_shell.dart` (pass the source)
- Test: `client/test/services/cursor_usage/cursor_usage_event_source_test.dart`

**Interfaces:**
- Consumes: `CursorUsageAccount`, `CursorUsageCache`, `CursorUsageDay`, `SessionUsageEvent`, `CliTool`.
- Produces:
  - `const cursorAccountUsageSessionId = 'cursor-account-usage'`
  - `CursorUsageEventSource({required Future<List<CursorUsageAccount>> Function() listAccounts, required Future<CursorUsageCache> Function(String accountId) loadCache})`
  - `Future<List<SessionUsageEvent>> loadEvents()`

- [ ] **Step 1: Write the failing test**

Create `client/test/services/cursor_usage/cursor_usage_event_source_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/cursor_usage_account.dart';
import 'package:teampilot/models/cursor_usage_report.dart';
import 'package:teampilot/services/cursor_usage/cursor_usage_event_source.dart';

int ms(int day) => DateTime(2026, 10, day).millisecondsSinceEpoch;

const _account = CursorUsageAccount(
  accountId: 'acct1',
  userId: 'user_a',
  label: 'A',
  source: CursorAccountSource.discovered,
);

CursorUsageCache cacheWithDays() => CursorUsageCache(
  accountId: 'acct1',
  days: [
    CursorUsageDay(
      dayMs: ms(1),
      inputTokens: 10,
      outputTokens: 5,
      cacheReadTokens: 100,
      cacheWriteTokens: 2,
      totalCents: 3.5,
      eventCount: 2,
      models: const {
        'cursor-grok-4.6-high': CursorUsageModelTotals(
          inputTokens: 10,
          outputTokens: 5,
          cacheReadTokens: 100,
          cacheWriteTokens: 2,
          totalCents: 3.5,
          eventCount: 2,
        ),
        '': CursorUsageModelTotals(totalCents: 1, eventCount: 1),
      },
    ),
  ],
);

void main() {
  test('synthesizes one event per account, day, and model', () async {
    final source = CursorUsageEventSource(
      listAccounts: () async => [_account],
      loadCache: (_) async => cacheWithDays(),
    );

    final events = await source.loadEvents();

    expect(events.length, 2);
    final grok = events.firstWhere((e) => e.model == 'cursor-grok-4.6-high');
    expect(grok.requestId, 'cursor-account:acct1:${ms(1)}:cursor-grok-4.6-high');
    expect(grok.sessionId, cursorAccountUsageSessionId);
    expect(grok.inputTokens, 10);
    expect(grok.cacheCreationTokens, 2);
    expect(grok.timestampMs, ms(1));
    expect(grok.costMicroUsd, 35000);
    expect(events.every((e) => e.cli.name == 'cursor'), isTrue);
  });

  test('an empty model name becomes cursor-auto', () async {
    final source = CursorUsageEventSource(
      listAccounts: () async => [_account],
      loadCache: (_) async => cacheWithDays(),
    );
    final events = await source.loadEvents();
    expect(events.map((e) => e.model), contains('cursor-auto'));
  });

  test('disabled accounts are skipped', () async {
    final source = CursorUsageEventSource(
      listAccounts: () async => [
        const CursorUsageAccount(
          accountId: 'acct1',
          userId: 'user_a',
          label: 'A',
          source: CursorAccountSource.manual,
          enabled: false,
        ),
      ],
      loadCache: (_) async => cacheWithDays(),
    );
    expect(await source.loadEvents(), isEmpty);
  });

  test('two accounts with identical days do not collide', () async {
    final source = CursorUsageEventSource(
      listAccounts: () async => [
        _account,
        const CursorUsageAccount(
          accountId: 'acct2',
          userId: 'user_b',
          label: 'B',
          source: CursorAccountSource.manual,
        ),
      ],
      loadCache: (accountId) async => CursorUsageCache(
        accountId: accountId,
        days: cacheWithDays().days,
      ),
    );
    final events = await source.loadEvents();
    expect(events.map((e) => e.requestId).toSet().length, events.length);
  });
}
```

- [ ] **Step 2: Run the test to confirm it fails**

Run: `cd client && dart run tool/run_tests.dart test/services/cursor_usage/cursor_usage_event_source_test.dart`
Expected: FAIL — unresolved import.

- [ ] **Step 3: Implement the source**

`client/lib/services/cursor_usage/cursor_usage_event_source.dart`:

```dart
import '../../models/cursor_usage_account.dart';
import '../../models/cursor_usage_report.dart';
import '../../models/session_usage.dart';
import '../../models/team_config.dart';

/// Synthetic session id for account-level Cursor rows.
const cursorAccountUsageSessionId = 'cursor-account-usage';

/// Turns the per-account caches into [SessionUsageEvent]s so the session usage
/// dashboard totals every Cursor account.
///
/// Uses the `days` aggregates rather than the raw 90-day `events` list: older
/// ranges still count, and `days` is derived from `events`, so the two can
/// never double count.
final class CursorUsageEventSource {
  CursorUsageEventSource({
    required Future<List<CursorUsageAccount>> Function() listAccounts,
    required Future<CursorUsageCache> Function(String accountId) loadCache,
  }) : _listAccounts = listAccounts,
       _loadCache = loadCache;

  final Future<List<CursorUsageAccount>> Function() _listAccounts;
  final Future<CursorUsageCache> Function(String accountId) _loadCache;

  Future<List<SessionUsageEvent>> loadEvents() async {
    final accounts = await _listAccounts();
    final out = <SessionUsageEvent>[];
    for (final account in accounts) {
      if (!account.enabled) continue;
      final cache = await _loadCache(account.accountId);
      for (final day in cache.days) {
        for (final entry in day.models.entries) {
          final totals = entry.value;
          if (totals.totalTokens == 0 && totals.totalCents == 0) continue;
          out.add(
            SessionUsageEvent(
              requestId:
                  'cursor-account:${account.accountId}:${day.dayMs}:${entry.key}',
              cli: CliTool.cursor,
              model: entry.key.trim().isEmpty ? 'cursor-auto' : entry.key,
              inputTokens: totals.inputTokens,
              outputTokens: totals.outputTokens,
              cacheReadTokens: totals.cacheReadTokens,
              cacheCreationTokens: totals.cacheWriteTokens,
              inputSemantics: UsageInputSemantics.fresh,
              timestampMs: day.dayMs,
              sessionId: cursorAccountUsageSessionId,
              costMicroUsd: (totals.totalCents * 10000).round(),
            ),
          );
        }
      }
    }
    return out;
  }
}
```

The API's `inputTokens` excludes cache reads (verified: `9598 + 4642 + 335488 = 349728` equals the reported total), which is why the semantics are `fresh`.

- [ ] **Step 4: Run the test**

Run: `cd client && dart run tool/run_tests.dart test/services/cursor_usage/cursor_usage_event_source_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Wire it into `loadEvents`**

In `client/lib/app/session_usage_services.dart`:

1. Add a factory parameter next to `cursorHttpClient` (line ~74):

```dart
    Future<List<SessionUsageEvent>> Function()? loadCursorAccountUsage,
```

2. Replace the body of `loadEvents()` (line ~189) so the Cursor rows come from
   the account source instead of `stores.cursorImport`. The whole method becomes:

```dart
    Future<List<SessionUsageEvent>> loadEvents() async {
      final stores = currentStores();
      final base = await stores.store.readLatest();
      final imported = await (loadCursorAccountUsage?.call() ??
          Future<List<SessionUsageEvent>>.value(const []));
      if (imported.isEmpty) return base;
      final byId = {for (final event in base) event.requestId: event};
      for (final event in imported) {
        byId[event.requestId] = event;
      }
      final merged = byId.values.toList(growable: false);
      merged.sort((a, b) => a.timestampMs.compareTo(b.timestampMs));
      return merged;
    }
```

This deliberately drops `stores.cursorImport.loadEvents()`: keeping both
sources would double count, since the two id schemes cannot be reconciled.

- [ ] **Step 6: Relabel the synthetic session**

In `client/lib/pages/usage/usage_format.dart`:

```dart
import '../../services/cursor_usage/cursor_usage_event_source.dart';
```

and at line 101:

```dart
  if (group.label == cursorAccountUsageSessionId) {
    return l10n.sessionUsageCursorImportedSession;
  }
```

Remove the now-unused `import '../../models/cursor_usage_import.dart';` from
that file. Keep the l10n key — only its vendor changes.

- [ ] **Step 7: Add the all-accounts totals row**

In `cursor_usage_account_list`'s constructor add
`required this.reports` (`Map<String, CursorUsageReport>`), and render above the
list:

```dart
      if (reports.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            '${l10n.cursorUsageAllAccounts} · '
            '${formatUsageTokens(totalTokens)} · ${formatCursorUsageUsd(totalCents)}',
            style: styles.xsColored(cs.onSurface.withValues(alpha: 0.55)),
          ),
        ),
```

with locals computed first:

```dart
    final totalTokens = reports.values.fold<int>(0, (sum, r) => sum + r.totalTokens);
    final totalCents = reports.values.fold<double>(0, (sum, r) => sum + r.totalCents);
```

Add imports for `usage_format.dart` and `cursor_usage_format.dart`, pass
`reports: state.reports` from `cursor_usage_page.dart`, and add the key
`"cursorUsageAllAccounts": "All accounts"` (+ zh) to both ARB files.

- [ ] **Step 8: Pass the source from `app_shell.dart`**

Where `SessionUsageServices.forStorage` is called (line ~1589):

```dart
      loadCursorAccountUsage: () => CursorUsageEventSource(
        listAccounts: cursorAccountRegistry.list,
        loadCache: cursorUsageCacheStore.load,
      ).loadEvents(),
```

`cursorAccountRegistry` and `cursorUsageCacheStore` are created in Task 11's
block, which appears *after* this call site. Move the Task 11 block above
`sessionUsageServices` so both are in scope.

- [ ] **Step 9: Run the affected tests**

Run: `cd client && dart run tool/run_tests.dart test/services/cursor_usage/ test/services/usage/session_usage_services_test.dart test/pages/usage/`
Expected: PASS. `session_usage_services_test.dart` exercises `loadEvents`; if it
asserts imported Cursor rows, update it to the new source.

- [ ] **Step 10: Commit**

```bash
git add client/lib/services/cursor_usage/cursor_usage_event_source.dart client/lib/app/session_usage_services.dart client/lib/app/app_shell.dart client/lib/pages/usage/usage_format.dart client/lib/pages/cursor_usage client/lib/l10n/app_en.arb client/lib/l10n/app_zh.arb client/test/services/cursor_usage/cursor_usage_event_source_test.dart
git commit -m "feat(cursor-usage): count every account in session usage totals"
```

---

### Task 13: Retire the old Cursor import path

**Files:**
- Delete: `client/lib/services/usage/cursor_usage_sync_service.dart`
- Delete: `client/lib/services/usage/cursor_usage_csv.dart`
- Delete: `client/lib/services/usage/cursor_usage_import_store.dart`
- Delete: `client/lib/models/cursor_usage_import.dart`
- Delete: `client/test/services/usage/cursor_usage_csv_test.dart`
- Delete: `client/test/services/usage/cursor_usage_import_store_test.dart`
- Delete: `client/test/services/usage/cursor_usage_sync_service_test.dart`
- Modify: `client/lib/app/session_usage_services.dart`, `client/lib/cubits/session_usage_cubit.dart`, `client/lib/pages/usage/session_usage_page.dart`, `client/lib/pages/usage/usage_maintenance_dialog.dart`, `client/lib/app/app_shell.dart`, `client/lib/l10n/app_en.arb`, `client/lib/l10n/app_zh.arb`
- Modify: `client/test/cubits/session_usage_cubit_test.dart`, `client/test/pages/usage/usage_maintenance_dialog_test.dart`

**Interfaces:**
- Consumes: Task 12's bridge, which is now the only Cursor data path.
- Produces: nothing new. `SessionUsageServices` loses `loadCursorStatus`,
  `importCursorCsv`, `syncCursorUsage`, `clearCursorUsage`.

- [ ] **Step 1: Delete the four implementation files and three test files**

```bash
git rm client/lib/services/usage/cursor_usage_sync_service.dart \
       client/lib/services/usage/cursor_usage_csv.dart \
       client/lib/services/usage/cursor_usage_import_store.dart \
       client/lib/models/cursor_usage_import.dart \
       client/test/services/usage/cursor_usage_csv_test.dart \
       client/test/services/usage/cursor_usage_import_store_test.dart \
       client/test/services/usage/cursor_usage_sync_service_test.dart
```

- [ ] **Step 2: Strip the seams from `SessionUsageServices`**

Remove the four constructor fields and the four `return SessionUsageServices._(...)`
entries (`loadCursorStatus`, `importCursorCsv`, `syncCursorUsage`,
`clearCursorUsage`), the `_PlaneUsageStores.cursorImport` / `.cursorSync` fields,
and the `cursorHttpClient` parameter. Delete the `_PlaneUsageStores` lines that
construct them — leave every other store untouched.

- [ ] **Step 3: Strip the seams from `SessionUsageCubit`**

Remove the four injected functions, the state fields `cursorStatus`,
`cursorBusy`, `cursorError`, and the methods `loadCursorStatus`,
`importCursorCsv`, `syncCursorUsage`, `clearCursorUsage`. Keep `hasData`,
pricing, and sync state untouched.

- [ ] **Step 4: Remove the Cursor UI**

In `usage_maintenance_dialog.dart`, delete the Cursor section and the params
`cursorStatus`, `cursorBusy`, `onImportCursorCsv`, `onSyncCursor`,
`onClearCursor`. In `session_usage_page.dart`, delete `_importCursorCsv`,
`_syncCursorUsage`, `_clearCursorUsage`, `_pickCursorCsv`, `_cursorErrorText`,
the `onCursor:` argument, and the `file_picker` import if nothing else uses it.

- [ ] **Step 5: Delete the l10n keys**

Remove every `sessionUsageCursor*` key (and its `@` metadata block) from
`app_en.arb` and `app_zh.arb`. Cross-check with
`grep -n "sessionUsageCursor" client/lib/l10n/app_en.arb`; anything still
referenced in code means a usage was missed in Steps 2-4.

- [ ] **Step 6: Let the analyzer find the rest**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: errors listing every remaining reference. Fix them one by one —
`app_shell.dart` (the four cubit arguments and the `cursorHttpClient` argument),
`session_usage_cubit_test.dart`, `usage_maintenance_dialog_test.dart`. Repeat
until clean.

- [ ] **Step 7: Run the tests**

Run: `cd client && dart run tool/run_tests.dart test/cubits/session_usage_cubit_test.dart test/pages/usage/ test/services/usage/ test/services/cursor_usage/`
Expected: PASS.

- [ ] **Step 8: Full suite in the background**

Run: `cd client && dart run tool/run_tests.dart`
Expected: PASS.

- [ ] **Step 9: Commit**

```bash
git add -A client/lib client/test
git commit -m "refactor(cursor-usage): retire the single-account CSV import path"
```

`usage/cursor_import.json` stays on disk and is never read again. Do not add a
deletion step for it.

---

## Notes for the implementer

- `validateCursorUsageAccount` (the `pageSize: 1` probe from the spec) is
  folded into `CursorUsageCoordinator._fillGap`'s `owningUser` binding instead of
  a separate call. A pasted cookie is verified on its first real fetch; a wrong
  cookie fails with `accountMismatch` and the account shows "Token belongs to
  another account". Do not add a second probe request.
- Team accounts: `teamId` is read from the account row and passed to
  `fetchPage`; the coordinator currently passes `0` from `load()`. Wire
  `account.teamId` through when the first team account is actually needed — the
  binding check must be skipped for it.
- Expiry differs by source: a discovered account whose token expired simply
  disappears from the list (the resolver drops expired tokens, and the provider
  home refreshes itself on the next Cursor login), while a manual account stays
  listed with `hasCredential: false` and renders "Expired". Do not add an
  expired-token code path to the resolver for this.
- After Task 12 the session usage page's total means "local sessions plus every
  Cursor account". It is no longer "what ran on this machine". Do not try to
  subtract one from the other: Cursor records requests server-side for every
  client (IDE, CLI, web) and exposes no client field, so the two sets overlap in
  a way neither side can measure.
- Task 12 moves the `app_shell.dart` block written in Task 11 to *above* the
  `SessionUsageServices.forStorage` call. If you implement 11 then 12 in order,
  that move is a cut-and-paste, not a rewrite.
