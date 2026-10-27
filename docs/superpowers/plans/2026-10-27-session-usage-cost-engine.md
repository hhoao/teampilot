# Session Usage Cost Engine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Calculate and display USD cost for cached token usage using a versioned built-in price catalog plus per-home-plane user overrides.

**Architecture:** Add a pure pricing model, catalog, and calculator. Load user rules from `usage/pricing.json`, merge them with built-in defaults, and pass the catalog through aggregation. Add cost fields to summary/groups/table, a separate cost card, and a pricing editor dialog. Extract Codex model IDs from `turn_context` so Codex events can be priced.

**Tech Stack:** Flutter, `equatable`, existing `Filesystem`/`HomeStorage`, `flutter_bloc`, `dart run tool/run_tests.dart`.

## Global Constraints

- Work in `/home/hhoa/git/hhoa/teampilot` on `main`.
- Never run `flutter test` directly. Use `dart run tool/run_tests.dart <paths>`.
- Do not use `git add -A` or `git commit -a`.
- Do not touch pre-existing user changes, especially:
  - `client/lib/pages/usage/widgets/usage_summary_cards.dart`
  - `client/test/pages/usage/usage_summary_cards_test.dart`
  - chat/work-path/shared_ui/user changes
- Cost unit is micro-USD; price rates are USD per 1M tokens.
- CLI-reported `costMicroUsd` wins over table pricing.
- Unknown models stay unpriced; never show `$0.00` for them.
- No currency conversion, external pricing API, or event rewrites.
- Pricing edits recompute from cached events only; no transcript scan.

## File Map

| File | Action | Responsibility |
|---|---|---|
| `client/lib/models/session_usage_pricing.dart` | Create | Rules, catalog, cost result, normalization |
| `client/lib/models/session_usage_pricing_defaults.dart` | Create | Built-in reference rules |
| `client/lib/services/usage/usage_cost_calculator.dart` | Create | Pure cost lookup/calculation |
| `client/lib/services/usage/usage_pricing_store.dart` | Create | Pricing load result + store port |
| `client/lib/services/usage/json_usage_pricing_store.dart` | Create | `usage/pricing.json` persistence |
| `client/lib/services/cli/codex/capabilities/usage/session_usage.dart` | Modify | Extract `turn_context.model` |
| `client/lib/services/usage/usage_aggregator.dart` | Modify | Cost totals on summary/groups |
| `client/lib/models/session_usage_dashboard.dart` | Modify | Cost fields |
| `client/lib/app/session_usage_services.dart` | Modify | `loadPricing`/`savePricing` |
| `client/lib/cubits/session_usage_cubit.dart` | Modify | Pricing state/load/save/reset |
| `client/lib/pages/usage/session_usage_page.dart` | Modify | Cost card and pricing action |
| `client/lib/pages/usage/widgets/usage_cost_card.dart` | Create | Cost summary card |
| `client/lib/pages/usage/widgets/usage_detail_table.dart` | Modify | Cost column/unpriced rows |
| `client/lib/pages/usage/usage_pricing_dialog.dart` | Create | Structured price editor |
| `client/lib/pages/usage/usage_format.dart` | Modify | Cost formatting |
| `client/lib/utils/ui/app_keys.dart` | Modify | Cost/pricing keys |
| `client/lib/l10n/app_en.arb`, `app_zh.arb` | Modify | Cost/pricing strings |
| tests | Create/modify | Model, calculator, store, aggregator, cubit, Codex, UI |

---

## Task 1: Pricing model, defaults, and calculator

**Files:**
- Create: `client/lib/models/session_usage_pricing.dart`
- Create: `client/lib/models/session_usage_pricing_defaults.dart`
- Create: `client/lib/services/usage/usage_cost_calculator.dart`
- Test: `client/test/models/session_usage_pricing_test.dart`
- Test: `client/test/services/usage/usage_cost_calculator_test.dart`

**Interfaces:**
- Produces: `UsagePriceSource`, `UsageCostKind`, `UsagePriceRule`, `UsageCost`, `UsagePricingCatalog`, `usageNormalizeModelId`
- Produces: `usageBuiltInPricingRules`, `calculateUsageCost`

- [ ] **Step 1: Write failing model tests**

