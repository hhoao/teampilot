# Managed Provider Icons, Master Switch, and Auto Refresh Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enabled Managed Providers show brand icons (first-line aligned), appear in the lower-left status bar, and auto-refresh every 10 minutes; disabling one hides it from the status bar and stops all queries for it.

**Architecture:** Keep `ManagedProvider.enabled` as the master switch. Resolve brand marks with a pure helper + `ProviderBrandIcon`. Drive periodic `ensureFresh` from a small auto-refresh binder in app bootstrap (injectable ticker), not a new JSON field. Official Codex/Claude `staleAfter` becomes 10 minutes.

**Tech Stack:** Flutter/Dart, `flutter_bloc`, existing `ProviderBrandIcon` / `assets/providers/*.svg`, Managed Provider cubits.

## Global Constraints

- Do not add `autoQuery` / `showInStatusBar` fields.
- Do not dart-format all of `client/lib/app/app_shell.dart`.
- l10n only in `client/lib/l10n/app_en.arb` and `app_zh.arb`.
- Do not commit `client/pubspec.lock` unless the task requires a new dependency (it should not).
- Commands run from `client/`: `flutter test <path>`.

## File map

| File | Role |
|---|---|
| `client/lib/widgets/managed_provider/managed_provider_brand_icon.dart` | Pure resolve + brand mark widget |
| `client/test/widgets/managed_provider/managed_provider_brand_icon_test.dart` | Resolver + widget tests |
| `client/lib/pages/managed_providers/managed_provider_list.dart` | Brand icon, first-line align |
| `client/lib/widgets/managed_provider/managed_provider_usage_panel.dart` | Brand icon, first-line align, per-row enable switch |
| `client/lib/widgets/managed_provider/managed_provider_usage_status_item.dart` | Brand icons in status segment |
| `client/lib/pages/managed_providers/managed_provider_editor_sections.dart` | Move enabled switch to basics |
| `client/lib/pages/managed_providers/managed_provider_editor_page.dart` | Pass enabled into basics; drop from advanced |
| `client/lib/services/provider_usage/adapters/codex_official_subscription_client.dart` | `staleAfter` 10 min |
| `client/lib/services/provider_usage/adapters/claude_official_subscription_client.dart` | `staleAfter` 10 min |
| `client/lib/cubits/managed_provider_usage_cubit.dart` | `refreshExpiredEnabled` |
| `client/lib/services/provider_usage/managed_provider_usage_auto_refresh.dart` | Periodic tick + disable cancel |
| `client/lib/app/app_shell.dart` | Start/stop auto-refresh (surgical) |

---

### Task 1: Brand icon resolver

**Files:**
- Create: `client/lib/widgets/managed_provider/managed_provider_brand_icon.dart`
- Test: `client/test/widgets/managed_provider/managed_provider_brand_icon_test.dart`

- [ ] **Step 1: Write the failing resolver tests**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/managed_provider.dart';
import 'package:teampilot/widgets/managed_provider/managed_provider_brand_icon.dart';

ManagedProvider _provider({
  String adapterId = 'fake',
  String name = 'Example',
  String url = 'https://example.test/usage',
}) => ManagedProvider(
  id: 'p1',
  name: name,
  kind: ManagedProviderKind.apiBalance,
  adapterId: adapterId,
  endpointConfig: ManagedProviderEndpointConfig(url: url),
);

