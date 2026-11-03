# Vault-First Credentials — Design

Date: 2026-11-02
Status: Implemented
Supersedes: the opt-in linking UX in `2026-10-28-vault-credential-management-design.md` (storage model and crypto stay unchanged)

## 1. Background

The credential vault (PR #8) stores secrets in a device-local vault, but it is **opt-in**:
SSH profiles and providers keep using the OS keychain / `providers.json` until a user
manually links an entry. As a result, existing passwords, private keys, provider keys,
usage credentials and GitHub tokens never appear in the vault, and new saves still
scatter secrets across three storage systems.

This design makes the vault **vault-first**: every secret managed by TeamPilot is stored
in the vault automatically, and all pre-existing secrets are imported once, silently.

## 2. Goals

- New SSH credentials, provider API keys, managed-provider (balance/usage) credentials
  and the GitHub token are written to the vault on save, with no prompt and no success
  toast.
- All existing credentials are migrated exactly once, in the background, silently.
- Every migrated or newly captured secret is a normal vault entry: visible, searchable,
  revealable (except private keys), copyable, and listed as a reference of its owner.
- Old copies are deleted only after the vault value is verified by reading it back.
- Saving is atomic: if the vault cannot be written (locked + cancel, unavailable, I/O
  error), nothing is persisted — no profile with a missing secret, no half-migrated row.

## 3. Non-goals

- No import/export, sync, CSV, audit log, idle auto-lock, attachment hosting, or password
  generator (unchanged from the vault v1 spec).
- No new encryption scheme. Keychain backend remains the default; the encrypted-file
  backend and Argon2id/AES-256-GCM envelope are unchanged.
- SSH profile metadata (name, host, port, username) stays in `ssh_profiles/`; the vault
  stores secrets only.
- Termux's generated loopback key pair and the device identity key
  (`SshCredentialStore.loadDevicePrivateKey`) are **not** migrated: they are machine
  identities, must remain available before the vault is unlocked, and Termux additionally
  needs the PEM on disk at `.termux/ssh/id_ed25519`. The `termux` pseudo-profile is not an
  `SshProfile`, so the profile migration never sees it.
- CLI-owned login tokens (Claude/Cursor/Codex config files) are not TeamPilot-managed
  secrets and are not migrated.

## 4. Scope of secrets

| Owner | Current storage | Vault entry |
|---|---|---|
| SSH profile | `SecureSshCredentialStore` (keychain, per profile: password / privateKey / passphrase / relayGrant) | one entry per profile |
| App provider | `providers/{tool}/providers.json` → `AppProviderConfig.apiKey` | one entry per provider |
| Managed provider (balance/usage) | `ManagedProviderSecretStore` (namespaced keychain KV, multi-field) | one entry per managed provider |
| GitHub | `GithubCredentialsStore` (keychain: token/login/source) | one fixed entry (`ownerId = "default"`) |

## 5. Architecture

### 5.1 New components

- `VaultCredentialCapture` (`client/lib/services/vault/credential_capture.dart`)
  - Library-style service; owns create/update/verify for all four owner kinds.
  - Methods: `captureSsh`, `captureProvider`, `captureManaged`, `captureGithub`.
  - Finds an existing entry by `extra.ownerKind` + `extra.ownerId`, so retries are
    idempotent and renames update the same entry (id and references stay stable).
  - Verifies every field with `VaultService.readField` before returning the entry id.
  - Never logs secret values.
- `VaultLegacyImportService` (`client/lib/services/vault/legacy_import.dart`)
  - One-shot, idempotent, single-flight migration of the four owner kinds.
  - Depends on: `VaultService`, `VaultCredentialCapture`, `SshProfileRepository`,
    `SshCredentialStore`, `AppProviderRepository` (per `CliTool`),
    `ManagedProviderRepository` + `ManagedProviderSecretStore`, `GithubCredentialsStore`,
    and a `VaultDocument` marker helper.
- `VaultUnlockGate` (`client/lib/services/vault/vault_unlock_gate.dart`)
  - `Future<bool> ensureUnlocked()`: returns true when the vault is usable; when the
    encrypted backend is locked, shows the existing unlock dialog through
    `appRouter.routerDelegate.navigatorKey.currentContext` and returns whether it was
    unlocked.
  - Injected into capture-facing call sites so cubits don't import dialogs (same pattern
    as `openCredentialLoginUrl` in `AppProviderCubit`).
  - `showVaultUnlockDialog` is refactored to return `Future<bool>`.

