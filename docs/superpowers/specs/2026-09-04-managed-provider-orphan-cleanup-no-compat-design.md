# Per-entry credentials: orphan cleanup and legacy-source removal

Date: 2026-09-04
Status: Approved design

## Problem

The per-entry official credentials feature (commits `13ee499c0`..`bde3007f6`)
left two follow-ups:

1. **Orphan rows and credentials** — deleting a managed-provider entry
   (or logging in from a canceled new editor) leaves the dedicated CLI
   provider row (`<cli>-mp-<entryId>`) and its isolated HOME directory
   (live OAuth tokens) on disk forever.
2. **Backward-compat layer** — legacy shared credential sources
   (`cli:cursor-account`, `cli:claude-official`, `cli:openai-official`) are
   still recognized, migrated on load, and the shared CLI provider rows
   remain launch-selectable.

The user directed: no backward compatibility. Legacy entries fail outright,
the shared rows are deleted entirely, and orphans are reclaimed.

## Goal

- Managed-provider `cli:` credential sources are **per-entry only**
  (`cli:<cli>-mp-<entryId>`). Legacy shared sources are no longer recognized,
  migrated, or honored.
- The shared CLI provider rows (`cursor-account`, `claude-official`,
  `openai-official`) are deleted from the provider catalogs **and from disk**
  (including their credential directories — irreversible, accepted).
- Deleting a managed-provider entry deletes its dedicated CLI row and
  isolated HOME directory.
- A startup sweep reclaims orphaned `-mp-` rows (no corresponding entry) and
  performs the one-time shared-row deletion.

## Design

### 1. No-compat binding and resolution chain

`ManagedProviderCliBinding` (`client/lib/services/provider_usage/managed_provider_cli_binding.dart`):

- Remove `_legacyByCli` row-id matching, `legacySourceForCli`, and
  `migrateCredentialSource`. `cliForCredentialSource` / `rowIdForCredentialSource`
  recognize **only** `<cli.value>-mp-` per-entry sources; every other `cli:`
  source resolves to null (treated as an invalid source).
- Rename `_legacyTemplates` to an official-templates table (still derived from
  the official presets — `rowTemplateFor` keeps deriving dedicated rows).
- Remove `isPerEntrySource` (all valid sources are per-entry; the
  distinction collapses).

`ManagedProviderCubit` (`client/lib/cubits/managed_provider_cubit.dart`):

- Remove the migration rewrite from the load/upsert paths (the
  `migrateCredentialSource` call sites). Keep `_ensureCliRow` so upsert still
  ensures the dedicated row exists.
- Load performs no source rewriting. **Existing legacy-source entries stay
  in the catalog un-migrated**; their usage queries resolve no CLI and
  return `missingCredential` — the panel shows "credential not configured".
  The user deletes or re-creates them manually.

Official managed-provider presets
(`client/lib/services/provider_usage/managed_provider_presets.dart`):

- The three official presets' `credentialSource` changes from the legacy
  shared ids to **CLI-intent sources**: `cli:cursor`, `cli:claude`,
  `cli:codex` (no row id). The editor resolves the intent source to the real
  per-entry source (`cli:<cli>-mp-<entryId>`) when the entry is saved, and
  the editor's official-credentials widget binds to the dedicated row the
  same way it does today. New entries land with per-entry sources.

### 2. Delete the shared rows entirely

- Delete `client/lib/services/provider_usage/official_managed_provider_binding.dart`
  (`OfficialManagedProviderBinding`, `ensureOfficialAppProvider`) and its
  test — dead code per the final review.
- `ProviderCapability.defaultOfficialProviderId` returns **null** for cursor,
  claude, and codex. Simple launch with no pinned provider no longer
  auto-selects a shared row (`SimpleLaunchIdentity.resolve` tolerates null;
  the consumer sites — automation_dispatcher,
  session_provisional_builder, landing_draft_resolver, cursor/codex
  capability fallbacks — already have null-tolerant branches).
- `_resolveDefaultClaudeProviderId` (claude capability) generalizes its
  `provider.id == 'claude-official'` special case to
  `isOfficial && category == official`.
- Model-catalog id comparisons (`codex_model_catalog`,
  `claude_model_catalog`) keep their branches — they compare user-configured
  ids and simply stop matching; no behavior hazard.
- The startup sweep (§3) deletes the shared rows from the three CLI
  catalogs and removes `providers/<cli>/<shared-row-id>/` from disk
  (credentials included — irreversible, user-accepted).

### 3. Orphan cleanup — delete hook + startup sweep

**Delete hook** — `ManagedProviderCubit.delete()` (inside
`_serializeMutation`):

1. If the entry uses a per-entry source: remove the dedicated row from the
   CLI catalog via the `AppProviderCubit` (drop `id == <rowId>` from
   `providersFor(cli)` and persist).
2. Remove the disk directory `providers/<cli>/<rowId>/` recursively
   (`Filesystem.removeRecursive` — for cursor this removes the whole
   isolated HOME including auth.json, hooks, rules).
3. Existing secret-store and usage-cache cleanup unchanged.

**Startup sweep** — new service `ManagedProviderCliRowJanitor`
(`client/lib/services/provider_usage/managed_provider_cli_row_janitor.dart`),
triggered once by `app_shell` after the first managed-provider load:

- For each of cursor / claude / codex: scan the provider catalog rows.
- Delete every `<cli>-mp-*` row with no corresponding managed-provider
  entry (row + disk directory).
- Delete the shared rows (`cursor-account`, `claude-official`,
  `openai-official`) — row + disk directory.
- The sweep only deletes — never creates or rewrites. Failures are logged
  via `AppLogger` and do not block startup.

### 4. Error handling

- Disk deletion failure during the delete hook → log; row deletion
  continues (residual directories are reclaimed by the next sweep).
- `AppProviderCubit` row removal failure → entry deletion still completes
  (cleanup is best-effort, matching the existing `onProvidersDeleted`
  semantics).
- Sweep failure → log only.

## Testing

- **Binding unit tests**: legacy sources return null; `cli:cursor`
  (intent source) resolves; template derivation unchanged; per-entry
  sources still resolve.
- **Cubit unit tests**: delete of a per-entry entry removes the CLI row and
  directory; delete of an ordinary entry has no CLI side effects; the
  load-migration tests are removed/rewritten (migration no longer exists);
  the serialized-save race regression test is adapted to the row-ensure
  save path.
- **Janitor unit tests**: orphan `-mp-` rows reclaimed; rows with a live
  entry preserved; shared rows deleted; empty catalogs are a no-op.
- **Preset unit tests**: the three official presets carry intent sources
  (`cli:<cli>`).

## Out of scope

- Model-catalog id-comparison branches (harmless after row deletion).
- Any UI for listing invalid legacy entries beyond the existing
  missing-credential rendering.
- Cross-machine credential bridge.