Create `client/test/models/session_usage_pricing_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/session_usage_pricing.dart';

UsagePriceRule _rule({
  required String model,
  double input = 1,
  double output = 2,
  double cacheRead = 0.1,
  double cacheWrite = 1.25,
  double? cacheWrite1h,
  int effectiveFromMs = 0,
  UsagePriceSource source = UsagePriceSource.user,
}) => UsagePriceRule(
  model: model,
  inputPerMillion: input,
  outputPerMillion: output,
  cacheReadPerMillion: cacheRead,
  cacheWritePerMillion: cacheWrite,
  cacheWrite1hPerMillion: cacheWrite1h,
  effectiveFromMs: effectiveFromMs,
  source: source,
);

void main() {
  test('normalizes case and date suffixes', () {
    expect(usageNormalizeModelId(' Claude-Sonnet-4-5-20250929 '),
        'claude-sonnet-4-5');
    expect(usageNormalizeModelId('gpt-5.4'), 'gpt-5.4');
    expect(usageNormalizeModelId('claude-3-5-sonnet-2024-10-22'),
        'claude-3-5-sonnet');
  });

  test('picks the latest rule not after the event timestamp', () {
    final catalog = UsagePricingCatalog(
      builtInRules: const [],
      userRules: [
        _rule(model: 'm', input: 1, effectiveFromMs: 100),
        _rule(model: 'm', input: 2, effectiveFromMs: 200),
      ],
    );

    expect(catalog.ruleFor(model: 'm', timestampMs: 99), isNull);
    expect(catalog.ruleFor(model: 'm', timestampMs: 150)?.inputPerMillion, 1);
    expect(catalog.ruleFor(model: 'm', timestampMs: 250)?.inputPerMillion, 2);
  });

  test('user rule wins at the same effective time', () {
    final catalog = UsagePricingCatalog(
      builtInRules: [
        _rule(
          model: 'm',
          input: 1,
          source: UsagePriceSource.builtIn,
        ),
      ],
      userRules: [_rule(model: 'm', input: 9)],
    );

    expect(catalog.ruleFor(model: 'm', timestampMs: 0)?.inputPerMillion, 9);
  });
}
```

- [ ] **Step 2: Write failing calculator tests**

Create `client/test/services/usage/usage_cost_calculator_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/session_usage.dart';
import 'package:teampilot/models/session_usage_pricing.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/usage/usage_cost_calculator.dart';

SessionUsageEvent _event({
  String model = 'm',
  int input = 1_000_000,
  int output = 1_000_000,
  int cacheRead = 0,
  int cacheCreate = 0,
  int cacheCreate1h = 0,
  UsageInputSemantics semantics = UsageInputSemantics.fresh,
  int? reported,
}) => SessionUsageEvent(
  requestId: 'r',
  cli: CliTool.claude,
  model: model,
  inputTokens: input,
  outputTokens: output,
  cacheReadTokens: cacheRead,
  cacheCreationTokens: cacheCreate,
  cacheCreation1hTokens: cacheCreate1h,
  inputSemantics: semantics,
  timestampMs: 100,
  sessionId: 's',
  costMicroUsd: reported,
);

final _catalog = UsagePricingCatalog(
  builtInRules: const [],
  userRules: [
    UsagePriceRule(
      model: 'm',
      inputPerMillion: 3,
      outputPerMillion: 15,
      cacheReadPerMillion: 0.3,
      cacheWritePerMillion: 3.75,
      cacheWrite1hPerMillion: 6,
      effectiveFromMs: 0,
      source: UsagePriceSource.user,
    ),
  ],
);

void main() {
  test('calculates fresh input, output, cache read and write', () {
    final cost = calculateUsageCost(
      _event(
        input: 1_000_000,
        output: 2_000_000,
        cacheRead: 500_000,
        cacheCreate: 200_000,
        cacheCreate1h: 100_000,
      ),
      _catalog,
    );

    expect(cost.kind, UsageCostKind.priced);
    expect(cost.microUsd, 3_000_000 + 30_000_000 + 150_000 + 375_000 + 600_000);
  });

  test('normalizes total input semantics', () {
    final cost = calculateUsageCost(
      _event(
        input: 1_000_000,
        output: 0,
        cacheRead: 400_000,
        semantics: UsageInputSemantics.total,
      ),
      _catalog,
    );

    expect(cost.microUsd, 600_000 * 3 + 400_000 * 0.3);
  });

  test('reported cost wins', () {
    final cost = calculateUsageCost(_event(reported: 1234), _catalog);
    expect(cost.kind, UsageCostKind.reported);
    expect(cost.microUsd, 1234);
  });

  test('unknown model is unpriced', () {
    final cost = calculateUsageCost(_event(model: 'unknown'), _catalog);
    expect(cost.kind, UsageCostKind.unpriced);
    expect(cost.microUsd, isNull);
  });
}
```

- [ ] **Step 3: Run tests to verify they fail**

```bash
cd client
dart run tool/run_tests.dart \
  test/models/session_usage_pricing_test.dart \
  test/services/usage/usage_cost_calculator_test.dart
```

Expected: compile errors for missing pricing types and calculator.

- [ ] **Step 4: Implement the pricing model**

Create `client/lib/models/session_usage_pricing.dart`:

