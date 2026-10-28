# Cursor usage: multiple accounts, arbitrary range

## Scope

A dedicated account-level Cursor usage page that:

- lists every Cursor account the app can see, discovered automatically or added
  manually, and fetches them independently;
- queries **any** start/end range, defaulting to the account's billing cycle;
- reads Cursor's event API instead of the dashboard CSV export.

This supersedes the Cursor sections of
[`2026-10-28-session-usage-cursor-gemini-codebuddy-design.md`](2026-10-28-session-usage-cursor-gemini-codebuddy-design.md).
Two of its limits are removed: "the sync picks the newest valid token" and
"multiple accounts are not merged into one report".

The existing session usage page and `usage/cursor_import.json` are untouched.
Account usage is a separate product surface with its own storage.

## Decisions

| Question | Decision |
|----------|----------|
| Where accounts come from | Auto-discovered provider homes **plus** manual entries, merged by `accountId` |
| Where usage is shown | New page; session usage page stays scoped to local sessions |
| Range default | Billing cycle from `usage-summary`, with presets and a custom range |
| Data source | `POST /api/dashboard/get-filtered-usage-events`; the new page never uses CSV |
| Cache | Coverage-based gap fill, raw events kept 90 days, day aggregates kept forever |

## Why the event API, not the CSV export

Measured on one account over 2026-09-29 → 2026-10-28 (740 events, same range for
both endpoints):

| | CSV export | Event API |
|---|---|---|
| Requests | 1 | 2 (500 per page) |
| Account identity in payload | none | `owningUser` per event |
| Row identity | `sha256` of the row fields | `usageEventId` |
| Cost for subscription usage | empty (`Free` / `Included` / `-`; sums to `$0.00`) | `totalCents` `$468.66`, `chargedCents` `$461.26` |
| Token buckets | input, cache write, cache read, output | same |
| Model | `auto` for 109 rows | `default` for the same 109 rows |

The CSV export cannot answer "what did this account cost" for plan-included
usage, and its rows carry no account identity, so multi-account attribution
would rest entirely on which cookie issued the request. Neither is acceptable
once several accounts share one report.

## Account model

```dart
enum CursorAccountSource { discovered, manual }

final class CursorUsageAccount {
  final String accountId;   // sha256(sub)[0:16] — same as CursorUsageAuth
  final String userId;      // last segment of sub, used to build the cookie
  final String label;       // user-editable; default "Cursor · <id[0:6]>"
  final CursorAccountSource source;
  final bool enabled;
  final int? expiresAtMs;   // JWT exp
  final String? owningUser; // bound on first successful fetch
  final int teamId;         // 0 = personal account, shown in the editor
}
```

`accountId` reuses the hash already produced by
`services/cli/cursor/provider/cursor_usage_auth_resolver.dart`, so auto-discovered
and manual entries for the same account collapse into one row.

`CursorAccountRegistry.list()`:

1. Scan `<base>/providers/cursor/*/home` auth files, then
   `CursorHomeLayout.globalAuthJsonCandidates(home)`; parse the JWT, key by
   `accountId`, keep the newest `mtime` per id.
2. Merge `cursor_usage/accounts.json` manual entries. On an `accountId` collision
   the manual entry wins for `label` / `enabled` / `teamId` / `owningUser`, but
   the **token still comes from whichever source is freshest**, because a
   discovered home refreshes itself while a pasted cookie only expires.
3. Keep expired accounts in the list, flagged `expired`. They never sync, and
   they never block the others.

Storage is split: non-secret metadata in `<base>/cursor_usage/accounts.json`
(atomic write, revision counter, cross-instance lock, following
`repositories/managed_provider_repository.dart`); secrets in secure storage.

## Credentials and attribution

Manual entry accepts three paste shapes — a full
`WorkosCursorSessionToken=user_x::eyJ…` cookie, `user_x::eyJ…`, or a bare
`eyJ…` JWT. Only the JWT is stored; `userId` is derived from `sub` and the
cookie is rebuilt on demand, mirroring `CursorUsageAuth.cookie`. There is exactly
one source of truth for the header.

Validation runs in two steps: reject locally when `exp <= now + 60s`, then issue
`POST get-filtered-usage-events` with `pageSize: 1` and require HTTP 200.

### Why binding, not comparison

The JWT `sub` is `user_01KWV3…` while events carry `owningUser: "380653899"`.
The two identifiers come from different systems, so equality cannot be checked.
Instead:

- On the first successful fetch, record the observed `owningUser` set. For a
  personal account it must be exactly one value.
- On every later fetch with `teamId == 0`, the set must still be that single
  value; otherwise the account is stopped with `accountMismatch`. This catches a
  pasted cookie that belongs to a different account.
- `teamId != 0` accounts skip the comparison — a team's events legitimately span
  several `owningUser` values — and only record the set.

Expiry is never auto-refreshed: Cursor exposes no public refresh endpoint, so a
web session cookie has to be pasted again. The account row shows "expired, sign
in again" and other accounts keep syncing.

## Range

`CursorUsageRange` is a sealed value: `billingCycle | today | 7d | 30d |
lastMonth | custom(start, end)`. The default is `billingCycle`, parsed from
`usage-summary` (`billingCycleStart` / `billingCycleEnd` are ISO strings, not
epoch millis); when those fields are missing it falls back to the calendar
month. Custom ranges snap to local day boundaries — `start` at `00:00:00.000`,
`end` at `23:59:59.999` — so a partially covered day cannot be counted twice.

The last selection is a single scalar in app settings.

