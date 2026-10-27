# Session Usage Cost Engine

**Date:** 2026-10-27
**Status:** Implemented
**Parent feature:** `docs/superpowers/specs/2026-10-26-agent-cli-usage-tracking-design.md`

## Goal

Turn token events into displayable USD cost. Cost is calculated from a
versioned, editable price catalog, with CLI-reported cost taking precedence.
Unknown models remain visibly unpriced instead of silently becoming zero.

## Scope

- Micro-USD cost calculation for every usage event.
- Built-in reference prices for confirmed common models.
- Per-home-plane user price overrides stored as JSON.
- Cost totals in summary, grouped rows, and the detail table.
- A pricing editor dialog: add, edit, delete, save, reset to defaults.
- Codex model extraction from `turn_context` so Codex events can be priced.
- Cost formatting and unpriced-state UI.

## Non-goals

- Currency conversion or non-USD display.
- Fetching prices from provider APIs.
- Invoice reconciliation, discounts, subscriptions, or credits.
- Rewriting stored `SessionUsageEvent` values.
- Per-message cost display and ACP live cost. Those remain later milestones.

## Decisions

| Decision | Value |
|---|---|
| Cost unit | Integer micro-USD (`1 USD = 1_000_000`) |
| Currency | USD only |
| Price rate unit | USD per 1,000,000 tokens |
| Defaults | Built-in reference list, versioned in code |
| User overrides | `usage/pricing.json` on the current home plane |
| Precedence | CLI-reported `costMicroUsd` > user rule > built-in rule > unpriced |
| Model matching | Normalized exact model ID |
| Historical pricing | Latest rule with `effectiveFromMs <= event.timestampMs` |
| Unknown model | `costMicroUsd = null`, `UsageCostKind.unpriced` |
| Price changes | Recompute from cached events; never rewrite events |
| Pricing edit scope | User rules only; reset removes user rules |
| Codex model | Read `turn_context.payload.model` and attach to later `token_count` events |

## Price model

`models/session_usage_pricing.dart`:

```dart
enum UsagePriceSource { builtIn, user }

enum UsageCostKind { reported, priced, unpriced }

@immutable
final class UsagePriceRule extends Equatable {
  final String model;
  final double inputPerMillion;
  final double outputPerMillion;
  final double cacheReadPerMillion;
  final double cacheWritePerMillion;
  final double? cacheWrite1hPerMillion;
  final int effectiveFromMs;
  final UsagePriceSource source;
}

@immutable
final class UsageCost extends Equatable {
  final int? microUsd;
  final UsageCostKind kind;
}
```

Model normalization:

- Trim and lowercase.
- Remove a trailing `-YYYYMMDD` or `-YYYY-MM-DD` version suffix.
- Example: `claude-sonnet-4-5-20250929` → `claude-sonnet-4-5`.
- Matching is exact after normalization. Users can add aliases as separate
  rules.

Catalog:

```dart
@immutable
final class UsagePricingCatalog extends Equatable {
  final List<UsagePriceRule> builtInRules;
  final List<UsagePriceRule> userRules;

  UsagePriceRule? ruleFor({
    required String model,
    required int timestampMs,
  });
}
```

`ruleFor` returns the newest matching rule whose `effectiveFromMs` is not
after the event timestamp. A user rule wins over a built-in rule with the same
model and effective timestamp.

## Cost formula

```text
oneHourWrite = clamp(cacheCreation1hTokens, 0, cacheCreationTokens)
regularWrite = cacheCreationTokens - oneHourWrite
write1hRate  = cacheWrite1hPerMillion ?? cacheWritePerMillion

costMicroUsd = round(
  freshInputTokens      * inputPerMillion +
  outputTokens          * outputPerMillion +
  cacheReadTokens       * cacheReadPerMillion +
  regularWrite          * cacheWritePerMillion +
  oneHourWrite          * write1hRate
)
```

`freshInputTokens` already normalizes Codex `total` semantics.
`reported` cost short-circuits the calculation.
`unpriced` leaves cost null.

## Built-in reference prices

`services/usage/usage_pricing_defaults.dart` contains a const list with
`source: UsagePriceSource.builtIn` and `effectiveFromMs: 0`.

The first slice seeds confirmed Claude models only:

- `claude-opus-4-1`: input 15, output 75, cache read 1.5, cache write 18.75,
  1h cache write 30.
- `claude-opus-4`: same family rates.
- `claude-sonnet-4-5`: input 3, output 15, cache read 0.3, cache write 3.75,
  1h cache write 6.
- `claude-sonnet-4`: same family rates.
- `claude-haiku-4-5`: input 1, output 5, cache read 0.1, cache write 1.25,
  1h cache write 2.
- `claude-3-5-sonnet`: input 3, output 15, cache read 0.3, cache write 3.75,
  1h cache write 6.

These are reference list prices, not provider-specific negotiated prices.
Users can override them. Models without a confirmed default, including current
Codex and many proxy models, remain unpriced until configured. OpenCode
usually reports its own cost and therefore uses `reported`.