```dart
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

enum UsagePriceSource { builtIn, user }

enum UsageCostKind { reported, priced, unpriced }

String usageNormalizeModelId(String raw) {
  var value = raw.trim().toLowerCase();
  value = value.replaceFirst(RegExp(r'-\d{4}-\d{2}-\d{2}$'), '');
  value = value.replaceFirst(RegExp(r'-\d{8}$'), '');
  return value.trim();
}

@immutable
final class UsagePriceRule extends Equatable {
  const UsagePriceRule({
    required this.model,
    required this.inputPerMillion,
    required this.outputPerMillion,
    this.cacheReadPerMillion = 0,
    this.cacheWritePerMillion = 0,
    this.cacheWrite1hPerMillion,
    this.effectiveFromMs = 0,
    this.source = UsagePriceSource.user,
  });

  final String model;
  final double inputPerMillion;
  final double outputPerMillion;
  final double cacheReadPerMillion;
  final double cacheWritePerMillion;
  final double? cacheWrite1hPerMillion;
  final int effectiveFromMs;
  final UsagePriceSource source;

  String get normalizedModel => usageNormalizeModelId(model);

  UsagePriceRule copyWith({
    String? model,
    double? inputPerMillion,
    double? outputPerMillion,
    double? cacheReadPerMillion,
    double? cacheWritePerMillion,
    double? cacheWrite1hPerMillion,
    bool clearCacheWrite1h = false,
    int? effectiveFromMs,
    UsagePriceSource? source,
  }) {
    return UsagePriceRule(
      model: model ?? this.model,
      inputPerMillion: inputPerMillion ?? this.inputPerMillion,
      outputPerMillion: outputPerMillion ?? this.outputPerMillion,
      cacheReadPerMillion: cacheReadPerMillion ?? this.cacheReadPerMillion,
      cacheWritePerMillion:
          cacheWritePerMillion ?? this.cacheWritePerMillion,
      cacheWrite1hPerMillion: clearCacheWrite1h
          ? null
          : (cacheWrite1hPerMillion ?? this.cacheWrite1hPerMillion),
      effectiveFromMs: effectiveFromMs ?? this.effectiveFromMs,
      source: source ?? this.source,
    );
  }

  Map<String, Object?> toJson() => {
    'model': model,
    'inputPerMillion': inputPerMillion,
    'outputPerMillion': outputPerMillion,
    'cacheReadPerMillion': cacheReadPerMillion,
    'cacheWritePerMillion': cacheWritePerMillion,
    if (cacheWrite1hPerMillion != null)
      'cacheWrite1hPerMillion': cacheWrite1hPerMillion,
    'effectiveFromMs': effectiveFromMs,
  };

  factory UsagePriceRule.fromJson(Map<String, Object?> json) {
    return UsagePriceRule(
      model: '${json['model'] ?? ''}',
      inputPerMillion: (json['inputPerMillion'] as num?)?.toDouble() ?? 0,
      outputPerMillion: (json['outputPerMillion'] as num?)?.toDouble() ?? 0,
      cacheReadPerMillion:
          (json['cacheReadPerMillion'] as num?)?.toDouble() ?? 0,
      cacheWritePerMillion:
          (json['cacheWritePerMillion'] as num?)?.toDouble() ?? 0,
      cacheWrite1hPerMillion:
          (json['cacheWrite1hPerMillion'] as num?)?.toDouble(),
      effectiveFromMs: (json['effectiveFromMs'] as num?)?.toInt() ?? 0,
      source: UsagePriceSource.user,
    );
  }

  @override
  List<Object?> get props => [
    model,
    inputPerMillion,
    outputPerMillion,
    cacheReadPerMillion,
    cacheWritePerMillion,
    cacheWrite1hPerMillion,
    effectiveFromMs,
    source,
  ];
}

@immutable
final class UsageCost extends Equatable {
  const UsageCost({required this.microUsd, required this.kind});

  final int? microUsd;
  final UsageCostKind kind;

  @override
  List<Object?> get props => [microUsd, kind];
}

@immutable
final class UsagePricingCatalog extends Equatable {
  const UsagePricingCatalog({
    this.builtInRules = const [],
    this.userRules = const [],
  });

  factory UsagePricingCatalog.builtIn() => UsagePricingCatalog(
    builtInRules: usageBuiltInPricingRules,
  );

  final List<UsagePriceRule> builtInRules;
  final List<UsagePriceRule> userRules;

  UsagePriceRule? ruleFor({
    required String model,
    required int timestampMs,
  }) {
    final key = usageNormalizeModelId(model);
    if (key.isEmpty) return null;
    UsagePriceRule? best;
    for (final rule in [...userRules, ...builtInRules]) {
      if (rule.normalizedModel != key) continue;
      if (rule.effectiveFromMs > timestampMs) continue;
      if (best == null ||
          rule.effectiveFromMs > best.effectiveFromMs ||
          (rule.effectiveFromMs == best.effectiveFromMs &&
              rule.source == UsagePriceSource.user)) {
        best = rule;
      }
    }
    return best;
  }

  @override
  List<Object?> get props => [builtInRules, userRules];
}
```