### 5.2 Entry conventions

`VaultEntry.extra` gains:
- `ownerKind`: `sshProfile` | `appProvider` | `managedProvider` | `github`
- `ownerId`: the owner's id (`default` for GitHub)

Type and fields:

| Owner | `type` | `fields` | `revealable` |
|---|---|---|---|
| SSH password | `sshPassword` | `host`, `port`, `username`, `password`, optional `relayGrant` | true |
| SSH private key | `sshPrivateKey` | `host`, `port`, `username`, `privateKey`, `passphrase`, optional `relayGrant` | false |
| App provider | `apiKey` | `provider`, `baseUrl`, `apiKey` | true |
| Managed provider | `apiKey` when exactly one field, else `custom` | scope fields verbatim | true |
| GitHub | `apiKey` | `token`, `login`, `source` | true |

Tags: `ssh` / `provider` / `usage` / `github`, plus `migrated` for entries created by the
one-shot importer. Titles follow the owner's display name and are updated on rename.

### 5.3 References

- SSH: existing `SshProfile.vaultEntryId`; the paired-relay grant lives in the same entry
  (`relayGrant`), so a profile has exactly one entry.
- App provider: existing `AppProviderConfig.credentialLink = "vault:<entryId>"`.
- Managed provider: new nullable `ManagedProvider.vaultEntryId`.
  Read order: `vaultEntryId` → vault entry; otherwise legacy `credentialRef` → secret store.
- GitHub: pointer key `teampilot.github.v1.vault_entry` in the same secure KV (holds only
  an entry id, not a secret). `readStored()` follows the pointer; legacy keys remain
  readable during migration. The importer reads through `readStored()` so the store's own
  legacy-key migration runs first.

### 5.4 Import marker

`VaultDocument` gains optional `legacyImportVersion` (int, default `0`). It is stored
inside the encrypted document, so migration state travels with the vault. Parsing is
additive and tolerant: documents without the field load as `0`; the document version
stays `1`. The marker is set to `1` only when a full pass finishes with zero failures.

## 6. Capture-on-save

All flows: `ensureUnlocked()` first; on refusal/error the save aborts before any write.
No success toast, no confirmation dialog.

### 6.1 SSH

- Desktop dialog `_SshProfileFormDialog._save` and full-page `SshProfileSetupPage`:
  1. validate and build the profile,
  2. `ensureUnlocked()`,
  3. `captureSsh(profile, password|privateKey+passphrase)`,
  4. save the profile with the returned `vaultEntryId`,
  5. never write the keychain.
- The "identity file on disk" input is still read into a PEM and captured; the path is
  kept in metadata.
- The paired-relay grant is captured into the same entry when it exists.
- Remove the "credential source" `TpSelect`, the "Save to vault" checkbox, the list
  card's "Move to vault" button, and the now-unused `SshProfileCubit.migrateToVault`
  method (plus its test). Existing manual linking remains readable but is no longer
  offered.

### 6.2 App providers

- `AppProviderCubit.upsertProvider` is the single write choke point (forms, logins,
  imports). When `apiKey` is non-empty and `credentialLink` is not a `vault:` link:
  1. `ensureUnlocked()`,
  2. `captureProvider(draft)`,
  3. persist with `credentialLink = vault:<id>` and `apiKey = ""`.
- When the row already has a `vault:` link, a non-empty `apiKey` updates that same entry
  instead of creating a new one.
- Rows linked to a managed provider (`credentialLink` = managed id) are untouched; the
  managed entry itself is migrated separately.
- Removing a provider deletes its vault entry (no orphan secrets); like saving, the
  delete calls `ensureUnlocked()` and is aborted when the user cancels the prompt.

### 6.3 Managed providers (balance/usage)

- Editor save with a non-empty credential secret:
  1. resolve required existing fields (from vault entry when `vaultEntryId` is set,
     otherwise from the legacy store),
  2. `ensureUnlocked()`,
  3. `captureManaged`,
  4. persist the provider with `vaultEntryId`; on persistence failure delete the
     newly-created entry (or restore the previous field map).
- The credential transaction keeps its current atomicity contract; it is reimplemented
  on top of capture for vault-backed rows and left unchanged for legacy rows.