void main() {
  test('official Codex uses bundled openai', () {
    expect(
      resolveManagedProviderBrandIcon(
        _provider(
          adapterId: 'official-codex-subscription',
          name: 'Codex',
        ).copyWith(kind: ManagedProviderKind.subscriptionQuota),
      ),
      const ManagedProviderBrandIconSpec.bundled('openai'),
    );
  });

  test('official Claude uses bundled claude', () {
    expect(
      resolveManagedProviderBrandIcon(
        _provider(
          adapterId: 'official-claude-subscription',
          name: 'Claude Code',
        ).copyWith(kind: ManagedProviderKind.subscriptionQuota),
      ),
      const ManagedProviderBrandIconSpec.bundled('claude'),
    );
  });

  test('DeepSeek host or name uses bundled deepseek', () {
    expect(
      resolveManagedProviderBrandIcon(
        _provider(
          adapterId: 'http-json',
          name: 'Other',
          url: 'https://api.deepseek.com/user/balance',
        ),
      ),
      const ManagedProviderBrandIconSpec.bundled('deepseek'),
    );
    expect(
      resolveManagedProviderBrandIcon(
        _provider(adapterId: 'http-json', name: 'DeepSeek'),
      ),
      const ManagedProviderBrandIconSpec.bundled('deepseek'),
    );
  });

  test('https brand.iconUrl wins after adapter maps', () {
    expect(
      resolveManagedProviderBrandIcon(
        _provider().copyWith(
          brand: ManagedProviderBrand(iconUrl: 'https://cdn.example/icon.png'),
        ),
      ),
      const ManagedProviderBrandIconSpec.remote('https://cdn.example/icon.png'),
    );
  });

  test('unknown adapter falls back to initials', () {
    expect(
      resolveManagedProviderBrandIcon(_provider(name: 'Acme')),
      const ManagedProviderBrandIconSpec.initials('Acme'),
    );
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/widgets/managed_provider/managed_provider_brand_icon_test.dart`

Expected: FAIL compiling (`managed_provider_brand_icon.dart` missing).

- [ ] **Step 3: Implement resolver + widget**

```dart
import 'package:flutter/material.dart';

import '../../models/managed_provider.dart';
import '../app_provider/provider_brand_icon.dart';

sealed class ManagedProviderBrandIconSpec {
  const ManagedProviderBrandIconSpec();
  const factory ManagedProviderBrandIconSpec.bundled(String key) =
      ManagedProviderBundledIcon;
  const factory ManagedProviderBrandIconSpec.remote(String url) =
      ManagedProviderRemoteIcon;
  const factory ManagedProviderBrandIconSpec.initials(String name) =
      ManagedProviderInitialsIcon;
}

class ManagedProviderBundledIcon extends ManagedProviderBrandIconSpec {
  const ManagedProviderBundledIcon(this.key);
  final String key;
}

class ManagedProviderRemoteIcon extends ManagedProviderBrandIconSpec {
  const ManagedProviderRemoteIcon(this.url);
  final String url;
}

class ManagedProviderInitialsIcon extends ManagedProviderBrandIconSpec {
  const ManagedProviderInitialsIcon(this.name);
  final String name;
}

ManagedProviderBrandIconSpec resolveManagedProviderBrandIcon(
  ManagedProvider provider,
) {
  final adapter = provider.adapterId.trim();
  if (adapter == 'official-codex-subscription') {
    return const ManagedProviderBrandIconSpec.bundled('openai');
  }
  if (adapter == 'official-claude-subscription') {
    return const ManagedProviderBrandIconSpec.bundled('claude');
  }
  final host = Uri.tryParse(provider.endpointConfig.url)?.host.toLowerCase();
  if (adapter == 'http-json' &&
      (host == 'api.deepseek.com' ||
          provider.name.trim().toLowerCase() == 'deepseek')) {
    return const ManagedProviderBrandIconSpec.bundled('deepseek');
  }
  final iconUrl = provider.brand.iconUrl?.trim() ?? '';
  if (iconUrl.startsWith('https://')) {
    return ManagedProviderBrandIconSpec.remote(iconUrl);
  }
  return ManagedProviderBrandIconSpec.initials(provider.name);
}

class ManagedProviderBrandMark extends StatelessWidget {
  const ManagedProviderBrandMark({
    required this.provider,
    this.size = 20,
    this.showBorder = false,
    super.key,
  });

  final ManagedProvider provider;
  final double size;
  final bool showBorder;

  @override
  Widget build(BuildContext context) {
    final spec = resolveManagedProviderBrandIcon(provider);
    return switch (spec) {
      ManagedProviderBundledIcon(:final key) => ProviderBrandIcon(
        icon: key,
        name: provider.name,
        size: size,
        borderRadius: 4,
        showBorder: showBorder,
      ),
      ManagedProviderRemoteIcon(:final url) => ProviderBrandIcon(
        icon: '',
        name: provider.name,
        size: size,
        borderRadius: 4,
        showBorder: showBorder,
      ), // remote: Image.network(url, errorBuilder: initials via ProviderBrandIcon)
      ManagedProviderInitialsIcon() => ProviderBrandIcon(
        icon: '',
        name: provider.name,
        size: size,
        borderRadius: 4,
        showBorder: showBorder,
      ),
    };
  }
}
```

For `remote`, wrap `Image.network` in the same sized tile as `ProviderBrandIcon`, with `errorBuilder` returning `ProviderBrandIcon(icon: '', name: provider.name, ...)`. Do not throw.

Equality: implement `==` / `hashCode` on spec classes so tests can use `expect(..., const ...)`, or compare with `isA<>()` / field expects if Equatable is easier.

- [ ] **Step 4: Run tests and make sure they pass**

Run: `cd client && flutter test test/widgets/managed_provider/managed_provider_brand_icon_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add client/lib/widgets/managed_provider/managed_provider_brand_icon.dart \
  client/test/widgets/managed_provider/managed_provider_brand_icon_test.dart
git commit -m "feat(managed-provider): resolve bundled brand icons"
```

---

### Task 2: List, panel, and status bar icons + first-line align

**Files:**
- Modify: `client/lib/pages/managed_providers/managed_provider_list.dart`
- Modify: `client/lib/widgets/managed_provider/managed_provider_usage_panel.dart`
- Modify: `client/lib/widgets/managed_provider/managed_provider_usage_status_item.dart`
- Test: `client/test/pages/managed_providers/managed_provider_management_page_test.dart`
- Test: `client/test/widgets/managed_provider/managed_provider_usage_panel_test.dart`
- Test: `client/test/widgets/managed_provider/managed_provider_usage_status_item_test.dart`

- [ ] **Step 1: Write failing widget tests**

Management list: pump a Codex official provider; `find.byKey(Key('managed-provider-brand-p1'))` finds one; `find.byIcon(Icons.account_balance_wallet_outlined)` finds nothing on that card. Alignment:

```dart
final icon = tester.getRect(find.byKey(const Key('managed-provider-brand-p1')));
final name = tester.getRect(find.text('Codex').first);
expect((icon.top - name.top).abs(), lessThanOrEqualTo(1));
```

Panel: same key on the row; two-line row uses `CrossAxisAlignment.start`.

Status item: two enabled providers (Codex + Claude) → `find.byKey(const Key('managed-provider-usage-brand-icons'))` and two brand marks; no wallet icon. One enabled → brand + usage text. Disabled provider is omitted from the segment and panel list (`enabledProviders` already filters; add a test that a disabled row is absent from the panel).

- [ ] **Step 2: Run tests to verify they fail**

Run:

```
cd client && flutter test \
  test/pages/managed_providers/managed_provider_management_page_test.dart \
  test/widgets/managed_provider/managed_provider_usage_panel_test.dart \
  test/widgets/managed_provider/managed_provider_usage_status_item_test.dart
```

Expected: FAIL missing keys / wallet icon still present / alignment > 1px.

- [ ] **Step 3: Implement UI**

List `_ProviderHeader`: replace `CircleAvatar` with

```dart
KeyedSubtree(
  key: Key('managed-provider-brand-${provider.id}'),
  child: ManagedProviderBrandMark(provider: provider, size: 20),
)
```

Header `Row` / compact column: `crossAxisAlignment: CrossAxisAlignment.start` for the identity+icon row.

Panel `_ProviderUsageRow`: same mark at `size: 15`, `crossAxisAlignment: CrossAxisAlignment.start`. Keep the warning icon on the value line.

Status `_SummaryContent`: if `summary.providers == 0`, keep current add label (no brand wall). If 1, one `ManagedProviderBrandMark` (15) + measure text, `CrossAxisAlignment.center`. If >1, `Row(key: Key('managed-provider-usage-brand-icons'), children: brands)` + count. Drop `Icons.account_balance_wallet_outlined`. Keep the warning amber icon when `summary.warning`.

Pass the actual `List<ManagedProvider>` into `_Summary` so marks can render (not just a count).

- [ ] **Step 4: Run tests and make sure they pass**

Same flutter test command. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git commit -m "feat(managed-provider): show brand icons aligned to the name line"
```

---

### Task 3: Official staleAfter = 10 minutes

**Files:**
- Modify: `client/lib/services/provider_usage/adapters/codex_official_subscription_client.dart`
- Modify: `client/lib/services/provider_usage/adapters/claude_official_subscription_client.dart`
- Modify: `client/test/services/provider_usage/official_subscription_adapter_test.dart` if it hard-codes 5 minutes
- Test: `client/test/services/provider_usage/official_subscription_client_test.dart`

- [ ] **Step 1: Write failing assertions**

In both Claude and Codex client tests, after `fetch`:

```dart
expect(response.staleAfter, const Duration(minutes: 10));
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/services/provider_usage/official_subscription_client_test.dart`

Expected: FAIL `Duration:5:00:00.000000` vs `10:00:00.000000`.

- [ ] **Step 3: Change both clients**

Replace `staleAfter: const Duration(minutes: 5)` with `minutes: 10` in:

- `codex_official_subscription_client.dart`
- `claude_official_subscription_client.dart`

Update adapter unit test fixtures that assume 5 minutes.

- [ ] **Step 4: Run tests and make sure they pass**

Run: `cd client && flutter test test/services/provider_usage/official_subscription_client_test.dart test/services/provider_usage/official_subscription_adapter_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git commit -m "fix(managed-provider): mark official usage stale after 10 minutes"
```

---

### Task 4: Auto-refresh binder + disable cancels in-flight work

**Files:**
- Create: `client/lib/services/provider_usage/managed_provider_usage_auto_refresh.dart`
- Test: `client/test/services/provider_usage/managed_provider_usage_auto_refresh_test.dart`
- Modify: `client/lib/cubits/managed_provider_usage_cubit.dart` (add `refreshExpiredEnabled`)
- Modify: `client/lib/app/app_shell.dart` (start/stop only; no full-file format)
- Test: `client/test/cubits/managed_provider_usage_cubit_test.dart`

- [ ] **Step 1: Write failing cubit + binder tests**

Cubit:

```dart
test('refreshExpiredEnabled skips disabled and fresh snapshots', () async {
  await providers.upsert(_provider());
  await providers.upsert(_provider(id: 'disabled', enabled: false));
  await usage.save(_ready()); // staleAt in the future
  final cubit = ManagedProviderUsageCubit(coordinator: coordinator);
  addTearDown(cubit.close);
  await cubit.load();
  await cubit.refreshExpiredEnabled();
  expect(adapter.calls, 0);
});

test('refreshExpiredEnabled queries stale enabled providers', () async {
  await providers.upsert(_provider());
  await usage.save(_ready(staleAt: 50)); // now=100
  ...
  await cubit.refreshExpiredEnabled();
  expect(adapter.calls, 1);
});
```

Binder (inject fake periodic):

```dart
test('tick calls refreshExpiredEnabled only while started', () async {
  var ticks = 0;
  late void Function() fire;
  final binder = ManagedProviderUsageAutoRefresh(
    usage: usageCubit,
    providers: providerCubit,
    startPeriodic: (callback, interval) {
      expect(interval, const Duration(minutes: 10));
      fire = callback;
      return Object();
    },
    stopPeriodic: (_) {},
  );
  binder.start();
  fire();
  await Future<void>.delayed(Duration.zero);
  expect(adapter.calls, 1);
});

test('disabling a provider cancels its in-flight ensureFresh', () async {
  final gate = Completer<ProviderUsageSnapshot>();
  adapter.result = gate.future;
  ...
  final pending = usageCubit.ensureFresh('p1');
  await Future<void>.delayed(Duration.zero);
  await providerCubit.disable('p1');
  // binder listening to provider cubit should cancel
  gate.complete(_ready());
  await pending;
  expect(usageCubit.state.snapshotFor('p1')?.status, isNot(ProviderUsageStatus.ready));
});
```

Adjust the cancel assertion to match current `cancelForProvider` behavior (invalidated / previous snapshot retained). The requirement is: disable must call `usage.cancelForProvider(id)` and later `refreshAll` / ticks must not hit the adapter for that id.

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd client && flutter test test/cubits/managed_provider_usage_cubit_test.dart test/services/provider_usage/managed_provider_usage_auto_refresh_test.dart`

Expected: FAIL missing `refreshExpiredEnabled` / binder.

- [ ] **Step 3: Implement**

On `ManagedProviderUsageCubit`:

```dart
Future<void> refreshExpiredEnabled() async {
  await load();
  if (isClosed) return;
  await Future.wait([
    for (final provider in _coordinator.providers.where((p) => p.enabled))
      ensureFresh(provider.id),
  ]);
}
```

`ManagedProviderUsageAutoRefresh`:

- `static const interval = Duration(minutes: 10);`
- `start()`: subscribe to `ManagedProviderCubit.stream`; on enabled-id set shrinking, `unawaited(usage.cancelForProvider(id))` for removed ids; start periodic with injected `startPeriodic` defaulting to `Timer.periodic`.
- `stop()` / `dispose()`: cancel timer and subscription.
- First tick is the periodic firing, not an extra immediate fetch (resume already covers launch/foreground).

`TeamPilotApp` / `TeamPilotAppState`:

- Field `ManagedProviderUsageAutoRefresh? _usageAutoRefresh;`
- After `_shell` is assigned successfully, ` _usageAutoRefresh = ManagedProviderUsageAutoRefresh(...)..start();`
- In `dispose`, `_usageAutoRefresh?.dispose()`.
- Keep existing `didChangeAppLifecycleState` → `_refreshExpiredManagedProviders` but implement that helper as `usage.refreshExpiredEnabled()` so resume and the timer share one path.

Do not reformat the rest of `app_shell.dart`.

- [ ] **Step 4: Run tests and make sure they pass**

Run the same cubit + binder tests plus `test/app/app_shell_provider_usage_bootstrap_test.dart`.

Expected: PASS. Close is still ordered and idempotent.

- [ ] **Step 5: Commit**

```bash
git commit -m "feat(managed-provider): auto-refresh enabled usage every 10 minutes"
```

---

### Task 5: Master switch in editor basics and status panel

**Files:**
- Modify: `client/lib/pages/managed_providers/managed_provider_editor_sections.dart`
- Modify: `client/lib/pages/managed_providers/managed_provider_editor_page.dart`
- Modify: `client/lib/widgets/managed_provider/managed_provider_usage_panel.dart`
- Test: `client/test/pages/managed_providers/managed_provider_management_page_test.dart`
- Test: `client/test/widgets/managed_provider/managed_provider_usage_panel_test.dart`

- [ ] **Step 1: Write failing tests**

Editor: open Codex/new editor; `find.byKey(const Key('managed-provider-enabled'))` is visible without expanding Advanced (`find.byKey(Key('managed-provider-section-advanced'))` may stay collapsed). Toggle it, save, expect `providerCubit.state.providers.single.enabled` is false. Advanced section must not contain a second enabled switch (`findsOneWidget` globally).

Panel: enabled row has `Key('managed-provider-usage-enabled-${id}')`. Tapping calls `ManagedProviderCubit.disable` (or enable). After disable, that row disappears from the panel; the management list still shows the card with disabled badge.

- [ ] **Step 2: Run tests to verify they fail**

Run the two test files. Expected: FAIL (enabled still only in Advanced; panel has no switch).

- [ ] **Step 3: Implement**

`ManagedProviderBasicsSection`: add `enabled` + `onEnabledChanged`. After the name field:

```dart
if (schema.hasField('enabled'))
  SwitchListTile.adaptive(
    key: const Key('managed-provider-enabled'),
    contentPadding: EdgeInsets.zero,
    title: Text(l10n.managedProvidersEnabledTitle),
    subtitle: Text(l10n.managedProvidersEnabledSubtitle),
    value: enabled,
    onChanged: onEnabledChanged,
  ),
```

`ManagedProviderAdvancedSection`: delete the enabled `SwitchListTile`.

`ManagedProviderEditorPage`: pass `_enabled` / `_setEnabled` into basics; stop passing them into advanced. `_advancedInitiallyExpanded` no longer treats `!provider.enabled` as a reason to expand.

Panel `_ProviderUsageRow`: add a compact switch/icon button that calls `context.read<ManagedProviderCubit>().disable/enable`. Tooltip uses existing enable/disable l10n. The binder from Task 4 cancels in-flight queries.

- [ ] **Step 4: Run tests and make sure they pass**

```
cd client && flutter test \
  test/pages/managed_providers/managed_provider_management_page_test.dart \
  test/widgets/managed_provider/managed_provider_usage_panel_test.dart \
  test/widgets/managed_provider/managed_provider_usage_status_item_test.dart \
  test/cubits/managed_provider_usage_cubit_test.dart \
  test/services/provider_usage/managed_provider_usage_auto_refresh_test.dart \
  test/widgets/managed_provider/managed_provider_brand_icon_test.dart \
  test/services/provider_usage/official_subscription_client_test.dart
```

Expected: All PASS.

- [ ] **Step 5: Commit**

```bash
git commit -m "feat(managed-provider): surface enabled as the status-bar master switch"
```

---

## Spec coverage

| Spec item | Task |
|---|---|
| Brand resolve order (Codex/Claude/DeepSeek/url/initials) | 1 |
| List / panel / status bar icons | 2 |
| First-line alignment | 2 |
| Multi-provider status brand row | 2 |
| Disabled omitted from status/panel | 2, 5 |
| Official `staleAfter` 10 min | 3 |
| 10 min `ensureFresh` for enabled only | 4 |
| Resume shares same refresh path | 4 |
| Disable cancels in-flight | 4 |
| Editor basics switch | 5 |
| Panel per-row switch | 5 |
| List pause kept | already exists; 5 tests it still works |
| No extra autoQuery field | all tasks |
| No global toast on auto-refresh fail | 4 (reuse existing queryFailed listener skip) |