`UsagePricingCatalog.builtIn()` imports `usageBuiltInPricingRules` from
`models/session_usage_pricing_defaults.dart`, so the model layer stays free of
service dependencies.

- [ ] **Step 5: Implement built-in defaults**

Create `client/lib/models/session_usage_pricing_defaults.dart`:

```dart
import 'session_usage_pricing.dart';

const usageBuiltInPricingRules = <UsagePriceRule>[
  UsagePriceRule(
    model: 'claude-opus-4-1',
    inputPerMillion: 15,
    outputPerMillion: 75,
    cacheReadPerMillion: 1.5,
    cacheWritePerMillion: 18.75,
    cacheWrite1hPerMillion: 30,
    source: UsagePriceSource.builtIn,
  ),
  UsagePriceRule(
    model: 'claude-opus-4',
    inputPerMillion: 15,
    outputPerMillion: 75,
    cacheReadPerMillion: 1.5,
    cacheWritePerMillion: 18.75,
    cacheWrite1hPerMillion: 30,
    source: UsagePriceSource.builtIn,
  ),
  UsagePriceRule(
    model: 'claude-sonnet-4-5',
    inputPerMillion: 3,
    outputPerMillion: 15,
    cacheReadPerMillion: 0.3,
    cacheWritePerMillion: 3.75,
    cacheWrite1hPerMillion: 6,
    source: UsagePriceSource.builtIn,
  ),
  UsagePriceRule(
    model: 'claude-sonnet-4',
    inputPerMillion: 3,
    outputPerMillion: 15,
    cacheReadPerMillion: 0.3,
    cacheWritePerMillion: 3.75,
    cacheWrite1hPerMillion: 6,
    source: UsagePriceSource.builtIn,
  ),
  UsagePriceRule(
    model: 'claude-haiku-4-5',
    inputPerMillion: 1,
    outputPerMillion: 5,
    cacheReadPerMillion: 0.1,
    cacheWritePerMillion: 1.25,
    cacheWrite1hPerMillion: 2,
    source: UsagePriceSource.builtIn,
  ),
  UsagePriceRule(
    model: 'claude-3-5-sonnet',
    inputPerMillion: 3,
    outputPerMillion: 15,
    cacheReadPerMillion: 0.3,
    cacheWritePerMillion: 3.75,
    cacheWrite1hPerMillion: 6,
    source: UsagePriceSource.builtIn,
  ),
];
```

- [ ] **Step 6: Implement the calculator**

Create `client/lib/services/usage/usage_cost_calculator.dart`:

```dart
import '../../models/session_usage.dart';
import '../../models/session_usage_pricing.dart';

UsageCost calculateUsageCost(
  SessionUsageEvent event,
  UsagePricingCatalog catalog,
) {
  final reported = event.costMicroUsd;
  if (reported != null) {
    return UsageCost(microUsd: reported, kind: UsageCostKind.reported);
  }

  final rule = catalog.ruleFor(
    model: event.model,
    timestampMs: event.timestampMs,
  );
  if (rule == null) {
    return const UsageCost(microUsd: null, kind: UsageCostKind.unpriced);
  }

  final oneHour = event.cacheCreation1hTokens.clamp(
    0,
    event.cacheCreationTokens,
  );
  final regularWrite = event.cacheCreationTokens - oneHour;
  final write1hRate =
      rule.cacheWrite1hPerMillion ?? rule.cacheWritePerMillion;
  final microUsd =
      (event.freshInputTokens * rule.inputPerMillion +
              event.outputTokens * rule.outputPerMillion +
              event.cacheReadTokens * rule.cacheReadPerMillion +
              regularWrite * rule.cacheWritePerMillion +
              oneHour * write1hRate)
          .round();

  return UsageCost(microUsd: microUsd, kind: UsageCostKind.priced);
}
```

- [ ] **Step 7: Run tests and commit**

```bash
cd client
dart run tool/run_tests.dart \
  test/models/session_usage_pricing_test.dart \
  test/services/usage/usage_cost_calculator_test.dart
flutter analyze --no-fatal-infos --no-fatal-warnings
```

Expected: tests pass; no new analyzer diagnostics.

