# Provider Usage Status Focus Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show a single focused Managed Provider (icon + primary usage) on the workspace status bar instead of every enabled brand icon plus a count.

**Architecture:** Keep focus selection in a pure Dart helper under `widgets/managed_provider/`. The status segment StatefulWidget remembers the previous snapshots and focused id for the session, recomputes focus on each usage rebuild, and builds the summary from that one provider. Cubit, coordinator, panel, and cache are unchanged.

**Tech Stack:** Flutter/Dart, flutter_bloc, existing `ManagedProvider` / `ProviderUsageSnapshot` models, Flutter widget + unit tests.

## Global Constraints

- UI-layer only: do not change `ManagedProviderUsageCubit`, repositories, adapters, or cache schema.
- Do not persist focus across app restarts.
- Do not animate or rotate through multiple changed providers.
- Warning still considers **all** enabled providers (stale/error/unsupported), even when the focused provider is healthy.
- Status bar Widgets must not perform HTTP I/O.
- Before completion run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && dart run tool/run_tests.dart` (or at least the targeted test files below if iterating).

---

## File Map

| File | Role |
|------|------|
| Create: `client/lib/widgets/managed_provider/managed_provider_usage_status_focus.dart` | Pure focus selection + change detection |
| Create: `client/test/widgets/managed_provider/managed_provider_usage_status_focus_test.dart` | Unit tests for the helper |
| Modify: `client/lib/widgets/managed_provider/managed_provider_usage_status_item.dart` | Session memory + single-provider summary display |
| Modify: `client/test/widgets/managed_provider/managed_provider_usage_status_item_test.dart` | Replace multi-icon expectations; add focus behavior tests |

---

### Task 1: Pure focus helper

**Files:**
- Create: `client/lib/widgets/managed_provider/managed_provider_usage_status_focus.dart`
- Test: `client/test/widgets/managed_provider/managed_provider_usage_status_focus_test.dart`

**Interfaces:**
- Consumes: `ManagedProvider`, `ProviderUsageSnapshot`, `ProviderUsageStatus`, `ProviderUsageMeasure`
- Produces:
  - `String? resolveManagedProviderUsageFocus({required List<ManagedProvider> enabledProviders, required Map<String, ProviderUsageSnapshot> currentSnapshots, required Map<String, ProviderUsageSnapshot> previousSnapshots, String? currentFocusId})`
  - Returns `null` when `enabledProviders` is empty; otherwise a provider id from the enabled list

- [ ] **Step 1: Write the failing unit tests**

Create `client/test/widgets/managed_provider/managed_provider_usage_status_focus_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/managed_provider.dart';
import 'package:teampilot/models/provider_usage_snapshot.dart';
import 'package:teampilot/widgets/managed_provider/managed_provider_usage_status_focus.dart';

ManagedProvider _p(String id) => ManagedProvider(
      id: id,
      name: id,
      kind: ManagedProviderKind.apiBalance,
      adapterId: 'fake',
      endpointConfig: ManagedProviderEndpointConfig(
        url: 'https://example.test/usage',
      ),
    );

ProviderUsageSnapshot _snap(
  String id, {
  String remaining = '10',
  int fetchedAt = 100,
  ProviderUsageStatus status = ProviderUsageStatus.ready,
}) =>
    ProviderUsageSnapshot(
      providerId: id,
      status: status,
      fetchedAt: fetchedAt,
      measures: [
        ProviderUsageMeasure(
          label: 'Balance',
          kind: ProviderUsageMeasureKind.balance,
          remaining: remaining,
          unit: 'USD',
        ),
      ],
    );

