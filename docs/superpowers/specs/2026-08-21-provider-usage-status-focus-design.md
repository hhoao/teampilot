# Provider usage status bar focus (single changed provider)

Date: 2026-08-21  
Status: approved for planning  
Related: [2026-08-18-managed-provider-usage-design.md](./2026-08-18-managed-provider-usage-design.md)

## Goal

The workspace status bar Managed Provider usage segment must show **one** brand icon and that provider’s primary usage value—not a row of every enabled provider’s icons plus a count. The shown provider is the one whose usage **changed** relative to the previous snapshots (session memory); when several change in one refresh, pick the latest `fetchedAt` (tie: later in the enabled list).

## Non-goals

- Changing Usage Panel / popover contents or refresh behavior
- Persisting focus across app restarts
- Cubit / repository / cache schema changes
- Animating or rotating through multiple changed providers

## Display rules

| Case | Status segment |
|------|----------------|
| Zero enabled providers | Unchanged: wallet icon + add entry |
| One or more enabled | Always: **one** brand mark + primary measure label (`remaining ?? used ?? total`, with currency/unit), same as today’s single-provider path |
| Any enabled snapshot is stale / error / unsupported | Keep warning icon even if the focused provider is healthy |
| Click | Unchanged: open full Usage Panel |

Remove the multi-icon `Row` (`managed-provider-usage-brand-icons`) path. Multi-provider no longer shows a bare count string as the primary label.

## Focus selection (`focusedProviderId`)

Pure function inputs: enabled providers, current snapshots, previous snapshots, current focus id. Output: next focus id.

| Situation | Selection |
|-----------|-----------|
| After a refresh, one or more providers **changed** vs previous | Among changed ids that are still enabled: max `fetchedAt`; equal `fetchedAt` → later in enabled list order |
| No changes this update | Keep previous focus if still enabled |
| Cold start / no focus yet | Among enabled: max `fetchedAt`; if none have snapshots → first enabled |
| Focused provider disabled or deleted | Re-select with cold-start rules |

### What counts as “changed”

For the same `providerId`, treat as changed when any of:

- Snapshot newly appears (absent → present)
- Primary measure fields differ: `remaining`, `used`, `total`, `unit`, `currency`
- `status` differs

Do not treat identical measure+status with only unrelated metadata noise as a change unless the product later expands the comparer. Prefer comparing the same primary-measure selection the label uses (`measures.firstOrNull` today).

## Architecture

UI-layer only (Approach 1).

1. **Pure helper** (e.g. `client/lib/widgets/managed_provider/managed_provider_usage_status_focus.dart`) — no Flutter imports; unit-tested.
2. **`ManagedProviderUsageStatusItem`** — Stateful widget keeps `_previousSnapshots` and `_focusedProviderId`. On each usage rebuild: compute next focus from previous+current, then store current snapshots as previous. Build `_Summary` from the single focused provider (reuse `_singleLabel`).
3. **Cubit / coordinator / panel** — unchanged.

Session memory is in-widget only; disposing the status segment resets focus to cold-start rules on next mount (acceptable).

## Testing

### Pure helper

- No previous → latest `fetchedAt` / first without snapshots
- Single provider change → focus that id
- Multiple changes → max `fetchedAt`; same timestamp → later in list
- No change → retain focus
- Focus disabled → reselect
- New snapshot (absent → present) → changed

### Widget (`managed_provider_usage_status_item_test.dart`)

- Two enabled providers: exactly one brand key; no multi-icon row key
- Sequential A then B measure changes: icon and label follow focus
- Cold start with two snapshots: shows usage for newest `fetchedAt`, not `"2"`

## Spec amendment to prior design

This supersedes the multi-provider bullet under “左下角摘要入口” in the 2026-08-18 design:

- **Was:** multiple providers → icon group + provider count  
- **Now:** multiple providers → single focused provider icon + that provider’s primary usage value, per rules above