```bash
cd /home/hhoa/git/hhoa/teampilot
git add client/lib/models/session_usage_pricing.dart \
  client/lib/models/session_usage_pricing_defaults.dart \
  client/lib/services/usage/usage_cost_calculator.dart \
  client/test/models/session_usage_pricing_test.dart \
  client/test/services/usage/usage_cost_calculator_test.dart
git commit -m "feat(usage): add pricing catalog and cost calculator" -- \
  client/lib/models/session_usage_pricing.dart \
  client/lib/models/session_usage_pricing_defaults.dart \
  client/lib/services/usage/usage_cost_calculator.dart \
  client/test/models/session_usage_pricing_test.dart \
  client/test/services/usage/usage_cost_calculator_test.dart
```

---

## Task 2: Extract Codex model from `turn_context`

**Files:**
- Modify: `client/lib/services/cli/codex/capabilities/usage/session_usage.dart`
- Test: `client/test/services/cli/registry/capabilities/usage/codex_session_usage_test.dart`

- [ ] **Step 1: Add the failing test**

```dart
  test('reads the model from turn_context for later token events', () async {
    final ctx = _ctx();
    final path = p.join(
      _home,
      'sessions',
      '2026',
      '10',
      '26',
      'rollout-2026-10-26T10-00-00-$_thread.jsonl',
    );
    await ctx.fs.writeString(
      path,
      '${jsonEncode({
        'type': 'turn_context',
        'timestamp': '2026-10-26T10:00:00.000Z',
        'payload': {'turn_id': 't1', 'model': 'gpt-5.4'},
      })}\n'
      '${_tokenCount(last: _usage(input: 10, cached: 2, output: 1))}\n',
    );
    final source = (await const CodexSessionUsageCapability()
        .discoverUsageSources(ctx))
        .single;
    final scan = await const CodexSessionUsageCapability().scanUsageSource(
      ctx: ctx,
      source: source,
      cursor: null,
    );

    expect(scan.events.single.model, 'gpt-5.4');
  });
```

- [ ] **Step 2: Run it to verify failure**

```bash
cd client
dart run tool/run_tests.dart \
  test/services/cli/registry/capabilities/usage/codex_session_usage_test.dart
```

Expected: `model` is empty.

- [ ] **Step 3: Implement model tracking**

In `scanUsageSource`, before the line loop:

```dart
    var currentModel = '';
```

At the start of the line loop after decoding `obj`:

```dart
      if (obj['type'] == 'turn_context') {
        final payloadRaw = obj['payload'];
        if (payloadRaw is Map) {
          final payload = Map<String, Object?>.from(payloadRaw);
          final model = '${payload['model'] ?? ''}'.trim();
          if (model.isNotEmpty) currentModel = model;
        }
        continue;
      }
```

Use `model: currentModel` in the `SessionUsageEvent` instead of `model: ''`.

- [ ] **Step 4: Run tests and commit**

```bash
cd client
dart run tool/run_tests.dart \
  test/services/cli/registry/capabilities/usage/codex_session_usage_test.dart
```

```bash
cd /home/hhoa/git/hhoa/teampilot
git add client/lib/services/cli/codex/capabilities/usage/session_usage.dart \
  client/test/services/cli/registry/capabilities/usage/codex_session_usage_test.dart
git commit -m "feat(usage): capture codex model for pricing" -- \
  client/lib/services/cli/codex/capabilities/usage/session_usage.dart \
  client/test/services/cli/registry/capabilities/usage/codex_session_usage_test.dart
```

---

## Task 3: Pricing storage, services, and cubit

**Files:**
- Create: `client/lib/services/usage/usage_pricing_store.dart`
- Create: `client/lib/services/usage/json_usage_pricing_store.dart`
- Modify: `client/lib/app/session_usage_services.dart`
- Modify: `client/lib/app/app_shell.dart`
- Modify: `client/lib/cubits/session_usage_cubit.dart`
- Test: `client/test/services/usage/json_usage_pricing_store_test.dart`
- Test: `client/test/cubits/session_usage_cubit_test.dart`

**Interfaces:**
- Produces: `UsagePricingLoad`, `UsagePricingStore`, `JsonUsagePricingStore`
- Produces: `SessionUsageServices.loadPricing`, `savePricing`
- Produces: `SessionUsageCubit.pricing`, `pricingSaving`, `pricingCorrupted`, `pricingError`, `savePricing`, `resetPricing`

- [ ] **Step 1: Write store tests**

Use `InMemoryFilesystem` and a temp path. Cover:
- save then load returns user rules and `corrupted == false`;
- corrupt JSON returns empty rules and `corrupted == true`;
- missing file returns empty rules.

Exact test skeleton:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/session_usage_pricing.dart';
import 'package:teampilot/services/usage/json_usage_pricing_store.dart';

import '../../support/in_memory_filesystem.dart';