void main() {
  test('empty enabled list returns null', () {
    expect(
      resolveManagedProviderUsageFocus(
        enabledProviders: const [],
        currentSnapshots: const {},
        previousSnapshots: const {},
        currentFocusId: null,
      ),
      isNull,
    );
  });

  test('cold start with no snapshots picks first enabled', () {
    expect(
      resolveManagedProviderUsageFocus(
        enabledProviders: [_p('a'), _p('b')],
        currentSnapshots: const {},
        previousSnapshots: const {},
        currentFocusId: null,
      ),
      'a',
    );
  });

  test('cold start picks max fetchedAt', () {
    expect(
      resolveManagedProviderUsageFocus(
        enabledProviders: [_p('a'), _p('b')],
        currentSnapshots: {
          'a': _snap('a', fetchedAt: 100),
          'b': _snap('b', fetchedAt: 200),
        },
        previousSnapshots: const {},
        currentFocusId: null,
      ),
      'b',
    );
  });

  test('single changed provider becomes focus', () {
    expect(
      resolveManagedProviderUsageFocus(
        enabledProviders: [_p('a'), _p('b')],
        currentSnapshots: {
          'a': _snap('a', remaining: '9', fetchedAt: 110),
          'b': _snap('b', remaining: '10', fetchedAt: 100),
        },
        previousSnapshots: {
          'a': _snap('a', remaining: '10', fetchedAt: 100),
          'b': _snap('b', remaining: '10', fetchedAt: 100),
        },
        currentFocusId: 'b',
      ),
      'a',
    );
  });

  test('multiple changes pick max fetchedAt', () {
    expect(
      resolveManagedProviderUsageFocus(
        enabledProviders: [_p('a'), _p('b')],
        currentSnapshots: {
          'a': _snap('a', remaining: '1', fetchedAt: 150),
          'b': _snap('b', remaining: '2', fetchedAt: 200),
        },
        previousSnapshots: {
          'a': _snap('a', remaining: '10', fetchedAt: 100),
          'b': _snap('b', remaining: '10', fetchedAt: 100),
        },
        currentFocusId: 'a',
      ),
      'b',
    );
  });

  test('equal fetchedAt among changes picks later enabled list order', () {
    expect(
      resolveManagedProviderUsageFocus(
        enabledProviders: [_p('a'), _p('b')],
        currentSnapshots: {
          'a': _snap('a', remaining: '1', fetchedAt: 200),
          'b': _snap('b', remaining: '2', fetchedAt: 200),
        },
        previousSnapshots: {
          'a': _snap('a', remaining: '10', fetchedAt: 100),
          'b': _snap('b', remaining: '10', fetchedAt: 100),
        },
        currentFocusId: 'a',
      ),
      'b',
    );
  });

  test('no change keeps current focus when still enabled', () {
    expect(
      resolveManagedProviderUsageFocus(
        enabledProviders: [_p('a'), _p('b')],
        currentSnapshots: {
          'a': _snap('a', remaining: '10', fetchedAt: 100),
          'b': _snap('b', remaining: '10', fetchedAt: 100),
        },
        previousSnapshots: {
          'a': _snap('a', remaining: '10', fetchedAt: 100),
          'b': _snap('b', remaining: '10', fetchedAt: 100),
        },
        currentFocusId: 'a',
      ),
      'a',
    );
  });

  test('disabled focus falls back to cold-start rules', () {
    expect(
      resolveManagedProviderUsageFocus(
        enabledProviders: [_p('b')],
        currentSnapshots: {
          'b': _snap('b', fetchedAt: 100),
        },
        previousSnapshots: {
          'a': _snap('a', fetchedAt: 50),
          'b': _snap('b', fetchedAt: 100),
        },
        currentFocusId: 'a',
      ),
      'b',
    );
  });

  test('new snapshot absent-to-present counts as change', () {
    expect(
      resolveManagedProviderUsageFocus(
        enabledProviders: [_p('a'), _p('b')],
        currentSnapshots: {
          'a': _snap('a', fetchedAt: 100),
          'b': _snap('b', fetchedAt: 120),
        },
        previousSnapshots: {
          'a': _snap('a', fetchedAt: 100),
        },
        currentFocusId: 'a',
      ),
      'b',
    );
  });

  test('status change counts as change', () {
    expect(
      resolveManagedProviderUsageFocus(
        enabledProviders: [_p('a'), _p('b')],
        currentSnapshots: {
          'a': _snap('a', status: ProviderUsageStatus.stale, fetchedAt: 110),
          'b': _snap('b', fetchedAt: 100),
        },
        previousSnapshots: {
          'a': _snap('a', status: ProviderUsageStatus.ready, fetchedAt: 100),
          'b': _snap('b', fetchedAt: 100),
        },
        currentFocusId: 'b',
      ),
      'a',
    );
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
cd client && flutter test test/widgets/managed_provider/managed_provider_usage_status_focus_test.dart
```

Expected: FAIL — library / `resolveManagedProviderUsageFocus` not found.

- [ ] **Step 3: Implement the helper**

Create `client/lib/widgets/managed_provider/managed_provider_usage_status_focus.dart` (no Flutter imports):

```dart
import '../../models/managed_provider.dart';
import '../../models/provider_usage_snapshot.dart';

/// Picks which enabled Managed Provider the status bar should show.
String? resolveManagedProviderUsageFocus({
  required List<ManagedProvider> enabledProviders,
  required Map<String, ProviderUsageSnapshot> currentSnapshots,
  required Map<String, ProviderUsageSnapshot> previousSnapshots,
  String? currentFocusId,
}) {
  if (enabledProviders.isEmpty) return null;

  final enabledIds = <String>{
    for (final p in enabledProviders) p.id,
  };

  final changedIds = <String>[];
  for (final provider in enabledProviders) {
    final id = provider.id;
    final current = currentSnapshots[id];
    final previous = previousSnapshots[id];
    if (_snapshotChanged(previous, current)) {
      changedIds.add(id);
    }
  }

  if (changedIds.isNotEmpty) {
    return _pickByFetchedAtThenListOrder(
      candidates: changedIds,
      enabledProviders: enabledProviders,
      snapshots: currentSnapshots,
    );
  }

  final focus = currentFocusId?.trim();
  if (focus != null && focus.isNotEmpty && enabledIds.contains(focus)) {
    return focus;
  }

  return _coldStartFocus(
    enabledProviders: enabledProviders,
    snapshots: currentSnapshots,
  );
}

String _coldStartFocus({
  required List<ManagedProvider> enabledProviders,
  required Map<String, ProviderUsageSnapshot> snapshots,
}) {
  final withSnapshots = <String>[
    for (final p in enabledProviders)
      if (snapshots.containsKey(p.id)) p.id,
  ];
  if (withSnapshots.isEmpty) return enabledProviders.first.id;
  return _pickByFetchedAtThenListOrder(
    candidates: withSnapshots,
    enabledProviders: enabledProviders,
    snapshots: snapshots,
  );
}

String _pickByFetchedAtThenListOrder({
  required List<String> candidates,
  required List<ManagedProvider> enabledProviders,
  required Map<String, ProviderUsageSnapshot> snapshots,
}) {
  final order = <String, int>{
    for (var i = 0; i < enabledProviders.length; i++)
      enabledProviders[i].id: i,
  };
  final sorted = [...candidates]..sort((a, b) {
    final fa = snapshots[a]?.fetchedAt ?? -1;
    final fb = snapshots[b]?.fetchedAt ?? -1;
    final byFetched = fa.compareTo(fb);
    if (byFetched != 0) return byFetched;
    return (order[a] ?? 0).compareTo(order[b] ?? 0);
  });
  return sorted.last;
}

bool _snapshotChanged(
  ProviderUsageSnapshot? previous,
  ProviderUsageSnapshot? current,
) {
  if (current == null) return false;
  if (previous == null) return true;
  if (previous.status != current.status) return true;
  return !_primaryMeasuresEqual(
    previous.measures.isEmpty ? null : previous.measures.first,
    current.measures.isEmpty ? null : current.measures.first,
  );
}

bool _primaryMeasuresEqual(
  ProviderUsageMeasure? a,
  ProviderUsageMeasure? b,
) {
  if (identical(a, b)) return true;
  if (a == null || b == null) return a == b;
  return a.remaining == b.remaining &&
      a.used == b.used &&
      a.total == b.total &&
      a.unit == b.unit &&
      a.currency == b.currency;
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd client && flutter test test/widgets/managed_provider/managed_provider_usage_status_focus_test.dart
```

Expected: All tests PASS.

- [ ] **Step 5: Commit**

```bash
git add client/lib/widgets/managed_provider/managed_provider_usage_status_focus.dart \
  client/test/widgets/managed_provider/managed_provider_usage_status_focus_test.dart
git commit -m "$(cat <<'EOF'
feat(managed-providers): add status-bar usage focus resolver

EOF
)"
```

---

### Task 2: Wire status item to single focused provider

**Files:**
- Modify: `client/lib/widgets/managed_provider/managed_provider_usage_status_item.dart`
- Modify: `client/test/widgets/managed_provider/managed_provider_usage_status_item_test.dart`

**Interfaces:**
- Consumes: `resolveManagedProviderUsageFocus` from Task 1
- Produces: status segment showing one brand + focused usage label; warning still scans all enabled providers

- [ ] **Step 1: Update widget tests (fail first)**

In `client/test/widgets/managed_provider/managed_provider_usage_status_item_test.dart`:

1. Replace the test `two enabled providers show brand-icons row and no wallet icon` with:

```dart
testWidgets(
  'two enabled providers show one focused brand and usage, not icon row',
  (tester) async {
    final codex = ManagedProvider(
      id: 'p1',
      name: 'Codex',
      kind: ManagedProviderKind.subscriptionQuota,
      adapterId: 'official-codex-subscription',
      endpointConfig: ManagedProviderEndpointConfig(
        url: 'https://example.test/usage',
      ),
    );
    final claude = ManagedProvider(
      id: 'p2',
      name: 'Claude',
      kind: ManagedProviderKind.subscriptionQuota,
      adapterId: 'official-claude-subscription',
      endpointConfig: ManagedProviderEndpointConfig(
        url: 'https://example.test/usage',
      ),
    );
    await pumpItem(
      tester,
      providers: [codex, claude],
      snapshots: {
        'p1': ProviderUsageSnapshot(
          providerId: 'p1',
          status: ProviderUsageStatus.ready,
          fetchedAt: 100,
          measures: [
            ProviderUsageMeasure(
              label: 'Balance',
              kind: ProviderUsageMeasureKind.balance,
              remaining: '12.50',
              unit: 'USD',
            ),
          ],
        ),
        'p2': ProviderUsageSnapshot(
          providerId: 'p2',
          status: ProviderUsageStatus.ready,
          fetchedAt: 200,
          measures: [
            ProviderUsageMeasure(
              label: 'Balance',
              kind: ProviderUsageMeasureKind.balance,
              remaining: '99.00',
              unit: 'USD',
            ),
          ],
        ),
      },
    );

    expect(
      find.byKey(const Key('managed-provider-usage-brand-icons')),
      findsNothing,
    );
    expect(find.byKey(const Key('managed-provider-brand-p2')), findsOneWidget);
    expect(find.byKey(const Key('managed-provider-brand-p1')), findsNothing);
    expect(find.text('99.00 USD'), findsOneWidget);
    expect(find.text('2'), findsNothing);
    expect(find.byIcon(Icons.account_balance_wallet_outlined), findsNothing);
  },
);
```

2. Add sequential-change test:

```dart
testWidgets('focus follows last changed provider across refreshes', (
  tester,
) async {
  final a = _provider(id: 'p1', name: 'A');
  final b = _provider(id: 'p2', name: 'B');
  await pumpItem(
    tester,
    providers: [a, b],
    snapshots: {
      'p1': ProviderUsageSnapshot(
        providerId: 'p1',
        status: ProviderUsageStatus.ready,
        fetchedAt: 100,
        measures: [
          ProviderUsageMeasure(
            label: 'Balance',
            kind: ProviderUsageMeasureKind.balance,
            remaining: '10',
            unit: 'USD',
          ),
        ],
      ),
      'p2': ProviderUsageSnapshot(
        providerId: 'p2',
        status: ProviderUsageStatus.ready,
        fetchedAt: 100,
        measures: [
          ProviderUsageMeasure(
            label: 'Balance',
            kind: ProviderUsageMeasureKind.balance,
            remaining: '20',
            unit: 'USD',
          ),
        ],
      ),
    },
  );
  // Cold start: equal fetchedAt → later list order → p2
  expect(find.byKey(const Key('managed-provider-brand-p2')), findsOneWidget);
  expect(find.text('20 USD'), findsOneWidget);

  usageCubit.emit(
    ManagedProviderUsageState(
      status: ManagedProviderUsageLoadStatus.ready,
      snapshots: {
        'p1': ProviderUsageSnapshot(
          providerId: 'p1',
          status: ProviderUsageStatus.ready,
          fetchedAt: 150,
          measures: [
            ProviderUsageMeasure(
              label: 'Balance',
              kind: ProviderUsageMeasureKind.balance,
              remaining: '9',
              unit: 'USD',
            ),
          ],
        ),
        'p2': ProviderUsageSnapshot(
          providerId: 'p2',
          status: ProviderUsageStatus.ready,
          fetchedAt: 100,
          measures: [
            ProviderUsageMeasure(
              label: 'Balance',
              kind: ProviderUsageMeasureKind.balance,
              remaining: '20',
              unit: 'USD',
            ),
          ],
        ),
      },
    ),
  );
  await tester.pump();
  expect(find.byKey(const Key('managed-provider-brand-p1')), findsOneWidget);
  expect(find.text('9 USD'), findsOneWidget);

  usageCubit.emit(
    ManagedProviderUsageState(
      status: ManagedProviderUsageLoadStatus.ready,
      snapshots: {
        'p1': ProviderUsageSnapshot(
          providerId: 'p1',
          status: ProviderUsageStatus.ready,
          fetchedAt: 150,
          measures: [
            ProviderUsageMeasure(
              label: 'Balance',
              kind: ProviderUsageMeasureKind.balance,
              remaining: '9',
              unit: 'USD',
            ),
          ],
        ),
        'p2': ProviderUsageSnapshot(
          providerId: 'p2',
          status: ProviderUsageStatus.ready,
          fetchedAt: 160,
          measures: [
            ProviderUsageMeasure(
              label: 'Balance',
              kind: ProviderUsageMeasureKind.balance,
              remaining: '19',
              unit: 'USD',
            ),
          ],
        ),
      },
    ),
  );
  await tester.pump();
  expect(find.byKey(const Key('managed-provider-brand-p2')), findsOneWidget);
  expect(find.text('19 USD'), findsOneWidget);
});
```

3. Keep tests for single provider, disabled omit, warning, empty, manage navigation. Remove or update any assertion that required `managed-provider-usage-brand-icons` for two providers.

- [ ] **Step 2: Run the status-item tests and confirm the new cases fail**

```bash
cd client && flutter test test/widgets/managed_provider/managed_provider_usage_status_item_test.dart
```

Expected: new multi-provider / focus tests FAIL (still shows icon row and/or `"2"`).

- [ ] **Step 3: Wire the status segment**

In `managed_provider_usage_status_item.dart`:

1. Import the focus helper.
2. On `_ManagedProviderUsageStatusSegmentState`, add:

```dart
Map<String, ProviderUsageSnapshot> _previousSnapshots = const {};
String? _focusedProviderId;
```

3. Inside the usage `BlocBuilder` builder, before building the UI:

```dart
final providers = providerState.enabledProviders;
final nextFocus = resolveManagedProviderUsageFocus(
  enabledProviders: providers,
  currentSnapshots: usageState.snapshots,
  previousSnapshots: _previousSnapshots,
  currentFocusId: _focusedProviderId,
);
_focusedProviderId = nextFocus;
_previousSnapshots = Map<String, ProviderUsageSnapshot>.unmodifiable(
  usageState.snapshots,
);
final summary = _Summary.from(
  context,
  providers,
  usageState,
  focusedProviderId: nextFocus,
);
```

**Important:** Prefer updating `_previousSnapshots` / `_focusedProviderId` during build only when values actually change, without calling `setState` from `build`. If that triggers lint/runtime issues, move the assignment into a post-frame callback that `setState`s only when the focused id changes.

4. Change `_Summary.from` to accept `String? focusedProviderId` and:

- Keep empty-providers branch unchanged.
- Compute `warning` from **all** `providers` (unchanged).
- Compute `loading` unchanged.
- Resolve display provider:

```dart
ManagedProvider? focused;
if (focusedProviderId != null) {
  for (final p in providers) {
    if (p.id == focusedProviderId) {
      focused = p;
      break;
    }
  }
}
focused ??= providers.isEmpty ? null : providers.first;
final displayList =
    focused == null ? const <ManagedProvider>[] : <ManagedProvider>[focused];
final label =
    focused == null ? '—' : _singleLabel(focused, usageState);
```

- Set `providerList: displayList` (length 0 or 1 — never the full multi list).

5. In `_SummaryContent`, delete the `summary.providerList.length > 1` multi-icon `Row` branch. Keep: loading spinner → single brand → wallet empty.

6. Ensure compact mode still shows the usage text when a focused provider exists (`providerList.length == 1`).

- [ ] **Step 4: Run widget tests**

```bash
cd client && flutter test test/widgets/managed_provider/managed_provider_usage_status_item_test.dart
```

Expected: All PASS.

- [ ] **Step 5: Run focus helper + analyze touchpoints**

```bash
cd client && flutter test \
  test/widgets/managed_provider/managed_provider_usage_status_focus_test.dart \
  test/widgets/managed_provider/managed_provider_usage_status_item_test.dart \
  && flutter analyze --no-fatal-infos --no-fatal-warnings \
  lib/widgets/managed_provider/managed_provider_usage_status_focus.dart \
  lib/widgets/managed_provider/managed_provider_usage_status_item.dart
```

Expected: tests PASS; analyze clean for those files.

- [ ] **Step 6: Commit**

```bash
git add client/lib/widgets/managed_provider/managed_provider_usage_status_item.dart \
  client/test/widgets/managed_provider/managed_provider_usage_status_item_test.dart
git commit -m "$(cat <<'EOF'
feat(managed-providers): show single changed provider on status bar

EOF
)"
```

---

## Spec coverage self-check

| Spec requirement | Task |
|------------------|------|
| Single icon + usage value | Task 2 |
| Remove multi-icon row / count label | Task 2 |
| Focus = changed vs previous | Task 1 |
| Multi-change → max `fetchedAt`, tie → later list | Task 1 |
| No change → keep focus | Task 1 |
| Cold start → max fetchedAt / first | Task 1 |
| Focus disabled → reselect | Task 1 |
| Warning across all enabled | Task 2 (`_Summary.from`) |
| Panel / cubit unchanged | Both (no edits) |
| Helper unit tests | Task 1 |
| Widget focus tests | Task 2 |