### 6.4 GitHub

- `GithubCredentialsStore` gains an optional `VaultService` + pointer support:
  - `saveOAuth` / `savePat`: capture the fixed GitHub entry, write the pointer, delete
    the legacy token/login/source keys.
  - `readStored`: pointer → vault entry; fall back to legacy keys.
  - `clearStored`: `ensureUnlocked()` first, then delete the entry and pointer, then
    legacy keys; cancel aborts the clear (no half-cleared credential state).
- All call sites (GitHub account page, Hub publish wizard) keep their current API.

## 7. One-shot migration

### 7.1 Trigger

- `app_shell` constructs `VaultLegacyImportService` and starts it after
  `vaultService.initialize()`.
- Keychain backend: runs immediately in the background.
- Encrypted backend: if locked, does nothing; `VaultCubit` gains an `onUnlocked`
  callback (also fired after `enableEncryption`) that starts the importer.
- Single-flight per process; failures are retried on the next start/unlock.

### 7.2 Per-owner procedure

```
for each owner of this kind:
  if owner already linked (vaultEntryId / vault: link / pointer): skip
  legacy = read legacy secrets
  if legacy is empty: skip
  entryId = capture(owner, legacy)          # find-or-create + verify
  write owner reference; persist owner      # profile / provider row / ref / pointer
  delete legacy secrets                     # only after reference persisted
on failure after capture:
  best-effort delete the entry created in this run
  keep legacy data; log ownerKind + ownerId + error code; continue with next owner
```

Order: GitHub → SSH → app providers (all `CliTool` values) → managed providers.

Safety invariants:
- A legacy secret is deleted only after (a) the vault value read-back matched and
  (b) the owner reference was persisted.
- Existing references are never rewritten when they already point at a vault entry.
- Provider rows that link to a managed provider are skipped even if they still carry a
  stale `apiKey`; their value comes from the managed entry, which is migrated separately.
- Profile metadata is saved before its secret is removed; if the secret capture fails,
  the profile is not saved at all when the user is creating it, and an existing profile
  keeps its old reference.
- Failures never abort other owners.

### 7.3 Marker

- `legacyImportVersion = 1` only after every owner kind completed without a failure.
- With failures, the marker stays `0`; the next run re-scans, skips linked owners, and
  retries only unfinished ones.
- Migration is silent: diagnostics go to `AppLogger` with ids/codes only.

## 8. Read paths

- SSH connections: unchanged — `resolveSshCredentials` prefers `vaultEntryId`.
- SSH test connection: already resolves vault.
- Paired relay tunnels (`PairedRelayTunnelRegistry`): read `relayGrant` from the linked
  vault entry first, then fall back to the keychain for unmigrated profiles.
- Provider runtime lookup: unchanged — `appProviderLinkedCredentialLookup` handles
  `vault:`.
- Managed-provider lookup (`app_shell` usage/balance resolution): add a vault branch
  keyed by `vaultEntryId`; legacy branch stays for unmigrated rows.
- GitHub reads: pointer-first as described above.
- `VaultCubit.referencesFor`: also returns managed providers and GitHub when their
  reference matches.

## 9. UI changes

- SSH form: no credential-source selector, no "save to vault" checkbox.
- SSH list: no "move to vault" button; the vault badge stays for linked profiles.
- Provider form: the credential-source list keeps "own key" and managed-provider
  options; vault links are shown as a read-only "stored in vault" state, and pasting a
  new key updates the linked entry.
- Managed provider editor: shows "stored in vault" for vault-backed rows; the legacy
  ref field is read-only once migrated.
- Vault page: unchanged. No success toasts anywhere in the capture flows.

## 10. Error handling

| Situation | Behaviour |
|---|---|
| Vault locked, encrypted | Prompt for passphrase; cancel = abort the whole save, nothing persisted |
| Vault unavailable (init/format/IO error) | Abort secret save with a localized error; never fall back to keychain |
| Capture verify mismatch | Treat as failure; do not write the owner reference or delete legacy data |
| Owner persist fails after capture | Delete the just-created entry (restore previous fields if it existed) |
| Migration singleton fails | Keep legacy data, continue others, marker stays 0 |
| Provider deleted | `ensureUnlocked()` then delete its vault entry; cancel aborts the delete. Same for managed providers and GitHub clear |