void main() {
  test('round-trips user rules', () async {
    final fs = InMemoryFilesystem();
    final store = JsonUsagePricingStore(
      fs: fs,
      filePath: '/tp/usage/pricing.json',
    );
    const rule = UsagePriceRule(
      model: 'm',
      inputPerMillion: 1,
      outputPerMillion: 2,
      cacheReadPerMillion: 0.1,
      cacheWritePerMillion: 1.25,
      effectiveFromMs: 0,
    );

    await store.save([rule]);
    final loaded = await store.load();

    expect(loaded.corrupted, isFalse);
    expect(loaded.rules.single.model, 'm');
    expect(loaded.rules.single.inputPerMillion, 1);
  });

  test('corrupt file falls back to empty rules', () async {
    final fs = InMemoryFilesystem();
    await fs.writeString('/tp/usage/pricing.json', '{bad');
    final store = JsonUsagePricingStore(
      fs: fs,
      filePath: '/tp/usage/pricing.json',
    );

    final loaded = await store.load();

    expect(loaded.corrupted, isTrue);
    expect(loaded.rules, isEmpty);
  });
}
```

- [ ] **Step 2: Implement the store port and JSON store**

`usage_pricing_store.dart`:

```dart
import '../../models/session_usage_pricing.dart';

final class UsagePricingLoad {
  const UsagePricingLoad({required this.rules, this.corrupted = false});

  final List<UsagePriceRule> rules;
  final bool corrupted;
}

abstract interface class UsagePricingStore {
  Future<UsagePricingLoad> load();
  Future<void> save(List<UsagePriceRule> rules);
}
```

`json_usage_pricing_store.dart`:

```dart
import 'dart:convert';

import '../../models/session_usage_pricing.dart';
import '../io/filesystem.dart';
import 'usage_pricing_store.dart';

final class JsonUsagePricingStore implements UsagePricingStore {
  JsonUsagePricingStore({required Filesystem fs, required String filePath})
    : _fs = fs,
      _path = filePath;

  final Filesystem _fs;
  final String _path;

  @override
  Future<UsagePricingLoad> load() async {
    final raw = await _fs.readString(_path);
    if (raw == null || raw.trim().isEmpty) {
      return const UsagePricingLoad(rules: []);
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return const UsagePricingLoad(rules: [], corrupted: true);
      }
      final rulesRaw = decoded['rules'];
      if (rulesRaw is! List) {
        return const UsagePricingLoad(rules: [], corrupted: true);
      }
      final rules = <UsagePriceRule>[];
      for (final entry in rulesRaw) {
        if (entry is! Map) continue;
        final rule = UsagePriceRule.fromJson(
          Map<String, Object?>.from(entry),
        );
        if (rule.normalizedModel.isEmpty) continue;
        rules.add(rule);
      }
      return UsagePricingLoad(rules: List.unmodifiable(rules));
    } on Object {
      return const UsagePricingLoad(rules: [], corrupted: true);
    }
  }

  @override
  Future<void> save(List<UsagePriceRule> rules) {
    final payload = {
      'version': 1,
      'updatedAtMs': DateTime.now().millisecondsSinceEpoch,
      'rules': [
        for (final rule in rules)
          if (rule.normalizedModel.isNotEmpty) rule.toJson(),
      ],
    };
    return _fs.atomicWrite(
      _path,
      const JsonEncoder.withIndent('  ').convert(payload),
    );
  }
}
```

- [ ] **Step 3: Wire services**

`SessionUsageServices` add:

```dart
  final Future<UsagePricingLoad> Function() loadPricing;
  final Future<void> Function(List<UsagePriceRule> rules) savePricing;
```

In `forStorage`, construct a store per call:

```dart
    JsonUsagePricingStore newPricingStore() => JsonUsagePricingStore(
      fs: storage.fs,
      filePath: storage.paths.usagePricingFile,
    );
```

Add `usagePricingFile` to `app_paths.dart`:

```dart
  String get usagePricingFile => _ctx.join(usageDir, 'pricing.json');
```

Return:

```dart
      loadPricing: () => newPricingStore().load(),
      savePricing: (rules) => newPricingStore().save(rules),
```

- [ ] **Step 4: Wire cubit state**

Add to `SessionUsageState`:

```dart
    this.pricing = const UsagePricingCatalog(),
    this.pricingSaving = false,
    this.pricingCorrupted = false,
    this.pricingError,
```

Fields, `copyWith` parameters, and `props` entries follow the same pattern.

Constructor gains:

```dart
    Future<UsagePricingLoad> Function()? loadPricing,
    Future<void> Function(List<UsagePriceRule> rules)? savePricing,
```

Fields:

```dart
  final Future<UsagePricingLoad> Function()? _loadPricing;
  final Future<void> Function(List<UsagePriceRule>)? _savePricing;
  UsagePricingCatalog _pricing = const UsagePricingCatalog();
