# API balance automatic refresh

## Goal

Ensure enabled HTTP/JSON API-balance providers refresh automatically after
their cached usage snapshot expires, without changing manual refresh behavior.

## Design

`HttpJsonMappingConfig.fromProvider` will assign a default cache lifetime of
ten minutes to HTTP/JSON provider responses. The adapter will consequently
persist `staleAt` ten minutes after `fetchedAt` for API balances.

The existing `ManagedProviderUsageAutoRefresh` timer already runs every ten
minutes and calls `refreshExpiredEnabled`. That path will refresh snapshots
once their `staleAt` is reached; app-resume follows the same path. A manually
requested refresh remains a forced refresh and is unchanged.

## Scope and compatibility

The change is limited to the HTTP/JSON usage adapter's default mapping. It
does not alter provider configuration, provider request formats, the refresh
button, or disabled-provider behavior.

## Tests

Add an adapter-level regression test that verifies an HTTP/JSON snapshot
receives a ten-minute `staleAt`. Existing cubit and auto-refresh tests already
exercise the expired-versus-fresh control flow; the new test connects that
flow to the HTTP/JSON adapter output.