## Cache

`<base>/cursor_usage/cache/<accountId>.json`:

```json
{ "version": 1, "accountId": "", "owningUser": "",
  "coverage": [{ "startMs": 0, "endMs": 0 }],
  "days": [{ "dayMs": 0, "inputTokens": 0, "outputTokens": 0,
             "cacheReadTokens": 0, "cacheWriteTokens": 0,
             "totalCents": 0.0, "chargedCents": 0.0, "eventCount": 0,
             "models": {} }],
  "events": [] }
```

- `days` holds per-day, per-model aggregates and is kept indefinitely.
- `events` holds raw events for the most recent 90 days only. Older ranges are
  answered from `days`; the detail table shows "summary only" instead of an
  empty table.
- `coverage` reuses the adjacent-interval merge currently inlined in
  `services/usage/cursor_usage_import_store.dart`; that helper is extracted to a
  shared function rather than copied.

## Sync

`CursorUsageCoordinator.fetchRange(account, startMs, endMs)`:

1. Expired account → return `login` without touching the network.
2. Subtract `coverage` from the request to get the gaps, aligned to whole days.
3. Page each gap with `pageSize: 500`, `page` from 1, until the collected count
   reaches `totalUsageEventsCount` or a page comes back empty. Hard cap 40 pages,
   then fail with `rangeTooLarge` and ask the user to narrow the range.
4. Verify the `owningUser` binding.
5. Upsert by `usageEventId`, recompute the affected `days` buckets, extend
   `coverage`, write atomically.
6. Trim `events` to the 90-day window.

Concurrency: serial within an account, at most two accounts in flight, 30 s per
request, one backoff on 429 before reporting `rateLimited`. A failure in one
account never aborts the rest. Per-account in-flight dedupe follows the
`_loadFlight` pattern in `cubits/session_usage_cubit.dart`.

Triggers: page open, range change, app resume, the refresh button, and a 10-minute
tick while the page is visible. A range with no coverage is always fetched before
rendering — never displayed as zero.

Errors: `login / rateLimited / network / http / invalidResponse /
accountMismatch / rangeTooLarge`.

## Modules

```
services/cursor_usage/
  cursor_account_registry.dart
  cursor_account_credential_store.dart   // SecureKeyValueStore + namespaced keys
  cursor_usage_api_client.dart           // POST events + pagination + error map
  cursor_usage_cache_store.dart          // coverage + days + events
  cursor_usage_coordinator.dart          // gap fill, concurrency, writes
```

Plus `models/cursor_usage_account.dart`, `models/cursor_usage_range.dart`,
`models/cursor_usage_report.dart`, `cubits/cursor_usage_cubit.dart`.

Credential storage reuses the `SecureKeyValueStore` interface from
`repositories/ssh_credential_store.dart` and follows the namespaced-key,
manifest, and rollback pattern of `services/provider_usage/managed_provider_secret_store.dart`
without importing that class.

## UI

Entry point: `HomeGlobalView.cursorUsage`, sidebar row below the session usage
row, deep link `/home-v2?global=cursorUsage`.

`pages/cursor_usage/`:

- `cursor_usage_page.dart` — header (range picker, refresh, add account), account
  list, selected account detail
- `widgets/account_row.dart` — label, `auto`/`manual` badge, status
  (ok / expired / syncing / failed), plan progress from `usage-summary`, range
  totals, last sync
- `widgets/range_picker.dart` — presets plus a custom range dialog
- `widgets/usage_totals.dart` — input, output, cache read, cache write, cost
- `widgets/daily_trend.dart` — per-day bars
- `widgets/model_breakdown.dart` — per-model split with an explicit
  "unattributed" bucket
- `widgets/event_table.dart` — event detail, with the summary-only notice on
  older ranges
- all-accounts view — one comparison table across accounts

`buildUsageDashboard` is not reused: it models session/team/CLI attribution, not
accounts. Formatting helpers and `TpTextStyles` tokens are reused.
`widgets/usage/usage_trend_chart.dart` currently takes a dashboard type, so its
bar rendering is extracted into a component that accepts
`List<(dayMs, tokens)>` and used by both pages.

Localization goes to `client/lib/l10n/app_en.arb` and `app_zh.arb` only.

## Testing

- `cursor_account_registry_test` — discovery dedupe, manual precedence, expired
  filtering
- `cursor_usage_gap_test` — gap subtraction, adjacent merge, day-boundary
  alignment
- `cursor_usage_coordinator_test` — pagination termination, 40-page cap,
  `accountMismatch` abort, 429 backoff
- `cursor_usage_cubit_test` — parallel accounts, one failing account does not
  block others, range change recompute

Fakes implement `CursorUsageApiClient`; storage uses
`test/support/in_memory_filesystem.dart`. No network in tests. Per
`AGENTS.md`, tests run through `dart run tool/run_tests.dart`.

## Non-goals

- Refreshing Cursor tokens automatically, or any OAuth flow.
- Per-conversation or per-request drill-down beyond the event table.
- Changing the session usage page's Cursor import path.
- Team member attribution inside a team account's events.

## Limitations

- Both exports name some models generically (`auto` in CSV, `default` in the
  event API), so roughly 15% of events land in the "unattributed" model bucket
  and cannot be attributed by this or any existing endpoint.
- The event API is internal and unversioned; a change breaks sync until the
  client is updated.
- Pasted cookies expire on Cursor's schedule and must be re-entered.
- `totalCents` is a floating-point per-event value; sums are close to, not
  identical with, the dashboard figure.