```

In `_loadInternal`, after teams:

```dart
      if (_loadPricing != null) {
        try {
          final loaded = await _loadPricing!();
          _pricing = UsagePricingCatalog(userRules: loaded.rules);
          pricingCorrupted = loaded.corrupted;
        } on Object {
          _pricing = UsagePricingCatalog.builtIn();
          pricingCorrupted = true;
        }
      } else {
        _pricing = UsagePricingCatalog.builtIn();
      }
```

Need `pricingCorrupted` local variable and pass to state. Use a local `var pricingCorrupted = false;` before the try.

In `_computeDashboard`, pass `pricing: _pricing`.

Add:

```dart
  Future<void> savePricing(List<UsagePriceRule> rules) async {
    final saver = _savePricing;
    if (saver == null || state.pricingSaving) return;
    emit(state.copyWith(pricingSaving: true, clearPricingError: true));
    try {
      await saver(rules);
      if (isClosed) return;
      _pricing = UsagePricingCatalog(userRules: rules);
      emit(
        state.copyWith(
          pricing: _pricing,
          pricingSaving: false,
          pricingCorrupted: false,
          dashboard: _computeDashboard(),
          clearPricingError: true,
        ),
      );
    } on Object catch (error) {
      if (isClosed) return;
      emit(state.copyWith(pricingSaving: false, pricingError: '$error'));
    }
  }

  Future<void> resetPricing() => savePricing(const []);
```

`copyWith` needs `clearPricingError`.

- [ ] **Step 5: Wire app shell**

```dart
    final sessionUsageCubit = SessionUsageCubit(
      loadEvents: sessionUsageServices.loadEvents,
      syncAll: sessionUsageServices.syncAll,
      startSync: sessionUsageServices.startSync,
      loadPricing: sessionUsageServices.loadPricing,
      savePricing: sessionUsageServices.savePricing,
      loadSessions: sessionUsageServices.loadSessions,
      loadTeams: sessionUsageServices.loadTeams,
      storageChanges: homeStorage.changes.map<void>((_) {}),
    );
```

- [ ] **Step 6: Add cubit tests and commit**

Add tests:
- load pricing merges user rules into dashboard cost;
- save updates state and recomputes;
- save failure exposes `pricingError`;
- reset clears user rules.

Use `InMemoryFilesystem` plus `JsonUsagePricingStore` for a focused test, or inject fake load/save callbacks.

```bash
cd client
dart run tool/run_tests.dart \
  test/services/usage/json_usage_pricing_store_test.dart \
  test/cubits/session_usage_cubit_test.dart
```

Commit all Task 3 paths explicitly.

---

## Task 4: Cost aggregation

**Files:**
- Modify: `client/lib/models/session_usage_dashboard.dart`
- Modify: `client/lib/services/usage/usage_aggregator.dart`
- Test: `client/test/services/usage/usage_aggregator_test.dart`

- [ ] **Step 1: Add failing aggregator assertions**

Extend the existing aggregator test with:

```dart
  test('calculates priced cost and counts unpriced events', () {
    final dashboard = buildUsageDashboard(
      events: [
        _event(id: 'a', model: 'claude-sonnet-4-5'),
        _event(id: 'b', model: 'unknown-model'),
      ],
      attribution: const UsageAttribution(),
      filter: const UsageFilter(),
      nowMs: _nowMs,
      pricing: UsagePricingCatalog.builtIn(),
    );

    expect(dashboard.summary.pricedEvents, 1);
    expect(dashboard.summary.unpricedEvents, 1);
    expect(dashboard.summary.costMicroUsd, greaterThan(0));
    expect(
      dashboard.rows.single.costMicroUsd,
      dashboard.summary.costMicroUsd,
    );
  });
```

`_event` must accept `model` (add a parameter if it does not already).

- [ ] **Step 2: Add cost fields**

`UsageSummary` add:

```dart
    this.costMicroUsd = 0,
    this.pricedEvents = 0,
    this.unpricedEvents = 0,
```

`UsageGroup` add the same. `UsageCliSlice` may stay token-only.

- [ ] **Step 3: Update aggregator**

`buildUsageDashboard` gains:

```dart
  UsagePricingCatalog pricing = const UsagePricingCatalog(),
```

Pass `pricing` to `_summarize` and `_group`.

In `_summarize`:

```dart
  var cost = 0;
  var priced = 0;
  var unpriced = 0;
  for (final event in events) {
    final unit = calculateUsageCost(event, pricing);
    if (unit.microUsd != null) {
      cost += unit.microUsd!;
      priced++;
    } else {
      unpriced++;
    }
    ...
  }