Logging never includes secret values; `VaultEntry.toString` already redacts them.

## 11. Testing strategy

### 11.1 Unit

- `VaultCredentialCapture`
  - create then update keeps the same entry id; rename updates the title
  - empty optional fields are not stored; private keys stay non-revealable
  - verify failure throws and leaves no reference behind
  - `extra.ownerKind/ownerId` present on every entry
- `VaultLegacyImportService`
  - full fixture (SSH password + key, provider, managed multi-field, GitHub) migrates
    everything, deletes legacy values, sets references, marker = 1
  - second run is a no-op
  - injected failure for one owner leaves its legacy data, marker = 0, next run retries
    only that owner
  - verify-mismatch leaves legacy data and no reference
  - locked vault → no-op; runs after unlock
  - already-linked owners and managed-link providers are skipped
- Storage branches
  - managed secret store vault read/write/delete, required-field merging
  - GitHub store vault save/read/clear with legacy fallback

### 11.2 Save flows

- SSH password save → entry exists, profile linked, keychain empty.
- SSH private-key save → entry non-revealable, PEM + passphrase captured.
- Locked vault: cancel → no profile, no entry; confirm → saved.
- App provider add/edit → entry created/updated, `credentialLink` set, `apiKey` empty.
- Provider paste-new-key on a linked row → same entry updated.
- Managed editor → entry created, `vaultEntryId` set; persist failure deletes the entry.
- GitHub OAuth/PAT → entry + pointer; legacy keys removed.

### 11.3 Migration integration

- Seed all four legacy stores → one run imports all, references resolve at runtime.
- Failure injection at each stage (read, capture, verify, persist reference, delete).
- Startup with locked vault then unlock → migration runs exactly once.
- Concurrent triggers (boot + unlock + provider save) → single-flight, no duplicates.

### 11.4 Regression

- SSH connect resolves from migrated entries; provider calls resolve; managed usage
  probes resolve; Hub publish reads the GitHub token.
- Existing SSH/provider/managed/GitHub tests updated where the storage contract changed.
- `flutter analyze --no-fatal-infos --no-fatal-warnings` → 0 errors.
- Full `dart run tool/run_tests.dart` in the background before declaring done.

## 12. Risks and mitigations

| Risk | Mitigation |
|---|---|
| A migration bug deletes a secret before it is safely stored | Strict order (capture → verify → persist ref → delete) + per-owner isolation + failure-injection tests |
| Locked vault blocks saving unexpectedly | Prompt at save time; cancel aborts atomically; background migration never prompts |
| Provider login/import flows bypass the form | Capture lives in `upsertProvider`, the single write choke point |
| Orphaned entries after owner deletion | Delete entry when provider/managed/GitHub is cleared or removed |
| Duplicate entries after a crash between capture and reference write | Find-or-create by `extra.ownerKind/ownerId` |
| Vault file corruption bricks secret saving | Surface a localized error pointing to vault settings; do not silently fall back |

## 13. Rollout

- No data-format break: `VaultDocument` stays version 1 with an additive marker;
  `ManagedProvider` gains an optional field.
- Old clients opening a new document ignore the extra marker field.
- The importer is idempotent, so an interrupted upgrade simply continues next launch.

## 14. Unlock policy (follow-up)

Functional reads and explicit reveals have different requirements:

- **Remembered master (functional reads).** When the user enables encryption or
  unlocks manually, the passphrase is written to the OS keychain under
  `teampilot.vault.v1.master`. At boot, `VaultService.tryAutoUnlock()` reads it
  and unlocks silently, so SSH, providers, balance/usage queries, CLI config
  generation and GitHub work without any prompt. Background work never
  prompts.
- **Explicit reveal (re-authentication).** Clicking the eye on a password/key
  input, or revealing a value in the vault detail view, always asks for the
  master password again, even when the vault is auto-unlocked. A wrong or
  cancelled password leaves the value masked. Keychain-backed vaults reveal
  without a prompt.
- **Lock.** The Lock action clears the in-memory document and deletes the
  remembered passphrase, so the next functional read requires the password
  again (or a restart with a fresh manual unlock). Restarting after a normal
  auto-unlock does not prompt.
- **Refresh.** After an unlock or background import, the vault page reloads its
  entry rows without changing status, avoiding re-entrant page rebuilds while
  a dialog is closing.
