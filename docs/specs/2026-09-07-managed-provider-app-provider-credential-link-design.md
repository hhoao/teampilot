# Managed Provider ↔ App Provider Credential Link Design

Date: 2026-09-07
Status: Approved (design phase)

## Problem

The same third-party provider (e.g. DeepSeek, an aggregator) is configured
twice today: once as an **App provider config** (`providers/{cli}/providers.json`,
`AppProviderConfig` — apiKey + baseUrl for CLI launches) and once as a
**Managed provider** entry (`ManagedProvider` — balance/usage query definition
under "余额与用量"). The API key must be entered and maintained in both places;
they never know about each other.

Goal: **bidirectional live credential sharing** — a managed-provider entry can
reference a provider config's apiKey as its query credential, and a provider
config can reference a managed-provider entry's stored secret as its apiKey.
One source of truth per credential, editable from either side.

Scope: **apiKey-class providers only** — categories
`thirdParty` / `aggregator` / `cnOfficial` (the categories where
`requiresApiKey` holds). Official subscription providers (claude / codex /
cursor) are OAuth-based, have no reusable key, and already have their own
`cli:` credential source on managed providers; they are unaffected.

## Credential reference forms

`ManagedProviderEndpointConfig.credentialSource` gains a third form alongside
the existing `secret` and `cli:<rowId>`:

| Form                     | Meaning                                              |
|--------------------------|------------------------------------------------------|
| `secret`                 | entry's own secret in `ManagedProviderSecretStore`   |
| `cli:<cli>-mp-<entryId>` | per-entry official CLI login row (existing)          |
| `provider:<cli>:<providerId>` | live reference to an App provider config's apiKey |

`AppProviderConfig` gains one optional persisted field, added to the
model's known keys and `toJson()` (so it serializes as a first-class field):

```json
"credentialLink": "<managedProviderId>"   // empty / absent = own apiKey
```

`fromJson` defaults it to `''`, so files written before this feature
round-trip unchanged.

Both references are **live**: editing the referenced credential updates every
consumer at next read. Neither side copies the secret value.

### Cycle guard

A managed provider whose source is `provider:<cli>:<id>` must not be offered
as a `credentialLink` target for that provider config, and vice versa. The
save paths validate and reject a cycle; the pickers simply filter the
already-linked counterpart out of the candidate list.

## Credential resolution

### Managed → App provider (query side)

`ManagedProviderCredentialResolver` (or a sibling resolver wired in
`managed_provider_cubit` / usage coordinator) recognizes the `provider:`
prefix: resolve `AppProviderRepository.findById(cli, providerId)`, take its
`apiKey`, and expose it in the request credential scope under the entry's
`credentialField`. Missing provider / missing key / empty key all surface
through the existing credential-missing path — the usage refresh fails with
the existing invalidated/error presentation, never silently.

Resolution happens at request time, so key rotations in the provider config
are picked up by the next usage refresh with no invalidation events needed.

### App provider → Managed (launch-config side)

Materialization for CLIs that need the key written into native config:
when `AppProviderConfig.apiKey` is empty and `credentialLink` is non-empty,
the persistence strategy reads the managed entry's secret from
`ManagedProviderSecretStore` under that entry's `credentialField` before
generating native config. The branch lives in the shared
`ProviderPersistenceStrategy` entry point (and the credential transaction
layer), **not** scattered as `if (link != null)` across the five CLI
strategy files.

`credentialStatus` for a linked provider reflects the referenced entry's
secret presence, so the provider list shows "ready" only when the underlying
managed entry actually has a key.

## UI

### Managed-provider editor (credentials section)

Below the existing credential source field, a **"从供应商配置引用"**
dropdown lists apiKey-class provider configs grouped by CLI
(thirdParty / aggregator / cnOfficial). Selecting one:

- sets `credentialSource` to `provider:<cli>:<id>`,
- hides the secret input,
- shows a read-only chip with the provider's name + CLI (no navigation).

Selecting "手动输入" (default) restores the secret input.

### Provider config add/edit form

Next to the apiKey input, a **"从余额与用量引用"** option lists managed
entries with a non-empty `credentialRef` and kind
`apiBalance` / `customHttp`. Selecting one:

- sets `credentialLink`,
- hides the apiKey input,
- shows the referenced entry's name.

The reverse listing already exists conceptually for `cli:` sources; this
follows the same interaction shape.

## Deletion cleanup (symmetric janitors)

| Deleted                        | Cleanup                                                          |
|--------------------------------|------------------------------------------------------------------|
| Managed provider entry         | new `managed_provider_link_janitor`: clears `credentialLink` on any provider configs referencing it (modeled on `managed_provider_cli_row_janitor`) |
| App provider config            | managed entries referencing it keep their definition; next refresh fails with credential-missing; user re-binds manually |

## Testing

- Resolver unit tests both directions: happy path, referenced object
  missing, referenced credential missing/empty, rotation picked up on next
  read.
- Cycle-guard validation tests on both save paths.
- Both janitors' unit tests (injected filesystem, existing support
  harnesses).
- Editor wiring tests: picker sets source/link, secret/apiKey inputs hide,
  cycle counterpart filtered out.
- Full gate: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && dart run tool/run_tests.dart`.

## Non-goals

- No new credential storage backends; both sides reuse existing stores.
- No changes to official OAuth providers or the `cli:` source machinery.
- No balance/usage data display inside the provider config UI
  (link is for credential reuse only).