```

Return the new fields.

In `_GroupAccumulator`, add cost fields and use the calculator in `add`
(pass pricing into the accumulator or calculate before adding):

```dart
final cost = calculateUsageCost(event, pricing);
group.add(event, cost);
```

Update `_GroupAccumulator.add` signature and `build`.

- [ ] **Step 4: Run tests and commit**

```bash
cd client
dart run tool/run_tests.dart test/services/usage/usage_aggregator_test.dart
```

Commit model/aggregator/test paths explicitly.

---

## Task 5: Cost UI and pricing dialog

**Files:**
- Create: `client/lib/pages/usage/widgets/usage_cost_card.dart`
- Create: `client/lib/pages/usage/usage_pricing_dialog.dart`
- Modify: `client/lib/pages/usage/session_usage_page.dart`
- Modify: `client/lib/pages/usage/widgets/usage_detail_table.dart`
- Modify: `client/lib/pages/usage/usage_format.dart`
- Modify: `client/lib/utils/ui/app_keys.dart`
- Modify: l10n ARBs and generated files
- Test: `client/test/pages/usage/session_usage_page_test.dart`
- Test: `client/test/pages/usage/usage_pricing_dialog_test.dart`

- [ ] **Step 1: Add formatters and l10n**

`formatUsageCost(int? microUsd)`:

```dart
String formatUsageCost(int? microUsd) {
  if (microUsd == null) return '—';
  if (microUsd == 0) return r'$0.00';
  if (microUsd < 10000) return r'<$0.01';
  final dollars = microUsd / 1000000;
  if (dollars < 1) return '\$${dollars.toStringAsFixed(4)}';
  return '\$${dollars.toStringAsFixed(2)}';
}
```

Add l10n keys for:
- Cost, priced/unpriced counts, unpriced, manage pricing
- Pricing dialog title/hint/model/input/output/cache read/cache write/1h/effective date
- Add rule, save, reset, invalid price, pricing saved/failed, reset confirmation

- [ ] **Step 2: Cost card**

Create `UsageCostCard` with a card-like container showing:
- `formatUsageCost(summary.pricedEvents == 0 ? null : summary.costMicroUsd)`
- `X priced · Y unpriced`
- partial hint when unpriced > 0
- `Manage pricing` button.

Do not edit `usage_summary_cards.dart`.

- [ ] **Step 3: Add cost to detail table**

Add a `Cost` header and row cell. Width layout: increase table min width by
100 and add a `_costCell` helper. For rows with `pricedEvents == 0`, show
`Unpriced`. For partial rows, show `≥ $x`? Use `formatUsageCost` plus an
asterisk/marker if `unpricedEvents > 0`.

- [ ] **Step 4: Pricing dialog**

Implement a `StatefulWidget` that:
- copies `state.pricing.userRules` into editable drafts;
- uses `TextEditingController`s for model, five rates, effective date;
- validates and constructs `UsagePriceRule`s;
- calls `onSave(rules)` and shows inline errors on failure;
- `Reset` calls `onReset` after confirmation.

Keep the dialog as a page-level helper method that closes on success.

- [ ] **Step 5: Wire page**

- Add `UsageCostCard` after `UsageSummaryCards`.
- Add a `Pricing` action that opens `UsagePricingDialog`.
- Pass `cubit.savePricing` and `cubit.resetPricing`.
- Show a dismissible warning when `state.pricingCorrupted`.

- [ ] **Step 6: Tests and commit**

Add:
- cost card renders total and unpriced count;
- detail table shows Cost and Unpriced;
- pricing dialog adds/saves/deletes a rule;
- reset confirmation removes user rules.

Run:
```bash
cd client
dart run tool/run_tests.dart \
  test/pages/usage/session_usage_page_test.dart \
  test/pages/usage/usage_pricing_dialog_test.dart
```

Commit explicit paths.

---

## Task 6: Verification

```bash
cd client
dart run tool/run_tests.dart \
  test/models/session_usage_pricing_test.dart \
  test/services/usage/usage_cost_calculator_test.dart \
  test/services/usage/json_usage_pricing_store_test.dart \
  test/services/usage/usage_aggregator_test.dart \
  test/cubits/session_usage_cubit_test.dart \
  test/services/cli/registry/capabilities/usage/codex_session_usage_test.dart \
  test/pages/usage/session_usage_page_test.dart \
  test/pages/usage/usage_pricing_dialog_test.dart
flutter analyze --no-fatal-infos --no-fatal-warnings
dart run tool/run_tests.dart
```

Mark this plan complete and commit the checkbox changes.

## Self-Review

- Pricing model/calculator: Task 1.
- Codex model: Task 2.
- Price persistence/services/cubit: Task 3.
- Cost aggregation: Task 4.
- Cost card/table/pricing dialog: Task 5.
- Verification: Task 6.
- No pricing API, FX, event rewrites, or edits to the user-modified summary cards file.