## Storage

`usage/pricing.json`:

```json
{
  "version": 1,
  "updatedAtMs": 1760000000000,
  "rules": [
    {
      "model": "gpt-5.4",
      "inputPerMillion": 1.25,
      "outputPerMillion": 10,
      "cacheReadPerMillion": 0.125,
      "cacheWritePerMillion": 0,
      "cacheWrite1hPerMillion": null,
      "effectiveFromMs": 0
    }
  ]
}
```

- The store reads user rules only; built-ins are merged in memory.
- A corrupt file reads as empty rules and returns `corrupted: true`.
- Save uses `Filesystem.atomicWrite`.
- Reset writes an empty rules array.
- All operations go through `Filesystem`, so SSH planes work.

## Services and cubit

`SessionUsageServices` gains:

```dart
Future<UsagePricingLoad> loadPricing();
Future<void> savePricing(List<UsagePriceRule> rules);
```

`UsagePricingLoad` carries the merged catalog and a `corrupted` flag.

`SessionUsageCubit` gains:

- `UsagePricingCatalog pricing`
- `bool pricingSaving`
- `bool pricingCorrupted`
- `String? pricingError`
- `Future<void> savePricing(List<UsagePriceRule> rules)`
- `Future<void> resetPricing()`

On load, pricing and usage events load together. If pricing load fails, the
built-in catalog is used and a non-fatal warning is exposed. Saving pricing
recomputes the dashboard from cached events without re-scanning transcripts.

## Aggregation

`UsageSummary` and `UsageGroup` gain:

- `int costMicroUsd`
- `int pricedEvents`
- `int unpricedEvents`

`buildUsageDashboard` takes a `UsagePricingCatalog` and calculates cost once per
event. A group's cost is the sum of priced events in that group; unpriced
events are counted separately. Summary cost may be partial when unpriced
events exist.

## Codex model extraction

In the Codex usage scanner:

- Decode `turn_context` records.
- Read `payload.model` when it is a non-empty string.
- Keep the latest model and attach it to subsequent `token_count` events.
- Existing stored events with an empty model stay unpriced; a future backfill
  is out of scope.

Add a fixture test where `turn_context` precedes `token_count` and assert
`event.model == 'gpt-5.4'`.

## UI

### Cost card

A separate `UsageCostCard` widget, independent of
`usage_summary_cards.dart` because that file has separate uncommitted user
work.

- Total known cost, or `Unpriced` when nothing is priced.
- `X priced · Y unpriced` detail.
- Partial-cost hint when `unpriced > 0`.
- `Manage pricing` action.

### Detail table

- Add a `Cost` column.
- Show `formatUsageCost(costMicroUsd)` for priced rows.
- Show `Unpriced` for rows with zero priced events.
- Keep the existing horizontal scroll behavior.

### Pricing dialog

`UsagePricingDialog` edits user rules only:

- Model ID.
- Input, output, cache read, cache write, optional 1h cache write.
- Effective date (`YYYY-MM-DD`, empty means `0`).
- Add rule, delete rule, save, reset to defaults.
- Validation: model non-empty; numeric rates non-negative; date parseable.
- Save failure keeps the dialog open and shows an inline error.
- Reset asks for confirmation.

### Formatting

`formatUsageCost(int? microUsd)`:

- `null` → `—`
- `0` → `$0.00`
- `< 10_000` micro-USD → `<$0.01`
- otherwise fixed two decimals, with more precision under `$1` if useful.

No currency symbol logic in the pure cost engine; UI formats.

## Error handling

- Corrupt pricing file: use built-ins, expose `pricingCorrupted`.
- Save failure: keep old catalog, set `pricingError`, show error.
- Pricing load failure: use built-ins, show a dismissible warning.
- Missing model: unpriced, not zero.
- Reported cost and table cost never both apply.

## Testing

- Normalization and date-suffix stripping.
- Rule lookup by model/effective date; user override.
- Cost formula: fresh/total semantics, cache split, 1h cache, reported cost.
- Unknown model unpriced.
- Pricing JSON load/save/reset/corrupt fallback (InMemoryFilesystem).
- Codex `turn_context.model`.
- Aggregator cost totals and unpriced counts.
- Pricing dialog validation, save, delete, reset.
- Cost card/table rendering and unpriced state.
- Existing usage suite + full suite + analyzer.

## Risks

- Built-in prices can go stale. They are labelled reference values and fully
  editable.
- Proxy providers may have different prices. Users can override per model.
- Codex events imported before this slice have empty models and remain
  unpriced.
- Cost totals are partial when any event is unpriced; the UI must not present
  them as exact.
- Price changes rewrite historical displayed cost by design; no event rewrite.

## Follow-ups

1. Import/export pricing JSON.
2. Provider-specific price profiles.
3. Discounts, subscriptions, and credits.
4. Non-USD currencies and exchange rates.
5. Backfill Codex model IDs for already-imported events.
6. Cost chart and per-CLI cost breakdown.
