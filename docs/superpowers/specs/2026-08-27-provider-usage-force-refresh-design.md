# Provider usage force refresh

## Goal

Make provider-usage refresh triggers fetch every enabled Provider directly,
without using cached snapshot expiration to decide whether to query.

## Design

Keep persisted usage snapshots so the UI can display the most recent result
immediately at startup and when a request fails. Retain `staleAt` in the model
and adapters for backward-compatible cache data, but remove it from automatic
refresh decisions.

`ManagedProviderUsageAutoRefresh` will request a refresh immediately when it
starts and every ten minutes thereafter. Its app-resume caller will use the
same force-refresh operation. The cubit will expose a method that reloads the
provider catalog and refreshes all enabled Providers, using the coordinator's
existing single-flight behavior to coalesce overlapping requests.

## Scope

Manual refresh remains unchanged. Disabled Providers remain excluded. No
provider configuration, cache schema, or UI change is required.

## Tests

Replace expiration-based auto-refresh expectations with tests that prove a
fresh cached snapshot is refreshed on a timer tick and at auto-refresh start.
Retain tests covering disabled Providers and overlapping refresh safety.
