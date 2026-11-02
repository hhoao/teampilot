# Vault-First Credentials Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Store every TeamPilot-managed credential in the credential vault automatically — on new saves and via a one-time migration of all existing secrets — without prompts or success toasts, while keeping saves atomic when the vault is locked.

**Architecture:** A `VaultCredentialCapture` service owns find-or-create/verify/rollback for four owner kinds (`sshProfile`, `appProvider`, `managedProvider`, `github`). Owners keep an explicit reference to their entry (`vaultEntryId`, `credentialLink = vault:<id>`, GitHub pointer key, `ManagedProvider.vaultEntryId`). A `VaultLegacyImportService` performs the one-shot migration with strict ordering (capture → verify → persist reference → delete legacy) and per-owner failure isolation. Saves call `VaultUnlockGate.ensureUnlocked()` first and abort atomically on refusal.

**Tech Stack:** Flutter/Dart, `flutter_bloc`, `pointycastle` (vault crypto), in-memory fakes from `client/test/support/in_memory_filesystem.dart`.

## Global Constraints

- Test command is always `cd client && dart run tool/run_tests.dart <paths>`; **never** run `flutter test` directly.
- Inner loop is `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`; the baseline is **34** pre-existing info/warning lines and **0** errors.
- Final verification is `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && dart run tool/run_tests.dart` (full suite in the background before claiming done).
- l10n edits only in `client/lib/l10n/app_en.arb` and `app_zh.arb`, then run `cd client && flutter gen-l10n`; commit generated files.
- Never log credential values. `VaultEntry.toString` already redacts; log only owner kind/id, entry id, and error codes.
- No success toast or confirmation dialog for capture; only errors prompt.
- Capture assumes the vault is initialized and unlocked; callers must call `VaultUnlockGate.ensureUnlocked()` first.
- Entry owner metadata keys are exactly `ownerKind` and `ownerId` in `VaultEntry.extra`.
- Owner kind constants live in `credential_capture.dart` and must be used everywhere (no string literals at call sites).

## File Structure

| File | Responsibility |
|---|---|
| `client/lib/models/vault_document.dart` | Additive `legacyImportVersion` marker |
| `client/lib/services/vault/vault_service.dart` | Marker read/write |
| `client/lib/services/vault/credential_capture.dart` | Create/update/verify/rollback entries for all owner kinds |
| `client/lib/services/vault/vault_unlock_gate.dart` | Unlock-before-write gate + typed blocked exception |
| `client/lib/pages/vault/vault_status_section.dart` | Unlock dialog returns success; router-based prompt |
| `client/lib/services/ssh/ssh_profile_vault_writer.dart` | Atomic SSH save (capture → profile → rollback) |
| `client/lib/services/vault/legacy_import.dart` | One-shot migration |
| `client/lib/services/github/github_credentials_store.dart` | GitHub vault pointer + legacy fallback |
| `client/lib/services/provider_usage/managed_provider_secret_store.dart` | Vault-aware managed-provider resolver |
| `client/lib/models/managed_provider.dart` | Optional `vaultEntryId` |
| `client/lib/cubits/app_provider_cubit.dart` | Capture on `upsertProvider`, entry delete on `deleteProvider` |
| `client/lib/pages/managed_providers/managed_provider_editor_page.dart` | Capture on save, vault-aware required-field check |
| `client/lib/pages/ssh_profiles/ssh_profile_form_dialog.dart` | Auto-capture; remove manual vault controls |
| `client/lib/pages/ssh_profile_setup_page.dart` | Same for the full-page editor |
| `client/lib/pages/ssh_profiles/ssh_profile_target_card.dart` / `ssh_profiles_section.dart` | Remove "move to vault" |
| `client/lib/cubits/ssh_profile_cubit.dart` | Remove `migrateToVault` |
| `client/lib/services/connect/paired_relay_tunnel_registry.dart` | Vault-first relay grant |
| `client/lib/app/app_shell.dart` | Wire gate/capture/importer/GitHub/managed resolver |
| `client/lib/main.dart` | Providers for gate + capture |
| `client/lib/cubits/vault_cubit.dart` | `onUnlocked` hook |

---

### Task 1: Vault document marker

**Files:**
- Modify: `client/lib/models/vault_document.dart`
- Modify: `client/lib/services/vault/vault_service.dart`
- Test: `client/test/models/vault_document_test.dart`
- Test: `client/test/services/vault/vault_service_test.dart`

**Interfaces:**
- Consumes: nothing new.
- Produces: `VaultDocument.legacyImportVersion` (int), `VaultDocument.copyWith({int? legacyImportVersion})`, `VaultService.legacyImportVersion` getter, `VaultService.markLegacyImported(int version)`.

- [ ] **Step 1: Write the failing model test**

Append to `client/test/models/vault_document_test.dart` inside `main()`:

```dart
  test('legacy import marker round-trips and defaults to zero', () {
    const document = VaultDocument(legacyImportVersion: 1);
    expect(document.toJson()['legacyImportVersion'], 1);
    expect(VaultDocument.fromJson(document.toJson()).legacyImportVersion, 1);
    expect(
      const VaultDocument().legacyImportVersion,
      0,
      reason: 'old documents have no marker',
    );
    expect(
      VaultDocument.fromJson({'version': 1, 'entries': []}).legacyImportVersion,
      0,
    );
  });

  test('marker participates in document equality', () {
    expect(
      const VaultDocument(legacyImportVersion: 1),
      isNot(const VaultDocument(legacyImportVersion: 0)),
    );
  });
```

- [ ] **Step 2: Run the model test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/models/vault_document_test.dart`
Expected: FAIL — `No named parameter with the name 'legacyImportVersion'`.

- [ ] **Step 3: Implement the marker**

In `client/lib/models/vault_document.dart`:

```dart
class VaultDocument {
  const VaultDocument({
    this.version = 1,
    this.entries = const [],
    this.legacyImportVersion = 0,
  });

  factory VaultDocument.fromJson(Map<String, Object?> json) {
    final version = (json['version'] as num?)?.toInt() ?? 1;
    if (version != 1) {
      throw const FormatException('Unsupported vault document version');
    }
    final rawEntries = json['entries'];
    return VaultDocument(
      version: version,
      entries: rawEntries is List
          ? [
              for (final raw in rawEntries)
                if (raw is Map)
                  VaultEntry.fromJson(Map<String, Object?>.from(raw)),
            ]
          : const [],
      legacyImportVersion:
          (json['legacyImportVersion'] as num?)?.toInt() ?? 0,
    );
  }

  final int version;
  final List<VaultEntry> entries;

  /// `0` until the one-shot legacy import completed a full pass.
  final int legacyImportVersion;

  Map<String, Object?> toJson() => {
    'version': version,
    if (legacyImportVersion > 0) 'legacyImportVersion': legacyImportVersion,
    'entries': [for (final entry in entries) entry.toJson()],
  };

  VaultDocument copyWith({
    List<VaultEntry>? entries,
    int? legacyImportVersion,
  }) => VaultDocument(
    version: version,
    entries: entries ?? this.entries,
    legacyImportVersion: legacyImportVersion ?? this.legacyImportVersion,
  );
```

Update `==`/`hashCode`/`props` to include `legacyImportVersion` (the existing class compares `version` and `entries` with `DeepCollectionEquality`).

- [ ] **Step 4: Write the failing service test**

Append to `client/test/services/vault/vault_service_test.dart` inside `main()`:

```dart
  test('marker persists through the keychain backend', () async {
    final store = _FakeStore();
    final service = buildService(store: store);
    await service.initialize();
    expect(service.legacyImportVersion, 0);

    await service.markLegacyImported(1);
    expect(service.legacyImportVersion, 1);

    final reloaded = buildService(store: store);
    await reloaded.initialize();
    expect(reloaded.legacyImportVersion, 1);
  });
```

- [ ] **Step 5: Run the service test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/services/vault/vault_service_test.dart`
Expected: FAIL — `The getter 'legacyImportVersion' isn't defined`.

- [ ] **Step 6: Implement the service accessors**

In `client/lib/services/vault/vault_service.dart`, after `isUnlocked`:

```dart
  /// `0` until the one-shot legacy import has completed.
  int get legacyImportVersion => _requireDocument().legacyImportVersion;

  Future<void> markLegacyImported(int version) {
    return _mutate(
      (document) => document.copyWith(legacyImportVersion: version),
    );
  }
```

- [ ] **Step 7: Run both tests**

Run: `cd client && dart run tool/run_tests.dart test/models/vault_document_test.dart test/services/vault/vault_service_test.dart`
Expected: `All tests passed!`

- [ ] **Step 8: Analyze and commit**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: `34 issues found.` (0 errors)

```bash
git add client/lib/models/vault_document.dart client/lib/services/vault/vault_service.dart client/test/models/vault_document_test.dart client/test/services/vault/vault_service_test.dart
git commit -m "feat(vault): persist a one-shot legacy import marker"
```

---

### Task 2: Capture service

**Files:**
- Create: `client/lib/services/vault/credential_capture.dart`
- Modify: `client/lib/services/vault/vault_service.dart` (add `verifyFields`)
- Test: `client/test/services/vault/credential_capture_test.dart`
- Test: `client/test/services/vault/vault_service_test.dart`

**Interfaces:**
- Consumes: `VaultService` (`list`, `get`, `upsert`, `delete`, `verifyFields`), `VaultEntry`, `SshProfile`, `AppProviderConfig`, `ManagedProvider`.
- Produces: `Future<bool> VaultService.verifyFields(String entryId, Map<String, String> fields)` — reloads the keychain backend and compares; encrypted backends compare the in-memory document (the passphrase is not retained after save).
- Produces:
  - consts `vaultOwnerKindSshProfile`, `vaultOwnerKindAppProvider`, `vaultOwnerKindManagedProvider`, `vaultOwnerKindGithub`
  - `class VaultCaptureResult { String entryId; bool created; VaultEntry? previous; }`
  - `class VaultCaptureException implements Exception { String reason; }`
  - `VaultCredentialCapture({required VaultService vault, Uuid? uuid})`
  - `Future<VaultCredentialCapture> ...`:
    - `captureSsh(SshProfile profile, {String? password, String? privateKey, String? passphrase, String? relayGrant})`
    - `captureProvider(AppProviderConfig provider, {String? apiKey})`
    - `captureManaged(ManagedProvider provider, Map<String, String> values)`
    - `captureGithub({required String token, String? login, String? source})`
    - `Future<VaultEntry?> findOwner(String ownerKind, String ownerId)`
    - `Future<void> rollback(VaultCaptureResult result)`
    - `Future<void> deleteOwner(String ownerKind, String ownerId)`

Merge semantics: `null` keeps an existing field, `''` removes it, a value overwrites it.

- [ ] **Step 1: Add the failing `verifyFields` test**

Append to `client/test/services/vault/vault_service_test.dart` inside `main()`:

```dart
  test('verifyFields reloads the keychain backend', () async {
    final store = _FakeStore();
    final service = buildService(store: store);
    await service.initialize();
    await service.upsert(
      const VaultEntry(
        id: 'a',
        type: VaultEntryType.token,
        title: 'A',
        fields: {'token': 't'},
      ),
    );
    expect(await service.verifyFields('a', {'token': 't'}), isTrue);
    expect(await service.verifyFields('a', {'token': 'other'}), isFalse);
    expect(await service.verifyFields('missing', {'token': 't'}), isFalse);
  });
```

Run it: `cd client && dart run tool/run_tests.dart test/services/vault/vault_service_test.dart`
Expected: FAIL — `The method 'verifyFields' isn't defined`.

Implement in `client/lib/services/vault/vault_service.dart`:

```dart
  /// Verifies that [fields] are present with these values.
  ///
  /// Keychain mode reloads the backend, so this is a real persistence
  /// round-trip. The encrypted backend does not retain the passphrase after
  /// save, so it compares the in-memory document that the awaited save
  /// already committed.
  Future<bool> verifyFields(String entryId, Map<String, String> fields) async {
    if (_locked) return false;
    VaultDocument? source;
    if (_encrypted) {
      source = _document;
    } else {
      try {
        source = await _keychainBackend.load();
      } on Object {
        return false;
      }
    }
    final entry = source?.entries.where((entry) => entry.id == entryId).firstOrNull;
    if (entry == null) return false;
    for (final field in fields.entries) {
      if (entry.fields[field.key] != field.value) return false;
    }
    return true;
  }
```

Import `package:collection/collection.dart` only if `firstOrNull` is not available; the file already uses plain loops, so prefer a loop:

```dart
    VaultEntry? entry;
    for (final candidate in source?.entries ?? const <VaultEntry>[]) {
      if (candidate.id == entryId) {
        entry = candidate;
        break;
      }
    }
```

Run the test again: expected PASS.

- [ ] **Step 2: Write the failing capture test**

Create `client/test/services/vault/credential_capture_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/app_provider_config.dart';
import 'package:teampilot/models/managed_provider.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/vault_entry.dart';
import 'package:teampilot/repositories/ssh_credential_store.dart';
import 'package:teampilot/repositories/vault_repository.dart';
import 'package:teampilot/services/vault/credential_capture.dart';
import 'package:teampilot/services/vault/encrypted_vault_backend.dart';
import 'package:teampilot/services/vault/keychain_vault_backend.dart';
import 'package:teampilot/services/vault/vault_crypto.dart';
import 'package:teampilot/services/vault/vault_service.dart';

import '../../support/in_memory_filesystem.dart';

class _FakeStore implements SecureKeyValueStore {
  final values = <String, String>{};

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

Future<VaultService> _service({_FakeStore? store}) async {
  final fs = InMemoryFilesystem(pathContext: p.Context(style: p.Style.posix));
  final service = VaultService(
    keychainBackend: KeychainVaultBackend(store ?? _FakeStore()),
    encryptedBackend: EncryptedVaultBackend(
      repository: VaultRepository(rootDir: '/root/vault', fs: fs),
      crypto: const VaultCrypto(memoryKiB: 256, iterations: 1, parallelism: 1),
    ),
  );
  await service.initialize();
  return service;
}

void main() {
  const passwordProfile = SshProfile(
    id: 'p1',
    name: 'Server',
    host: 'example.com',
    username: 'u',
  );

  test('captures an SSH password entry and is idempotent', () async {
    final service = await _service();
    final capture = VaultCredentialCapture(vault: service);

    final first = await capture.captureSsh(passwordProfile, password: 'secret');
    expect(first.created, isTrue);
    final entry = (await service.get(first.entryId))!;
    expect(entry.title, 'Server');
    expect(entry.type, VaultEntryType.sshPassword);
    expect(entry.fields['password'], 'secret');
    expect(entry.extra['ownerKind'], vaultOwnerKindSshProfile);
    expect(entry.extra['ownerId'], 'p1');

    final renamed = passwordProfile.copyWith(name: 'Renamed');
    final second = await capture.captureSsh(renamed, password: 'secret2');
    expect(second.created, isFalse);
    expect(second.entryId, first.entryId);
    expect((await service.get(first.entryId))!.title, 'Renamed');
    expect((await service.get(first.entryId))!.fields['password'], 'secret2');
  });

  test('switching auth type removes the old secret field', () async {
    final service = await _service();
    final capture = VaultCredentialCapture(vault: service);
    final id = (await capture.captureSsh(passwordProfile, password: 'pw')).entryId;

    final keyProfile = passwordProfile.copyWith(
      authType: SshAuthType.privateKey,
    );
    await capture.captureSsh(
      keyProfile,
      password: '',
      privateKey: 'PEM',
      passphrase: 'pass',
    );
    final entry = (await service.get(id))!;
    expect(entry.type, VaultEntryType.sshPrivateKey);
    expect(entry.fields.containsKey('password'), isFalse);
    expect(entry.fields['privateKey'], 'PEM');
    expect(entry.fields['passphrase'], 'pass');
    expect(entry.revealAllowed, isFalse);
  });

  test('captures a provider entry with the vault apiKey', () async {
    final service = await _service();
    final capture = VaultCredentialCapture(vault: service);
    const provider = AppProviderConfig(
      id: 'openai',
      cli: CliTool.codex,
      name: 'OpenAI',
      apiKey: 'sk-1',
      baseUrl: 'https://api.example.com',
    );

    final result = await capture.captureProvider(
      provider,
      apiKey: provider.apiKey,
    );
    final entry = (await service.get(result.entryId))!;
    expect(entry.title, 'OpenAI');
    expect(entry.fields['apiKey'], 'sk-1');
    expect(entry.fields['baseUrl'], 'https://api.example.com');
    expect(entry.tags, contains('provider'));

    await capture.captureProvider(
      provider.copyWith(name: 'OpenAI 2', apiKey: 'sk-2'),
      apiKey: 'sk-2',
    );
    expect((await service.get(result.entryId))!.fields['apiKey'], 'sk-2');
    expect(await service.readField(result.entryId, 'apiKey'), 'sk-2');
  });

  test('managed capture merges fields', () async {
    final service = await _service();
    final capture = VaultCredentialCapture(vault: service);
    final provider = ManagedProvider(
      id: 'm1',
      name: 'Usage',
      kind: ManagedProviderKind.apiBalance,
      adapterId: 'http_json_mapping',
    );

    final first = await capture.captureManaged(provider, {'apiKey': 'a'});
    await capture.captureManaged(provider, {'secretKey': 'b'});
    final entry = (await service.get(first.entryId))!;
    expect(entry.fields, {'apiKey': 'a', 'secretKey': 'b'});
    expect(entry.type, VaultEntryType.custom);
    expect(entry.tags, contains('usage'));
  });

  test('github capture stores token, login and source', () async {
    final service = await _service();
    final capture = VaultCredentialCapture(vault: service);
    final result = await capture.captureGithub(
      token: 'ghp_x',
      login: 'me',
      source: 'oauth',
    );
    final entry = (await service.get(result.entryId))!;
    expect(entry.fields, {'token': 'ghp_x', 'login': 'me', 'source': 'oauth'});
    expect(entry.extra['ownerKind'], vaultOwnerKindGithub);
    expect(entry.extra['ownerId'], 'default');
  });

  test('verify failure restores the previous entry', () async {
    final store = _FakeStore();
    final service = await _service(store: store);
    final capture = VaultCredentialCapture(vault: service);
    await capture.captureSsh(passwordProfile, password: 'old');

    final broken = _BrokenVerifyVaultService(store);
    await broken.initialize();
    final brokenCapture = VaultCredentialCapture(vault: broken);
    await expectLater(
      brokenCapture.captureSsh(passwordProfile, password: 'new'),
      throwsA(isA<VaultCaptureException>()),
    );

    final reloaded = await _service(store: store);
    expect(
      await reloaded.readField(
        (await reloaded.list()).single.id,
        'password',
      ),
      'old',
    );
  });

  test('rollback of an update restores the previous fields', () async {
    final store = _FakeStore();
    final service = await _service(store: store);
    final capture = VaultCredentialCapture(vault: service);
    await capture.captureSsh(passwordProfile, password: 'old');
    final updated = await capture.captureSsh(passwordProfile, password: 'new');
    expect(updated.created, isFalse);

    await capture.rollback(updated);
    expect(await service.readField(updated.entryId, 'password'), 'old');
  });
}

class _BrokenVerifyVaultService extends VaultService {
  _BrokenVerifyVaultService(_FakeStore store)
    : super(
        keychainBackend: KeychainVaultBackend(store),
        encryptedBackend: EncryptedVaultBackend(
          repository: VaultRepository(
            rootDir: '/root/vault',
            fs: InMemoryFilesystem(pathContext: p.Context(style: p.Style.posix)),
          ),
          crypto: const VaultCrypto(
            memoryKiB: 256,
            iterations: 1,
            parallelism: 1,
          ),
        ),
      );

  @override
  Future<bool> verifyFields(String entryId, Map<String, String> fields) async =>
      false;
}
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/services/vault/credential_capture_test.dart`
Expected: FAIL — `Couldn't resolve the package 'teampilot/services/vault/credential_capture.dart'`.

- [ ] **Step 4: Implement the capture service**

Create `client/lib/services/vault/credential_capture.dart`:

```dart
import 'package:uuid/uuid.dart';

import '../../models/app_provider_config.dart';
import '../../models/managed_provider.dart';
import '../../models/ssh_profile.dart';
import '../../models/vault_entry.dart';
import 'vault_service.dart';

const vaultOwnerKindSshProfile = 'sshProfile';
const vaultOwnerKindAppProvider = 'appProvider';
const vaultOwnerKindManagedProvider = 'managedProvider';
const vaultOwnerKindGithub = 'github';

class VaultCaptureResult {
  const VaultCaptureResult({
    required this.entryId,
    required this.created,
    this.previous,
  });

  final String entryId;
  final bool created;
  final VaultEntry? previous;
}

class VaultCaptureException implements Exception {
  const VaultCaptureException(this.reason);

  final String reason;

  @override
  String toString() => 'VaultCaptureException($reason)';
}

/// Creates or updates the vault entry that owns a credential.
///
/// Merge semantics for [fields]: `null` keeps the existing value, an empty
/// string removes the field, and a non-empty string overwrites it.
class VaultCredentialCapture {
  VaultCredentialCapture({required VaultService vault, Uuid? uuid})
    : _vault = vault,
      _uuid = uuid ?? const Uuid();

  final VaultService _vault;
  final Uuid _uuid;

  Future<VaultEntry?> findOwner(String ownerKind, String ownerId) async {
    for (final entry in await _vault.list()) {
      if (entry.extra['ownerKind'] == ownerKind &&
          entry.extra['ownerId'] == ownerId) {
        return entry;
      }
    }
    return null;
  }

  Future<VaultCaptureResult> captureSsh(
    SshProfile profile, {
    String? password,
    String? privateKey,
    String? passphrase,
    String? relayGrant,
  }) {
    final passwordAuth = profile.authType == SshAuthType.password;
    return _upsert(
      ownerKind: vaultOwnerKindSshProfile,
      ownerId: profile.id,
      type: passwordAuth
          ? VaultEntryType.sshPassword
          : VaultEntryType.sshPrivateKey,
      title: profile.name,
      tags: const ['ssh'],
      revealable: passwordAuth,
      fields: {
        'host': profile.host,
        'port': '${profile.port}',
        'username': profile.username,
        if (password != null) 'password': password,
        if (privateKey != null) 'privateKey': privateKey,
        if (passphrase != null) 'passphrase': passphrase,
        if (relayGrant != null) 'relayGrant': relayGrant,
      },
    );
  }

  /// [apiKey]: null keeps the stored key, an empty string removes it, a
  /// value overwrites it. Callers that have a key must pass it explicitly.
  Future<VaultCaptureResult> captureProvider(
    AppProviderConfig provider, {
    String? apiKey,
  }) {
    return _upsert(
      ownerKind: vaultOwnerKindAppProvider,
      ownerId: provider.id,
      type: VaultEntryType.apiKey,
      title: provider.name,
      tags: const ['provider'],
      revealable: true,
      fields: {
        'provider': provider.id,
        'baseUrl': provider.baseUrl,
        if (apiKey != null) 'apiKey': apiKey,
      },
    );
  }

  Future<VaultCaptureResult> captureManaged(
    ManagedProvider provider,
    Map<String, String> values,
  ) async {
    final existing = await findOwner(
      vaultOwnerKindManagedProvider,
      provider.id,
    );
    final merged = {...?existing?.fields, ...values}
      ..removeWhere((key, value) => value.isEmpty);
    return _upsert(
      ownerKind: vaultOwnerKindManagedProvider,
      ownerId: provider.id,
      type: merged.length <= 1
          ? VaultEntryType.apiKey
          : VaultEntryType.custom,
      title: provider.name,
      tags: const ['usage'],
      revealable: true,
      fields: values,
    );
  }

  Future<VaultCaptureResult> captureGithub({
    required String token,
    String? login,
    String? source,
  }) {
    return _upsert(
      ownerKind: vaultOwnerKindGithub,
      ownerId: 'default',
      type: VaultEntryType.token,
      title: 'GitHub',
      tags: const ['github'],
      revealable: true,
      fields: {
        'token': token,
        if (login != null) 'login': login,
        if (source != null) 'source': source,
      },
    );
  }

  Future<void> rollback(VaultCaptureResult result) async {
    if (result.created) {
      await _vault.delete(result.entryId);
      return;
    }
    final previous = result.previous;
    if (previous != null) {
      await _vault.upsert(previous);
    }
  }

  Future<void> deleteOwner(String ownerKind, String ownerId) async {
    final entry = await findOwner(ownerKind, ownerId);
    if (entry != null) await _vault.delete(entry.id);
  }

  Future<VaultCaptureResult> _upsert({
    required String ownerKind,
    required String ownerId,
    required VaultEntryType type,
    required String title,
    required List<String> tags,
    required bool revealable,
    required Map<String, String> fields,
  }) async {
    final existing = await findOwner(ownerKind, ownerId);
    final merged = {
      ...?existing?.fields,
      for (final entry in fields.entries)
        if (entry.value.isNotEmpty) entry.key: entry.value,
    };
    for (final entry in fields.entries) {
      if (entry.value.isEmpty) merged.remove(entry.key);
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final entry = VaultEntry(
      id: existing?.id ?? _uuid.v4(),
      type: type,
      title: title,
      fields: merged,
      tags: {...?existing?.tags, ...tags}.toList(growable: false),
      notes: existing?.notes ?? '',
      favorite: existing?.favorite ?? false,
      revealable: type == VaultEntryType.sshPrivateKey ? false : revealable,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
      extra: {
        ...?existing?.extra,
        'ownerKind': ownerKind,
        'ownerId': ownerId,
      },
    );
    await _vault.upsert(entry);
    if (!await _vault.verifyFields(entry.id, merged)) {
      if (existing == null) {
        await _vault.delete(entry.id);
      } else {
        await _vault.upsert(existing);
      }
      throw const VaultCaptureException('verifyFailed');
    }
    return VaultCaptureResult(
      entryId: entry.id,
      created: existing == null,
      previous: existing,
    );
  }
}
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `cd client && dart run tool/run_tests.dart test/services/vault/credential_capture_test.dart`
Expected: `All tests passed!`

- [ ] **Step 6: Analyze and commit**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: 0 errors.

```bash
git add client/lib/services/vault/credential_capture.dart client/lib/services/vault/vault_service.dart client/test/services/vault/credential_capture_test.dart client/test/services/vault/vault_service_test.dart
git commit -m "feat(vault): add credential capture with verify and rollback"
```

---

### Task 3: Unlock gate and dialog result

**Files:**
- Create: `client/lib/services/vault/vault_unlock_gate.dart`
- Modify: `client/lib/pages/vault/vault_status_section.dart`
- Modify: `client/lib/l10n/app_en.arb`, `client/lib/l10n/app_zh.arb`
- Test: `client/test/services/vault/vault_unlock_gate_test.dart`

**Interfaces:**
- Consumes: `VaultService.isUnlocked`, `showVaultUnlockDialog`.
- Produces: `class VaultSaveBlockedException`, `class VaultUnlockGate { Future<bool> ensureUnlocked(); }`, `Future<bool> showVaultUnlockDialog(BuildContext)` (now returns success), `Future<bool> promptVaultUnlockFromRouter()`.

- [ ] **Step 1: Add l10n strings**

Append to `client/lib/l10n/app_en.arb`:

```json
  "vaultLockedSaveBlocked": "Unlock the vault to save credentials.",
  "vaultUnavailable": "Credential vault is unavailable.",
  "vaultStoredInVault": "Stored in vault",
```

Append to `client/lib/l10n/app_zh.arb`:

```json
  "vaultLockedSaveBlocked": "请先解锁保险库再保存凭据。",
  "vaultUnavailable": "凭据保险库不可用。",
  "vaultStoredInVault": "已存入保险库",
```

Run: `cd client && flutter gen-l10n`
Expected: generated localization files update without errors.

- [ ] **Step 2: Write the failing gate test**

Create `client/test/services/vault/vault_unlock_gate_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/repositories/ssh_credential_store.dart';
import 'package:teampilot/repositories/vault_repository.dart';
import 'package:teampilot/services/vault/encrypted_vault_backend.dart';
import 'package:teampilot/services/vault/keychain_vault_backend.dart';
import 'package:teampilot/services/vault/vault_crypto.dart';
import 'package:teampilot/services/vault/vault_service.dart';
import 'package:teampilot/services/vault/vault_unlock_gate.dart';

import '../../support/in_memory_filesystem.dart';

class _FakeStore implements SecureKeyValueStore {
  final values = <String, String>{};

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

VaultService _service() => VaultService(
  keychainBackend: KeychainVaultBackend(_FakeStore()),
  encryptedBackend: EncryptedVaultBackend(
    repository: VaultRepository(
      rootDir: '/root/vault',
      fs: InMemoryFilesystem(pathContext: p.Context(style: p.Style.posix)),
    ),
    crypto: const VaultCrypto(memoryKiB: 256, iterations: 1, parallelism: 1),
  ),
);

void main() {
  test('unlocked vault skips the prompt', () async {
    final service = _service();
    await service.initialize();
    var prompts = 0;
    final gate = VaultUnlockGate(
      vault: service,
      prompt: () async {
        prompts++;
        return true;
      },
    );
    expect(await gate.ensureUnlocked(), isTrue);
    expect(prompts, 0);
  });

  test('refused prompt returns false', () async {
    final service = _service();
    await service.initialize();
    final gate = VaultUnlockGate(
      vault: _LockedVaultService(service),
      prompt: () async => false,
    );
    expect(await gate.ensureUnlocked(), isFalse);
  });
}

class _LockedVaultService implements VaultService {
  _LockedVaultService(this._delegate);

  final VaultService _delegate;

  @override
  bool get isUnlocked => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
```

Note: `VaultService` is a concrete class; `_LockedVaultService` only needs `isUnlocked` for this test. If `implements` complains about non-overridden members, replace it with a small subclass that overrides `isUnlocked` and delegates through `noSuchMethod` (as above).

- [ ] **Step 3: Run the test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/services/vault/vault_unlock_gate_test.dart`
Expected: FAIL — package file not found.

- [ ] **Step 4: Implement the gate**

Create `client/lib/services/vault/vault_unlock_gate.dart`:

```dart
import 'vault_service.dart';

class VaultSaveBlockedException implements Exception {
  const VaultSaveBlockedException();

  @override
  String toString() => 'VaultSaveBlockedException';
}

/// Ensures the vault is writable before a credential is captured.
class VaultUnlockGate {
  VaultUnlockGate({
    required VaultService vault,
    required Future<bool> Function() prompt,
  }) : _vault = vault,
       _prompt = prompt;

  final VaultService _vault;
  final Future<bool> Function() _prompt;

  Future<bool> ensureUnlocked() async {
    if (_vault.isUnlocked) return true;
    final prompted = await _prompt();
    return prompted && _vault.isUnlocked;
  }
}
```

- [ ] **Step 5: Refactor the unlock dialog to report success**

In `client/lib/pages/vault/vault_status_section.dart`, change `Future<void> showVaultUnlockDialog(BuildContext context)` to `Future<bool>` and return `cubit.state.unlocked` after `await cubit.unlock(passphrase)`. Return `false` when the dialog is cancelled or the passphrase is empty.

Add below it:

```dart
/// Router-based prompt for non-widget call sites (cubits, stores).
Future<bool> promptVaultUnlockFromRouter() async {
  final context = appRouter.routerDelegate.navigatorKey.currentContext;
  if (context == null) return false;
  return showVaultUnlockDialog(context);
}
```

Import `../../router/app_router.dart`.

Update the existing `VaultStatusSection` button:

```dart
onPressed: () => showVaultUnlockDialog(context),
```

(Return value intentionally ignored.)

- [ ] **Step 6: Run the gate test and the vault page tests**

Run: `cd client && dart run tool/run_tests.dart test/services/vault/vault_unlock_gate_test.dart test/pages/vault`
Expected: `All tests passed!`

- [ ] **Step 7: Analyze and commit**

```bash
git add client/lib/services/vault/vault_unlock_gate.dart client/lib/pages/vault/vault_status_section.dart client/lib/l10n client/test/services/vault/vault_unlock_gate_test.dart
git commit -m "feat(vault): add an unlock gate with an atomic save contract"
```

---
### Task 4: Atomic SSH profile writer

**Files:**
- Create: `client/lib/services/ssh/ssh_profile_vault_writer.dart`
- Test: `client/test/services/ssh/ssh_profile_vault_writer_test.dart`

**Interfaces:**
- Consumes: `VaultCredentialCapture`, `VaultUnlockGate`, `VaultSaveBlockedException`, `SshProfileRepository`, `SshCredentialStore`.
- Produces:
  - `class SshProfileVaultWriteResult { SshProfile profile; VaultCaptureResult capture; }`
  - `Future<SshProfileVaultWriteResult> saveSshProfileWithVault({required SshProfile profile, required String? password, required String? privateKey, required String? passphrase, required VaultCredentialCapture capture, required VaultUnlockGate unlockGate, required SshProfileRepository repository, required SshCredentialStore credentialStore})`

The writer is the single save path for both the desktop dialog and the full-page editor. It never writes the keychain.

- [ ] **Step 1: Write the failing test**

Create `client/test/services/ssh/ssh_profile_vault_writer_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/repositories/ssh_credential_store.dart';
import 'package:teampilot/repositories/ssh_profile_repository.dart';
import 'package:teampilot/repositories/vault_repository.dart';
import 'package:teampilot/services/ssh/ssh_profile_vault_writer.dart';
import 'package:teampilot/services/vault/credential_capture.dart';
import 'package:teampilot/services/vault/encrypted_vault_backend.dart';
import 'package:teampilot/services/vault/keychain_vault_backend.dart';
import 'package:teampilot/services/vault/vault_crypto.dart';
import 'package:teampilot/services/vault/vault_service.dart';
import 'package:teampilot/services/vault/vault_unlock_gate.dart';

import '../../support/in_memory_filesystem.dart';

class _FakeStore implements SecureKeyValueStore {
  final values = <String, String>{};

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

Future<VaultService> _vault({_FakeStore? store}) async {
  final service = VaultService(
    keychainBackend: KeychainVaultBackend(store ?? _FakeStore()),
    encryptedBackend: EncryptedVaultBackend(
      repository: VaultRepository(
        rootDir: '/root/vault',
        fs: InMemoryFilesystem(pathContext: p.Context(style: p.Style.posix)),
      ),
      crypto: const VaultCrypto(memoryKiB: 256, iterations: 1, parallelism: 1),
    ),
  );
  await service.initialize();
  return service;
}

void main() {
  const profile = SshProfile(
    id: 'p1',
    name: 'Server',
    host: 'example.com',
    username: 'u',
  );

  test('stores a password in the vault, links the profile and clears nothing', () async {
    final store = _FakeStore();
    final vault = await _vault(store: store);
    final repository = SshProfileRepository(storage: fakeHomeStorage());
    final credentials = InMemorySshCredentialStore();
    final capture = VaultCredentialCapture(vault: vault);
    final gate = VaultUnlockGate(vault: vault, prompt: () async => true);

    final result = await saveSshProfileWithVault(
      profile: profile,
      password: 'secret',
      privateKey: null,
      passphrase: null,
      capture: capture,
      unlockGate: gate,
      repository: repository,
      credentialStore: credentials,
    );

    expect(result.profile.vaultEntryId, result.capture.entryId);
    expect((await repository.loadAll()).single.vaultEntryId, result.capture.entryId);
    expect(await vault.readField(result.capture.entryId, 'password'), 'secret');
    expect(await credentials.loadPassword('p1'), isNull);
  });

  test('keeps the paired-relay grant inside the same entry', () async {
    final vault = await _vault();
    final repository = SshProfileRepository(storage: fakeHomeStorage());
    final credentials = InMemorySshCredentialStore();
    await credentials.saveRelayGrant('p1', 'grant-1');
    final capture = VaultCredentialCapture(vault: vault);

    final result = await saveSshProfileWithVault(
      profile: profile,
      password: 'secret',
      privateKey: null,
      passphrase: null,
      capture: capture,
      unlockGate: VaultUnlockGate(vault: vault, prompt: () async => true),
      repository: repository,
      credentialStore: credentials,
    );

    expect(await vault.readField(result.capture.entryId, 'relayGrant'), 'grant-1');
  });

  test('repository failure rolls the capture back', () async {
    final vault = await _vault();
    final credentials = InMemorySshCredentialStore();
    final capture = VaultCredentialCapture(vault: vault);

    await expectLater(
      saveSshProfileWithVault(
        profile: profile,
        password: 'secret',
        privateKey: null,
        passphrase: null,
        capture: capture,
        unlockGate: VaultUnlockGate(vault: vault, prompt: () async => true),
        repository: _ThrowingSshProfileRepository(),
        credentialStore: credentials,
      ),
      throwsA(isA<StateError>()),
    );
    expect(await vault.list(), isEmpty);
  });

  test('adopts legacy keychain secrets and deletes them after save', () async {
    final vault = await _vault();
    final repository = SshProfileRepository(storage: fakeHomeStorage());
    final credentials = InMemorySshCredentialStore();
    await credentials.savePassword('p1', 'legacy');
    final capture = VaultCredentialCapture(vault: vault);

    final result = await saveSshProfileWithVault(
      profile: profile,
      password: '',
      privateKey: null,
      passphrase: null,
      capture: capture,
      unlockGate: VaultUnlockGate(vault: vault, prompt: () async => true),
      repository: repository,
      credentialStore: credentials,
    );

    expect(await vault.readField(result.capture.entryId, 'password'), 'legacy');
    expect(await credentials.loadPassword('p1'), isNull);
  });

  test('blocked vault aborts without saving the profile or an entry', () async {
    final vault = await _vault();
    final repository = SshProfileRepository(storage: fakeHomeStorage());
    final credentials = InMemorySshCredentialStore();
    final capture = VaultCredentialCapture(vault: vault);
    final blocked = VaultUnlockGate(
      vault: _LockedVaultService(vault),
      prompt: () async => false,
    );

    await expectLater(
      saveSshProfileWithVault(
        profile: profile,
        password: 'secret',
        privateKey: null,
        passphrase: null,
        capture: capture,
        unlockGate: blocked,
        repository: repository,
        credentialStore: credentials,
      ),
      throwsA(isA<VaultSaveBlockedException>()),
    );
    expect(await repository.loadAll(), isEmpty);
    expect(await vault.list(), isEmpty);
  });
}

class _ThrowingSshProfileRepository implements SshProfileRepository {
  @override
  Future<void> save(SshProfile profile) async => throw StateError('save failed');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _LockedVaultService implements VaultService {
  _LockedVaultService(this._delegate);

  final VaultService _delegate;

  @override
  bool get isUnlocked => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/services/ssh/ssh_profile_vault_writer_test.dart`
Expected: FAIL — package file not found.

- [ ] **Step 3: Implement the writer**

Create `client/lib/services/ssh/ssh_profile_vault_writer.dart`:

```dart
import '../../models/ssh_profile.dart';
import '../../repositories/ssh_credential_store.dart';
import '../../repositories/ssh_profile_repository.dart';
import '../vault/credential_capture.dart';
import '../vault/vault_unlock_gate.dart';

class SshProfileVaultWriteResult {
  const SshProfileVaultWriteResult({
    required this.profile,
    required this.capture,
  });

  final SshProfile profile;
  final VaultCaptureResult capture;
}

/// Captures SSH secrets in the vault, then saves the profile metadata.
///
/// Field semantics match the capture service: `null` keeps the stored value,
/// `''` removes it, a value overwrites it. For a profile that is not linked
/// yet, empty password/key/passphrase arguments are filled from the legacy
/// keychain so an edit never silently drops an existing secret.
///
/// The keychain is never written. After the profile is saved, its legacy
/// keychain secrets are deleted (best effort); a failure there does not fail
/// the save because the vault already holds the values.
Future<SshProfileVaultWriteResult> saveSshProfileWithVault({
  required SshProfile profile,
  required String? password,
  required String? privateKey,
  required String? passphrase,
  required VaultCredentialCapture capture,
  required VaultUnlockGate unlockGate,
  required SshProfileRepository repository,
  required SshCredentialStore credentialStore,
}) async {
  if (!await unlockGate.ensureUnlocked()) {
    throw const VaultSaveBlockedException();
  }
  final linked = (profile.vaultEntryId ?? '').isNotEmpty;
  var effectivePassword = password;
  var effectivePrivateKey = privateKey;
  var effectivePassphrase = passphrase;
  if (!linked) {
    if (profile.authType == SshAuthType.password &&
        (effectivePassword == null || effectivePassword.isEmpty)) {
      effectivePassword = await credentialStore.loadPassword(profile.id);
    }
    if (profile.authType == SshAuthType.privateKey) {
      if (effectivePrivateKey == null || effectivePrivateKey.isEmpty) {
        effectivePrivateKey = await credentialStore.loadPrivateKey(profile.id);
      }
      if (effectivePassphrase == null || effectivePassphrase.isEmpty) {
        effectivePassphrase = await credentialStore.loadPrivateKeyPassphrase(
          profile.id,
        );
      }
    }
  }
  final relayGrant = await credentialStore.loadRelayGrant(profile.id);
  final result = await capture.captureSsh(
    profile,
    password: effectivePassword,
    privateKey: effectivePrivateKey,
    passphrase: effectivePassphrase,
    relayGrant: relayGrant,
  );
  final saved = profile.copyWith(vaultEntryId: result.entryId);
  try {
    await repository.save(saved);
  } on Object {
    try {
      await capture.rollback(result);
    } on Object {
      // Preserve the repository error; the final review can spot orphans.
    }
    rethrow;
  }
  try {
    await credentialStore.deleteAll(profile.id);
  } on Object {
    // Best effort: the vault already holds the values.
  }
  return SshProfileVaultWriteResult(profile: saved, capture: result);
}
```

- [ ] **Step 4: Run the test**

Run: `cd client && dart run tool/run_tests.dart test/services/ssh/ssh_profile_vault_writer_test.dart`
Expected: `All tests passed!`

- [ ] **Step 5: Analyze and commit**

```bash
git add client/lib/services/ssh/ssh_profile_vault_writer.dart client/test/services/ssh/ssh_profile_vault_writer_test.dart
git commit -m "feat(vault): add an atomic SSH profile writer"
```

---

### Task 5: SSH forms and list use vault-first

**Files:**
- Modify: `client/lib/pages/ssh_profiles/ssh_profile_form_dialog.dart`
- Modify: `client/lib/pages/ssh_profile_setup_page.dart`
- Modify: `client/lib/pages/ssh_profiles/ssh_profile_target_card.dart`
- Modify: `client/lib/pages/ssh_profiles/ssh_profiles_section.dart`
- Modify: `client/lib/cubits/ssh_profile_cubit.dart`
- Delete: `client/test/pages/ssh_profiles/ssh_vault_link_test.dart`
- Test: `client/test/pages/ssh_profiles/ssh_profiles_section_test.dart` (regression)

**Interfaces:**
- Consumes: `saveSshProfileWithVault`.
- Produces: `SshEditorSecretInputs sshEditorSecretInputs({required SshAuthType authType, required bool linked, required String passwordText, required String privateKeyPem, required String passphraseText})` in `ssh_profile_vault_writer.dart`; removes `SshProfileCubit.migrateToVault` and `SshProfileTargetCard.onMigrate`.

- [ ] **Step 1: Add the editor field-mapping helper and its test**

Append to `client/lib/services/ssh/ssh_profile_vault_writer.dart`:

```dart
typedef SshEditorSecretInputs = ({
  String? password,
  String? privateKey,
  String? passphrase,
});

/// Maps editor field state to the writer's null/''/value contract.
///
/// A linked profile keeps an emptied field (`null`); an unlinked profile
/// passes `''` so the writer can adopt the legacy keychain value. The
/// inactive auth-type fields are always `''` (remove).
SshEditorSecretInputs sshEditorSecretInputs({
  required SshAuthType authType,
  required bool linked,
  required String passwordText,
  required String privateKeyPem,
  required String passphraseText,
}) {
  if (authType == SshAuthType.password) {
    return (
      password: passwordText.isEmpty ? (linked ? null : '') : passwordText,
      privateKey: '',
      passphrase: '',
    );
  }
  return (
    password: '',
    privateKey: privateKeyPem.isEmpty ? null : privateKeyPem,
    passphrase: passphraseText.isEmpty ? null : passphraseText,
  );
}
```

Append to `client/test/services/ssh/ssh_profile_vault_writer_test.dart` inside `main()`:

```dart
  test('editor mapping keeps linked empties and clears the inactive auth', () {
    expect(
      sshEditorSecretInputs(
        authType: SshAuthType.password,
        linked: true,
        passwordText: '',
        privateKeyPem: '',
        passphraseText: '',
      ),
      (password: null, privateKey: '', passphrase: ''),
    );
    expect(
      sshEditorSecretInputs(
        authType: SshAuthType.privateKey,
        linked: true,
        passwordText: '',
        privateKeyPem: '',
        passphraseText: '',
      ),
      (password: '', privateKey: null, passphrase: null),
    );
    expect(
      sshEditorSecretInputs(
        authType: SshAuthType.password,
        linked: false,
        passwordText: '',
        privateKeyPem: '',
        passphraseText: '',
      ).password,
      '',
      reason: 'unlinked empty lets the writer adopt the keychain value',
    );
  });
```

- [ ] **Step 2: Update the desktop dialog**

In `client/lib/pages/ssh_profiles/ssh_profile_form_dialog.dart`:

1. Replace imports: add `../../services/ssh/ssh_profile_vault_writer.dart`, `../../services/vault/credential_capture.dart`, `../../services/vault/vault_unlock_gate.dart`; remove `dart:async`, `../../models/vault_entry.dart`, `../../services/vault/vault_service.dart` stays (test connection).
2. Remove the fields `_vaultEntries`, `_vaultEntryId`, `_saveToVault`; remove `_selectedVaultEntry`, `_loadVaultEntries`, and the `unawaited(_loadVaultEntries())` call in `initState`.
3. Replace `_usesPasswordAuth` with:

```dart
  bool get _usesPasswordAuth {
    if (_identityFileController.text.isNotEmpty) return false;
    if (_passwordController.text.isNotEmpty) return true;
    return widget.initialProfile?.authType == SshAuthType.password;
  }
```

4. In `_buildProfile`, set `vaultEntryId: widget.initialProfile?.vaultEntryId`.
5. Delete `_persistCredentials` entirely.
6. Replace `_save` with:

```dart
  Future<SshProfile?> _save({required bool notify}) async {
    if (_formKey.currentState?.validate() != true) return null;
    final profile = _buildProfile();
    if (!_isEditing &&
        !_usesPasswordAuth &&
        _identityFileController.text.trim().isEmpty) {
      AppToast.show(
        context,
        message: context.l10n.sshProfileFormCredentialRequired,
        variant: TpToastVariant.warning,
      );
      return null;
    }
    try {
      final linked =
          (widget.initialProfile?.vaultEntryId ?? '').isNotEmpty;
      final privateKeyPem = _usesPasswordAuth
          ? ''
          : (await _readIdentityFile() ?? '');
      final inputs = sshEditorSecretInputs(
        authType: _usesPasswordAuth
            ? SshAuthType.password
            : SshAuthType.privateKey,
        linked: linked,
        passwordText: _passwordController.text,
        privateKeyPem: privateKeyPem,
        passphraseText: _passphraseController.text,
      );
      final result = await saveSshProfileWithVault(
        profile: profile,
        password: inputs.password,
        privateKey: inputs.privateKey,
        passphrase: inputs.passphrase,
        capture: context.read<VaultCredentialCapture>(),
        unlockGate: context.read<VaultUnlockGate>(),
        repository: context.read<SshProfileRepository>(),
        credentialStore: context.read<SshCredentialStore>(),
      );
      if (!mounted) return result.profile;
      if (notify) {
        await context.read<SshProfileCubit>().load();
        if (mounted) Navigator.of(context).pop();
      }
      return result.profile;
    } on VaultSaveBlockedException {
      if (mounted) {
        AppToast.show(
          context,
          message: context.l10n.vaultLockedSaveBlocked,
          variant: TpToastVariant.error,
        );
      }
      return null;
    } on Object {
      if (mounted) {
        AppToast.show(
          context,
          message: context.l10n.sshProfileFormCredentialSaveFailed,
          variant: TpToastVariant.warning,
        );
      }
      return null;
    }
  }
```

7. In `_testConnection`, replace every `_vaultEntryId` with `widget.initialProfile?.vaultEntryId` (use a local `final linkedId = widget.initialProfile?.vaultEntryId;` and branch on `linkedId != null && linkedId.isNotEmpty`, reading the vault as before).
8. Delete the credential-source `TpSelect` block and the "Save to vault" `CheckboxListTile` from the form children. Keep the `onChanged: () => setState(() {})` arguments on the identity/password fields.

- [ ] **Step 2: Update the full-page setup editor**

In `client/lib/pages/ssh_profile_setup_page.dart`:

1. Add optional constructor deps:

```dart
    this.vaultCapture,
    this.vaultUnlockGate,
```

and fields:

```dart
  final VaultCredentialCapture? vaultCapture;
  final VaultUnlockGate? vaultUnlockGate;
```

2. Remove `_vaultEntries`, `_vaultEntryId`, `_saveToVault`, `_selectedVaultEntry`, `_loadVaultEntries`, the `unawaited(...)` call, the credential-source `TpSelect`, the checkbox, and `_migrateToVault`.
3. `_buildProfile`: replace `vaultEntryId: _vaultEntryId` with `vaultEntryId: widget.initialProfile?.vaultEntryId`.
4. Replace `_saveProfile` with:

```dart
  Future<SshProfile?> _saveProfile({required bool notify}) async {
    if (!(_formKey.currentState?.validate() ?? false)) return null;
    final profile = _buildProfile();
    final linked = (widget.initialProfile?.vaultEntryId ?? '').isNotEmpty;
    if (!linked &&
        !_isEditing &&
        _authType == SshAuthType.privateKey &&
        _privateKeyController.text.trim().isEmpty) {
      AppToast.show(
        context,
        message: context.l10n.sshProfileFormCredentialRequired,
        variant: TpToastVariant.warning,
      );
      return null;
    }
    try {
      final inputs = sshEditorSecretInputs(
        authType: _authType,
        linked: linked,
        passwordText: _passwordController.text,
        privateKeyPem: _privateKeyController.text,
        passphraseText: _passphraseController.text,
      );
      final result = await saveSshProfileWithVault(
        profile: profile,
        password: inputs.password,
        privateKey: inputs.privateKey,
        passphrase: inputs.passphrase,
        capture: widget.vaultCapture ?? context.read<VaultCredentialCapture>(),
        unlockGate:
            widget.vaultUnlockGate ?? context.read<VaultUnlockGate>(),
        repository: widget.profileRepository,
        credentialStore: widget.credentialStore,
      );
      if (mounted && notify) widget.onProfileSaved?.call();
      return result.profile;
    } on VaultSaveBlockedException {
      if (mounted) {
        AppToast.show(
          context,
          message: context.l10n.vaultLockedSaveBlocked,
          variant: TpToastVariant.error,
        );
      }
      return null;
    } on Object {
      if (mounted) {
        AppToast.show(
          context,
          message: context.l10n.sshProfileFormCredentialSaveFailed,
          variant: TpToastVariant.warning,
        );
      }
      return null;
    }
  }
```

5. In `_testConnection`, replace the vault branch to use `widget.initialProfile?.vaultEntryId` and the injected vault service (already `widget.vaultService`). Remove the `_vaultEntryId` reads.
6. Validators: require password/private key only when `widget.initialProfile?.vaultEntryId` is empty (replace the previous `_vaultEntryId == null` conditions).

- [ ] **Step 3: Remove the migration button and method**

In `client/lib/pages/ssh_profiles/ssh_profile_target_card.dart`:
- Remove the `onMigrate` constructor parameter, field, and the `Align(... TextButton(...))` block.

In `client/lib/pages/ssh_profiles/ssh_profiles_section.dart`:
- Remove the `onMigrate:` argument passed to `SshProfileTargetCard`.

In `client/lib/cubits/ssh_profile_cubit.dart`:
- Delete `migrateToVault`.
- Remove the now-unused `vaultService` constructor parameter/field and imports `package:uuid/uuid.dart`, `../models/vault_entry.dart`, `../services/vault/vault_service.dart`.

Delete `client/test/pages/ssh_profiles/ssh_vault_link_test.dart`.

- [ ] **Step 4: Run the SSH-focused tests**

Run: `cd client && dart run tool/run_tests.dart test/pages/ssh_profiles test/services/ssh test/pages/startup_gate_test.dart test/pages/onboarding/work_home_step_test.dart`
Expected: `All tests passed!`

- [ ] **Step 5: Analyze and commit**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: 0 errors (unused l10n keys are fine).

```bash
git add client/lib/pages/ssh_profiles client/lib/pages/ssh_profile_setup_page.dart client/lib/cubits/ssh_profile_cubit.dart client/test/pages/ssh_profiles
git commit -m "feat(vault): capture SSH credentials on save and drop manual linking"
```

---

### Task 6: Provider capture on upsert

**Files:**
- Modify: `client/lib/cubits/app_provider_cubit.dart`
- Modify: `client/lib/widgets/app_provider/app_provider_form_sheet.dart`
- Test: `client/test/cubits/app_provider_cubit_test.dart`

**Interfaces:**
- Consumes: `VaultCredentialCapture`, `VaultUnlockGate`, `vaultOwnerKindAppProvider`.
- Produces: `AppProviderCubit({VaultCredentialCapture? vaultCapture, Future<bool> Function()? ensureVaultUnlocked, ...})`; `upsertProvider` now links and clears the plaintext key.

- [ ] **Step 1: Write the failing cubit tests**

Append to `client/test/cubits/app_provider_cubit_test.dart` inside `main()` (add imports for `VaultCredentialCapture`, `VaultService`, backends, `VaultRepository`, `InMemoryFilesystem`, `path`, `SecureKeyValueStore`):

```dart
  test('saving a key captures it in the vault and clears the plaintext', () async {
    final vault = await _vaultService();
    final capture = VaultCredentialCapture(vault: vault);
    final autoCubit = AppProviderCubit(
      repository: repository,
      basePath: temp.path,
      storage: fakeHomeStorage(),
      vaultCapture: capture,
      ensureVaultUnlocked: () async => true,
    );
    addTearDown(autoCubit.close);
    await autoCubit.load();

    const draft = AppProviderConfig(
      id: 'captured',
      cli: CliTool.claude,
      name: 'Captured',
      apiKey: 'sk-secret',
    );
    expect(await autoCubit.upsertProvider(draft), isTrue);

    final saved = autoCubit.state.providersFor(CliTool.claude)
        .firstWhere((p) => p.id == 'captured');
    expect(saved.apiKey, isEmpty);
    expect(saved.credentialLink, startsWith('vault:'));
    final entryId = saved.credentialLink.substring('vault:'.length);
    expect(await vault.readField(entryId, 'apiKey'), 'sk-secret');

    await autoCubit.deleteProvider('captured');
    expect(await vault.get(entryId), isNull);
  });

  test('a refused unlock aborts the save', () async {
    final vault = await _vaultService();
    final autoCubit = AppProviderCubit(
      repository: repository,
      basePath: temp.path,
      storage: fakeHomeStorage(),
      vaultCapture: VaultCredentialCapture(vault: _LockedVaultService(vault)),
      ensureVaultUnlocked: () async => false,
    );
    addTearDown(autoCubit.close);
    await autoCubit.load();

    const draft = AppProviderConfig(
      id: 'blocked',
      cli: CliTool.claude,
      name: 'Blocked',
      apiKey: 'sk-secret',
    );
    expect(await autoCubit.upsertProvider(draft), isFalse);
    expect(autoCubit.state.providersFor(CliTool.claude), isEmpty);
  });
```

Add helpers at file scope:

```dart
Future<VaultService> _vaultService() async {
  final service = VaultService(
    keychainBackend: KeychainVaultBackend(_FakeVaultStore()),
    encryptedBackend: EncryptedVaultBackend(
      repository: VaultRepository(
        rootDir: '/root/vault',
        fs: InMemoryFilesystem(pathContext: p.Context(style: p.Style.posix)),
      ),
      crypto: const VaultCrypto(memoryKiB: 256, iterations: 1, parallelism: 1),
    ),
  );
  await service.initialize();
  return service;
}

class _FakeVaultStore implements SecureKeyValueStore {
  final values = <String, String>{};

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

class _LockedVaultService implements VaultService {
  _LockedVaultService(this._delegate);

  final VaultService _delegate;

  @override
  bool get isUnlocked => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd client && dart run tool/run_tests.dart test/cubits/app_provider_cubit_test.dart`
Expected: FAIL — `No named parameter with the name 'vaultCapture'`.

- [ ] **Step 3: Implement capture in the cubit**

In `client/lib/cubits/app_provider_cubit.dart`:

1. Imports: `../services/vault/credential_capture.dart`.
2. Constructor params and fields:

```dart
    VaultCredentialCapture? vaultCapture,
    Future<bool> Function()? ensureVaultUnlocked,
```

```dart
       _vaultCapture = vaultCapture,
       _ensureVaultUnlocked = ensureVaultUnlocked,
```

```dart
  final VaultCredentialCapture? _vaultCapture;
  final Future<bool> Function()? _ensureVaultUnlocked;
```

3. In `upsertProvider`, after the cycle guard and before `final current = ...`:

```dart
    final capture = _vaultCapture;
    var effectiveLink = provider.credentialLink.trim();
    var effectiveApiKey = provider.apiKey;
    if (capture != null &&
        (effectiveLink.startsWith('vault:') || provider.apiKey.isNotEmpty)) {
      final unlock = _ensureVaultUnlocked;
      if (unlock != null && !await unlock()) return false;
      final captured = await capture.captureProvider(
        provider,
        apiKey: provider.apiKey.isEmpty ? null : provider.apiKey,
      );
      effectiveLink = 'vault:${captured.entryId}';
      effectiveApiKey = '';
    }
```

4. In `provider.copyWith(...)` add:

```dart
      credentialLink: effectiveLink,
      apiKey: effectiveApiKey,
```

5. In `deleteProvider`, before filtering:

```dart
    final target = state.providers.where((p) => p.id == id).firstOrNull;
    if (target != null && target.credentialLink.trim().startsWith('vault:')) {
      final unlock = _ensureVaultUnlocked;
      if (unlock != null && !await unlock()) return;
      await _vaultCapture?.deleteOwner(vaultOwnerKindAppProvider, id);
    }
```

- [ ] **Step 4: Remove vault options from the provider form**

In `client/lib/widgets/app_provider/app_provider_form_sheet.dart`:

1. Remove `_vaultEntries`, `_loadVaultEntries`, `_vaultOf`, the `unawaited(_loadVaultEntries())` call, and imports `dart:async`, `../../models/vault_entry.dart`, `../../services/vault/vault_service.dart`.
2. Remove the `for (final entry in _vaultEntries) { options.add(...) }` block from `_credentialLinkOptions`.
3. In `_linkedEntryName`, replace the vault branch body with:

```dart
    if (vaultEntryIdFromCredentialLink(link) != null) {
      return context.l10n.vaultStoredInVault;
    }
```

Keep the `vault_credential_link.dart` import.

- [ ] **Step 5: Run the tests**

Run: `cd client && dart run tool/run_tests.dart test/cubits/app_provider_cubit_test.dart test/app/provider_vault_link_test.dart test/repositories/app_provider_repository_credential_link_test.dart`
Expected: `All tests passed!`

- [ ] **Step 6: Analyze and commit**

```bash
git add client/lib/cubits/app_provider_cubit.dart client/lib/widgets/app_provider/app_provider_form_sheet.dart client/test/cubits/app_provider_cubit_test.dart
git commit -m "feat(vault): capture provider API keys on every upsert"
```

---
### Task 7: Managed-provider reference and runtime read

**Files:**
- Modify: `client/lib/models/managed_provider.dart`
- Modify: `client/lib/services/provider_usage/managed_provider_secret_store.dart`
- Modify: `client/lib/app/app_shell.dart`
- Test: `client/test/models/managed_provider_test.dart`
- Test: `client/test/services/provider_usage/managed_provider_credential_link_resolver_test.dart`

**Interfaces:**
- Consumes: `VaultService.get`.
- Produces: `ManagedProvider.vaultEntryId` (nullable `String`), `ManagedProviderCredentialResolver({VaultService? vault})` reading vault entries first.

- [ ] **Step 1: Write the failing model test**

Append to `client/test/models/managed_provider_test.dart` inside `main()`:

```dart
  test('vaultEntryId round-trips and stays absent when null', () {
    final provider = ManagedProvider(
      id: 'm1',
      name: 'Usage',
      kind: ManagedProviderKind.apiBalance,
      adapterId: 'http_json_mapping',
      vaultEntryId: 'v1',
    );
    expect(ManagedProvider.fromJson(provider.toJson()).vaultEntryId, 'v1');

    final plain = ManagedProvider(
      id: 'm2',
      name: 'Plain',
      kind: ManagedProviderKind.apiBalance,
      adapterId: 'http_json_mapping',
    );
    expect(plain.toJson().containsKey('vaultEntryId'), isFalse);
    expect(ManagedProvider.fromJson(plain.toJson()).vaultEntryId, isNull);
  });
```

- [ ] **Step 2: Run the model test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/models/managed_provider_test.dart`
Expected: FAIL — `No named parameter with the name 'vaultEntryId'`.

- [ ] **Step 3: Add the field to the model**

In `client/lib/models/managed_provider.dart`:

1. Factory parameter after `credentialRef`:

```dart
    String? vaultEntryId,
```

and pass it to `_`:

```dart
    vaultEntryId: vaultEntryId,
```

2. Private constructor:

```dart
    this.vaultEntryId,
```

3. `fromJson`:

```dart
        vaultEntryId: json['vaultEntryId'] as String?,
```

and add `'vaultEntryId'` to the `known` set passed to `_unknownFields`.

4. Field:

```dart
  final String? vaultEntryId;
```

5. `copyWith` parameter `String? vaultEntryId` and `vaultEntryId: vaultEntryId ?? this.vaultEntryId`.

6. `toJson`:

```dart
    if (vaultEntryId != null) 'vaultEntryId': vaultEntryId,
```

7. Add `vaultEntryId` to `props`.

- [ ] **Step 4: Write the failing resolver test**

Append to `client/test/services/provider_usage/managed_provider_credential_link_resolver_test.dart` inside `main()`:

```dart
  test('vaultEntryId reads the entry before the legacy store', () async {
    final vault = VaultService(
      keychainBackend: KeychainVaultBackend(_FakeSecureKeyValueStore()),
      encryptedBackend: EncryptedVaultBackend(
        repository: VaultRepository(
          rootDir: '/root/vault',
          fs: InMemoryFilesystem(pathContext: p.Context(style: p.Style.posix)),
        ),
        crypto: const VaultCrypto(memoryKiB: 256, iterations: 1, parallelism: 1),
      ),
    );
    await vault.initialize();
    await vault.upsert(
      const VaultEntry(
        id: 'v1',
        type: VaultEntryType.apiKey,
        title: 'Usage',
        fields: {'apiKey': 'from-vault'},
      ),
    );
    final store = ManagedProviderSecretStore(_FakeSecureKeyValueStore());
    await store.write('managed-provider:m1', {'apiKey': 'from-store'});
    final resolver = ManagedProviderCredentialResolver(store, vault: vault);
    final provider = _secretEntry().copyWith(vaultEntryId: 'v1');

    final scope = await resolver.resolve(provider);
    expect(scope?.valueFor('apiKey'), 'from-vault');
  });
```

Add imports `dart:io`-free `package:path/path.dart as p`, `VaultEntry`, `VaultRepository`, `EncryptedVaultBackend`, `KeychainVaultBackend`, `VaultCrypto`, `VaultService`.

- [ ] **Step 5: Run the resolver test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/services/provider_usage/managed_provider_credential_link_resolver_test.dart`
Expected: FAIL — `No named parameter with the name 'vault'`.

- [ ] **Step 6: Implement the vault read branch**

In `client/lib/services/provider_usage/managed_provider_secret_store.dart`:

1. Import `../vault/vault_service.dart`.
2. Constructor:

```dart
  ManagedProviderCredentialResolver(
    this._store, {
    AppProviderRepository? appProviders,
    VaultService? vault,
  }) : _appProviders = appProviders,
       _vault = vault;
```

3. Field `final VaultService? _vault;`
4. In `resolve`, before the legacy ref branch:

```dart
    final vaultEntryId = provider.vaultEntryId?.trim() ?? '';
    if (vaultEntryId.isNotEmpty) {
      final entry = await _vault?.get(vaultEntryId);
      if (entry == null || entry.fields.isEmpty) return null;
      return ManagedProviderCredentialScope({
        for (final field in entry.fields.entries)
          if (field.value.isNotEmpty) field.key: field.value,
      });
    }
```

- [ ] **Step 7: Wire the resolver and the delete hook in `app_shell.dart`**

1. Resolver construction (around the existing `ManagedProviderCredentialResolver(` call):

```dart
        credentials: ManagedProviderCredentialResolver(
          resolvedManagedProviderSecretStore,
          appProviders: AppProviderRepository(storage: homeStorage),
          vault: vaultService,
        ),
```

2. `onProviderDeletedCredentialCleanup`:

```dart
        onProviderDeletedCredentialCleanup: (provider) async {
          final vaultEntryId = provider.vaultEntryId?.trim() ?? '';
          if (vaultEntryId.isNotEmpty) {
            await vaultService.delete(vaultEntryId);
          }
          final ref = provider.credentialRef?.trim();
          if (ref != null && ref.isNotEmpty) {
            await resolvedManagedProviderSecretStore.delete(ref);
          }
          await ManagedProviderLinkJanitor(
            appProviderCubit: appProviderCubit,
          ).clearLinksFor(provider.id);
        },
```

3. The managed-provider branch of `appProviderLinkedCredentialLookup` reads vault first:

```dart
    final vaultEntryId = entry.vaultEntryId?.trim() ?? '';
    if (vaultEntryId.isNotEmpty) {
      final field = entry.endpointConfig.credentialField ?? 'apiKey';
      return vaultService.readField(vaultEntryId, field);
    }
    final ref = entry.credentialRef?.trim();
```

- [ ] **Step 8: Run the tests and analyze**

Run: `cd client && dart run tool/run_tests.dart test/models/managed_provider_test.dart test/services/provider_usage/managed_provider_credential_link_resolver_test.dart test/cubits/managed_provider_cubit_test.dart`
Expected: `All tests passed!`

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: 0 errors.

- [ ] **Step 9: Commit**

```bash
git add client/lib/models/managed_provider.dart client/lib/services/provider_usage/managed_provider_secret_store.dart client/lib/app/app_shell.dart client/test/models/managed_provider_test.dart client/test/services/provider_usage/managed_provider_credential_link_resolver_test.dart
git commit -m "feat(vault): read managed-provider credentials from the vault"
```

---

### Task 8: Managed-provider capture on save

**Files:**
- Create: `client/lib/services/provider_usage/managed_provider_vault_writer.dart`
- Modify: `client/lib/services/vault/credential_capture.dart` (add `existingManagedFields`)
- Modify: `client/lib/pages/managed_providers/managed_provider_editor_page.dart`
- Test: `client/test/services/provider_usage/managed_provider_vault_writer_test.dart`

**Interfaces:**
- Consumes: `VaultCredentialCapture`, `VaultUnlockGate`, `VaultSaveBlockedException`.
- Produces: `Future<ManagedProvider> saveManagedProviderWithVault({required ManagedProvider provider, required ManagedProvider? current, required Map<String, String> secretValues, required VaultCredentialCapture capture, required VaultUnlockGate unlockGate, required Future<void> Function(ManagedProvider) persist})`; `VaultCredentialCapture.existingManagedFields(ManagedProvider)`.

- [ ] **Step 1: Add the capture helper and its test**

Append to `client/test/services/vault/credential_capture_test.dart` inside `main()`:

```dart
  test('existingManagedFields reads the provider vault entry', () async {
    final service = await _service();
    final capture = VaultCredentialCapture(vault: service);
    final provider = ManagedProvider(
      id: 'm1',
      name: 'Usage',
      kind: ManagedProviderKind.apiBalance,
      adapterId: 'http_json_mapping',
    );
    final result = await capture.captureManaged(provider, {'apiKey': 'a'});
    final linked = provider.copyWith(vaultEntryId: result.entryId);
    expect(await capture.existingManagedFields(linked), {'apiKey': 'a'});
    expect(
      await capture.existingManagedFields(provider),
      isEmpty,
      reason: 'no link means no vault fields',
    );
  });
```

Add to `client/lib/services/vault/credential_capture.dart`:

```dart
  Future<Map<String, String>> existingManagedFields(
    ManagedProvider provider,
  ) async {
    final entryId = provider.vaultEntryId?.trim() ?? '';
    if (entryId.isEmpty) return const {};
    final entry = await _vault.get(entryId);
    return entry?.fields ?? const {};
  }
```

- [ ] **Step 2: Write the failing writer test**

Create `client/test/services/provider_usage/managed_provider_vault_writer_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/managed_provider.dart';
import 'package:teampilot/repositories/ssh_credential_store.dart';
import 'package:teampilot/repositories/vault_repository.dart';
import 'package:teampilot/services/provider_usage/managed_provider_vault_writer.dart';
import 'package:teampilot/services/vault/credential_capture.dart';
import 'package:teampilot/services/vault/encrypted_vault_backend.dart';
import 'package:teampilot/services/vault/keychain_vault_backend.dart';
import 'package:teampilot/services/vault/vault_crypto.dart';
import 'package:teampilot/services/vault/vault_service.dart';
import 'package:teampilot/services/vault/vault_unlock_gate.dart';

import '../../support/in_memory_filesystem.dart';

class _FakeStore implements SecureKeyValueStore {
  final values = <String, String>{};

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

Future<VaultService> _vault() async {
  final service = VaultService(
    keychainBackend: KeychainVaultBackend(_FakeStore()),
    encryptedBackend: EncryptedVaultBackend(
      repository: VaultRepository(
        rootDir: '/root/vault',
        fs: InMemoryFilesystem(pathContext: p.Context(style: p.Style.posix)),
      ),
      crypto: const VaultCrypto(memoryKiB: 256, iterations: 1, parallelism: 1),
    ),
  );
  await service.initialize();
  return service;
}

void main() {
  final provider = ManagedProvider(
    id: 'm1',
    name: 'Usage',
    kind: ManagedProviderKind.apiBalance,
    adapterId: 'http_json_mapping',
  );

  test('captures secrets, links the provider and persists', () async {
    final vault = await _vault();
    final capture = VaultCredentialCapture(vault: vault);
    ManagedProvider? persisted;

    final saved = await saveManagedProviderWithVault(
      provider: provider,
      current: null,
      secretValues: {'apiKey': 'a'},
      capture: capture,
      unlockGate: VaultUnlockGate(vault: vault, prompt: () async => true),
      persist: (value) async => persisted = value,
    );

    expect(saved.vaultEntryId, isNotNull);
    expect(persisted?.vaultEntryId, saved.vaultEntryId);
    expect(await vault.readField(saved.vaultEntryId!, 'apiKey'), 'a');
  });

  test('merges existing fields on update', () async {
    final vault = await _vault();
    final capture = VaultCredentialCapture(vault: vault);
    final first = await saveManagedProviderWithVault(
      provider: provider,
      current: null,
      secretValues: {'apiKey': 'a'},
      capture: capture,
      unlockGate: VaultUnlockGate(vault: vault, prompt: () async => true),
      persist: (_) async {},
    );
    await saveManagedProviderWithVault(
      provider: first,
      current: first,
      secretValues: {'secretKey': 'b'},
      capture: capture,
      unlockGate: VaultUnlockGate(vault: vault, prompt: () async => true),
      persist: (_) async {},
    );
    final entry = (await vault.get(first.vaultEntryId!))!;
    expect(entry.fields, {'apiKey': 'a', 'secretKey': 'b'});
  });

  test('persist failure rolls the capture back', () async {
    final vault = await _vault();
    final capture = VaultCredentialCapture(vault: vault);

    await expectLater(
      saveManagedProviderWithVault(
        provider: provider,
        current: null,
        secretValues: {'apiKey': 'a'},
        capture: capture,
        unlockGate: VaultUnlockGate(vault: vault, prompt: () async => true),
        persist: (_) async => throw StateError('persist failed'),
      ),
      throwsA(isA<StateError>()),
    );
    expect(await vault.list(), isEmpty);
  });
}
```

- [ ] **Step 3: Run the writer test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/services/provider_usage/managed_provider_vault_writer_test.dart`
Expected: FAIL — package file not found.

- [ ] **Step 4: Implement the writer**

Create `client/lib/services/provider_usage/managed_provider_vault_writer.dart`:

```dart
import '../../models/managed_provider.dart';
import '../vault/credential_capture.dart';
import '../vault/vault_unlock_gate.dart';

/// Captures managed-provider credentials, then persists the provider row.
///
/// Rollback removes/restores the entry when [persist] fails, so a failed save
/// never leaves the vault ahead of the catalog.
Future<ManagedProvider> saveManagedProviderWithVault({
  required ManagedProvider provider,
  required ManagedProvider? current,
  required Map<String, String> secretValues,
  required VaultCredentialCapture capture,
  required VaultUnlockGate unlockGate,
  required Future<void> Function(ManagedProvider) persist,
}) async {
  if (secretValues.isEmpty) {
    await persist(provider);
    return provider;
  }
  if (!await unlockGate.ensureUnlocked()) {
    throw const VaultSaveBlockedException();
  }
  final existing = current == null
      ? const <String, String>{}
      : await capture.existingManagedFields(current);
  final result = await capture.captureManaged(provider, {
    ...existing,
    ...secretValues,
  });
  final saved = provider.copyWith(vaultEntryId: result.entryId);
  try {
    await persist(saved);
  } on Object {
    await capture.rollback(result);
    rethrow;
  }
  return saved;
}
```

- [ ] **Step 5: Use the writer in the managed-provider editor**

In `client/lib/pages/managed_providers/managed_provider_editor_page.dart`:

1. Imports: `../../services/provider_usage/managed_provider_vault_writer.dart`, `../../services/vault/credential_capture.dart`, `../../services/vault/vault_unlock_gate.dart`, `../../services/vault/vault_service.dart`.
2. In `_save`, after `var requiredSecretsToKeep = requiredSecretFields;` and before the `_isLinkedProviderSource` branch, keep the existing logic but replace the `_existingCredentialHasRequiredSecrets` call with a vault-aware choice:

```dart
      final hasExisting = current?.vaultEntryId != null
          ? await _vaultHasRequiredSecrets(
              context.read<VaultService>(),
              current!,
              requiredSecretsToKeep,
            )
          : await _existingCredentialHasRequiredSecrets(
              store: secretStore,
              current: current,
              credentialRef: credentialRef,
              fields: requiredSecretsToKeep,
            );
```

3. Add `vaultEntryId: current?.vaultEntryId` to the `ManagedProvider(...)` constructor.
4. Replace the `credentialTransaction.run<void>(...)` block with:

```dart
    final secretValues = _isLinkedProviderSource
        ? const <String, String>{}
        : credentialValues;
    try {
      if (secretValues.isNotEmpty) {
        final saved = await saveManagedProviderWithVault(
          provider: next,
          current: current,
          secretValues: secretValues,
          capture: context.read<VaultCredentialCapture>(),
          unlockGate: context.read<VaultUnlockGate>(),
          persist: (value) async {
            await cubit.upsert(value);
            if (cubit.state.errorCode != null) {
              throw const _ManagedProviderEditorPersistenceFailed();
            }
          },
        );
        if (saved.vaultEntryId != next.vaultEntryId && mounted) {
          setState(() => _provider = saved);
        }
      } else {
        await cubit.upsert(next);
        if (cubit.state.errorCode != null) {
          throw const _ManagedProviderEditorPersistenceFailed();
        }
      }
    } on VaultSaveBlockedException {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _formError = context.l10n.vaultLockedSaveBlocked;
      });
      return;
    } on _ManagedProviderEditorPersistenceFailed {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _formError = managedProviderErrorMessage(
          context.l10n,
          providerCode: cubit.state.errorCode,
          detail: cubit.state.errorMessage,
        );
      });
      return;
    } on Object {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _formError = context.l10n.managedProvidersCredentialSaveFailed;
      });
      return;
    }
```

5. Add the vault-aware helper near `_existingCredentialHasRequiredSecrets`:

```dart
Future<bool> _vaultHasRequiredSecrets(
  VaultService vault,
  ManagedProvider provider,
  Set<String> fields,
) async {
  if (fields.isEmpty) return true;
  final entryId = provider.vaultEntryId?.trim() ?? '';
  if (entryId.isEmpty) return false;
  try {
    final entry = await vault.get(entryId);
    if (entry == null) return false;
    return fields.every((field) => (entry.fields[field] ?? '').isNotEmpty);
  } on Object {
    return false;
  }
}
```

- [ ] **Step 6: Run managed-provider tests**

Run: `cd client && dart run tool/run_tests.dart test/services/provider_usage test/pages/managed_providers test/cubits/managed_provider_cubit_test.dart test/services/vault/credential_capture_test.dart`
Expected: `All tests passed!`

- [ ] **Step 7: Analyze and commit**

```bash
git add client/lib/services/provider_usage/managed_provider_vault_writer.dart client/lib/services/vault/credential_capture.dart client/lib/pages/managed_providers/managed_provider_editor_page.dart client/test/services/provider_usage/managed_provider_vault_writer_test.dart client/test/services/vault/credential_capture_test.dart
git commit -m "feat(vault): capture managed-provider credentials on save"
```

---

### Task 9: GitHub token goes through the vault

**Files:**
- Modify: `client/lib/services/github/github_credentials_store.dart`
- Modify: `client/lib/app/app_shell.dart`
- Test: `client/test/services/github/github_credentials_store_test.dart`

**Interfaces:**
- Consumes: `VaultService`, `VaultCredentialCapture`, `VaultUnlockGate`, `VaultSaveBlockedException`.
- Produces: `GithubCredentialsStore({required SecureKeyValueStore kv, String? Function()? readEnvToken, VaultService? vault, VaultCredentialCapture? vaultCapture, Future<bool> Function()? ensureVaultUnlocked})`; pointer key `teampilot.github.v1.vault_entry`.

- [ ] **Step 1: Write the failing store test**

Append to `client/test/services/github/github_credentials_store_test.dart` inside `main()`:

```dart
  test('stores OAuth credentials in the vault and reads the pointer', () async {
    final vault = await _githubVault();
    final store = GithubCredentialsStore(
      kv: InMemorySecureKeyValueStore(),
      vault: vault,
      vaultCapture: VaultCredentialCapture(vault: vault),
      ensureVaultUnlocked: () async => true,
    );

    await store.saveOAuth(token: 'ghp_x', login: 'me');
    final snapshot = await store.readStored();
    expect(snapshot?.token, 'ghp_x');
    expect(snapshot?.login, 'me');
    expect(snapshot?.source, GithubCredentialSource.oauth);
    expect(await vault.list(), hasLength(1));

    await store.clearStored();
    expect(await store.readStored(), isNull);
    expect(await vault.list(), isEmpty);
  });

  test('a refused unlock aborts the save', () async {
    final vault = await _githubVault();
    final store = GithubCredentialsStore(
      kv: InMemorySecureKeyValueStore(),
      vault: vault,
      vaultCapture: VaultCredentialCapture(vault: _LockedGithubVault(vault)),
      ensureVaultUnlocked: () async => false,
    );
    await expectLater(
      store.savePat('ghp_y'),
      throwsA(isA<VaultSaveBlockedException>()),
    );
  });
```

Add helpers at file scope:

```dart
Future<VaultService> _githubVault() async {
  final service = VaultService(
    keychainBackend: KeychainVaultBackend(_FakeStore()),
    encryptedBackend: EncryptedVaultBackend(
      repository: VaultRepository(
        rootDir: '/root/vault',
        fs: InMemoryFilesystem(pathContext: p.Context(style: p.Style.posix)),
      ),
      crypto: const VaultCrypto(memoryKiB: 256, iterations: 1, parallelism: 1),
    ),
  );
  await service.initialize();
  return service;
}

class _LockedGithubVault implements VaultService {
  _LockedGithubVault(this._delegate);
  final VaultService _delegate;
  @override
  bool get isUnlocked => false;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
```

Reuse `InMemorySecureKeyValueStore` from this test file; add a local `_FakeStore` only for the encrypted backend keychain (same `values` map shape).

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/services/github/github_credentials_store_test.dart`
Expected: FAIL — `No named parameter with the name 'vault'`.

- [ ] **Step 3: Implement the vault branch**

In `client/lib/services/github/github_credentials_store.dart`:

```dart
import '../../services/vault/credential_capture.dart';
import '../../services/vault/vault_service.dart';
import '../../services/vault/vault_unlock_gate.dart';

class GithubCredentialsStore {
  GithubCredentialsStore({
    required SecureKeyValueStore kv,
    String? Function()? readEnvToken,
    VaultService? vault,
    VaultCredentialCapture? vaultCapture,
    Future<bool> Function()? ensureVaultUnlocked,
  }) : _kv = kv,
       _readEnvToken = readEnvToken ?? readGithubTokenFromEnvironment,
       _vault = vault,
       _vaultCapture = vaultCapture,
       _ensureVaultUnlocked = ensureVaultUnlocked;

  static const _vaultEntryKey = 'teampilot.github.v1.vault_entry';
  final VaultService? _vault;
  final VaultCredentialCapture? _vaultCapture;
  final Future<bool> Function()? _ensureVaultUnlocked;
```

Save methods:

```dart
  Future<void> saveOAuth({required String token, required String login}) async {
    if (await _captureVault(
      token: token,
      login: login,
      source: GithubCredentialSource.oauth.name,
    )) {
      return;
    }
    await _kv.write(_tokenKey, token);
    await _kv.write(_loginKey, login);
    await _kv.write(_sourceKey, GithubCredentialSource.oauth.name);
  }

  Future<void> savePat(String token, {String? login}) async {
    if (await _captureVault(
      token: token,
      login: login ?? '',
      source: GithubCredentialSource.pat.name,
    )) {
      return;
    }
    await _kv.write(_tokenKey, token);
    await _kv.write(_sourceKey, GithubCredentialSource.pat.name);
    if (login != null) {
      await _kv.write(_loginKey, login);
    } else {
      await _kv.delete(_loginKey);
    }
  }

  Future<bool> _captureVault({
    required String token,
    required String login,
    required String source,
  }) async {
    final capture = _vaultCapture;
    if (capture == null) return false;
    final unlock = _ensureVaultUnlocked;
    if (unlock != null && !await unlock()) {
      throw const VaultSaveBlockedException();
    }
    final result = await capture.captureGithub(
      token: token,
      login: login,
      source: source,
    );
    await _kv.write(_vaultEntryKey, result.entryId);
    await _clearLegacy();
    return true;
  }
```

`readStored`:

```dart
  Future<GithubCredentialsSnapshot?> readStored() async {
    await migrateLegacyHubPublishTokenIfNeeded();

    final pointer = (await _kv.read(_vaultEntryKey))?.trim() ?? '';
    if (pointer.isNotEmpty) {
      final entry = await _vault?.get(pointer);
      if (entry != null) {
        final token = entry.fields['token'] ?? '';
        if (token.isEmpty) return null;
        final sourceRaw = entry.fields['source'];
        return GithubCredentialsSnapshot(
          token: token,
          login: (entry.fields['login'] ?? '').isEmpty
              ? null
              : entry.fields['login'],
          source: _parseSource(sourceRaw),
        );
      }
    }

    final token = await _kv.read(_tokenKey);
    if (token == null || token.isEmpty) return null;
    await _migrateLegacyTokenToVault(token);
    return _legacySnapshot();
  }
```

Where `_migrateLegacyTokenToVault` is best-effort:

```dart
  Future<void> _migrateLegacyTokenToVault(String token) async {
    final capture = _vaultCapture;
    if (capture == null) return;
    try {
      final login = await _kv.read(_loginKey) ?? '';
      final source = await _kv.read(_sourceKey) ?? '';
      final result = await capture.captureGithub(
        token: token,
        login: login,
        source: source,
      );
      await _kv.write(_vaultEntryKey, result.entryId);
    } on Object {
      // Legacy read still succeeds; the importer retries later.
    }
  }
```

`clearStored`:

```dart
  Future<void> clearStored() async {
    final pointer = (await _kv.read(_vaultEntryKey))?.trim() ?? '';
    if (pointer.isNotEmpty && _vault != null) {
      final unlock = _ensureVaultUnlocked;
      if (unlock != null && !await unlock()) {
        throw const VaultSaveBlockedException();
      }
      await _vault.delete(pointer);
    }
    await _kv.delete(_vaultEntryKey);
    await _clearLegacy();
  }

  Future<void> _clearLegacy() async {
    await _kv.delete(_tokenKey);
    await _kv.delete(_loginKey);
    await _kv.delete(_sourceKey);
  }
```

Keep `resolveToken`, `migrateLegacyHubPublishTokenIfNeeded` and `_parseSource` as-is; the legacy snapshot path is the current body of `readStored`, moved into `_legacySnapshot()`.

- [ ] **Step 4: Wire the store in `app_shell.dart`**

Replace the construction with:

```dart
  final githubCredentialsStore = GithubCredentialsStore(
    kv: const FlutterSecureKeyValueStore(),
    vault: vaultService,
    vaultCapture: vaultCredentialCapture,
    ensureVaultUnlocked: vaultUnlockGate.ensureUnlocked,
  );
```

(These objects are created in Task 12; in this task use the local `vaultService` and construct a temporary `VaultCredentialCapture(vault: vaultService)` / `VaultUnlockGate(vault: vaultService, prompt: promptVaultUnlockFromRouter)`. Task 12 replaces the temporaries with the shared instances.)

Add imports for `credential_capture.dart`, `vault_unlock_gate.dart`, and `../../pages/vault/vault_status_section.dart` (for the router prompt) only if not already present.

- [ ] **Step 5: Run GitHub tests**

Run: `cd client && dart run tool/run_tests.dart test/services/github test/pages/hub_publish 2>/dev/null || cd client && dart run tool/run_tests.dart test/services/github`
Expected: `All tests passed!`

- [ ] **Step 6: Analyze and commit**

```bash
git add client/lib/services/github/github_credentials_store.dart client/lib/app/app_shell.dart client/test/services/github/github_credentials_store_test.dart
git commit -m "feat(vault): store the GitHub token in the vault"
```

---
### Task 10: Paired-relay grants read the vault first

**Files:**
- Modify: `client/lib/services/connect/paired_relay_tunnel_registry.dart`
- Modify: `client/lib/app/app_shell.dart`
- Test: `client/test/services/connect/paired_relay_tunnel_registry_test.dart`

**Interfaces:**
- Consumes: `VaultService.readField`.
- Produces: `PairedRelayTunnelRegistry({..., VaultService? vault})` and `Future<String?> relayGrantFor(SshProfile profile)`.

- [ ] **Step 1: Write the failing test**

Create `client/test/services/connect/paired_relay_tunnel_registry_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/repositories/ssh_credential_store.dart';
import 'package:teampilot/repositories/vault_repository.dart';
import 'package:teampilot/services/connect/paired_relay_tunnel_registry.dart';
import 'package:teampilot/services/vault/encrypted_vault_backend.dart';
import 'package:teampilot/services/vault/keychain_vault_backend.dart';
import 'package:teampilot/services/vault/vault_crypto.dart';
import 'package:teampilot/services/vault/vault_service.dart';

import '../../support/in_memory_filesystem.dart';

class _FakeStore implements SecureKeyValueStore {
  final values = <String, String>{};

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

void main() {
  test('reads the relay grant from the linked vault entry first', () async {
    final vault = VaultService(
      keychainBackend: KeychainVaultBackend(_FakeStore()),
      encryptedBackend: EncryptedVaultBackend(
        repository: VaultRepository(
          rootDir: '/root/vault',
          fs: InMemoryFilesystem(pathContext: p.Context(style: p.Style.posix)),
        ),
        crypto: const VaultCrypto(memoryKiB: 256, iterations: 1, parallelism: 1),
      ),
    );
    await vault.initialize();
    await vault.upsert(
      const VaultEntry(
        id: 'v1',
        type: VaultEntryType.sshPassword,
        title: 'Paired',
        fields: {'relayGrant': 'vault-grant'},
      ),
    );
    final credentials = InMemorySshCredentialStore();
    await credentials.saveRelayGrant('p1', 'legacy-grant');
    const profile = SshProfile(
      id: 'p1',
      name: 'Paired',
      host: '127.0.0.1',
      username: 'u',
      vaultEntryId: 'v1',
    );
    final registry = PairedRelayTunnelRegistry(
      credentialStore: credentials,
      vault: vault,
    );

    expect(await registry.relayGrantFor(profile), 'vault-grant');

    const legacy = SshProfile(
      id: 'p2',
      name: 'Legacy',
      host: '127.0.0.1',
      username: 'u',
    );
    expect(await registry.relayGrantFor(legacy), isNull);
  });
}
```

Add `VaultEntry` import.

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/services/connect/paired_relay_tunnel_registry_test.dart`
Expected: FAIL — `No named parameter with the name 'vault'`.

- [ ] **Step 3: Implement vault-first grant resolution**

In `client/lib/services/connect/paired_relay_tunnel_registry.dart`:

1. Import `../vault/vault_service.dart`.
2. Constructor `this.vault` and field `final VaultService? vault;`.
3. Add:

```dart
  /// Vault entry first (vault-first credentials), then the keychain.
  Future<String?> relayGrantFor(SshProfile profile) async {
    final entryId = profile.vaultEntryId?.trim() ?? '';
    if (vault != null && entryId.isNotEmpty) {
      try {
        final grant = await vault!.readField(entryId, 'relayGrant');
        if (grant != null && grant.isNotEmpty) return grant;
      } on Object {
        // Fall through to the keychain.
      }
    }
    return credentialStore.loadRelayGrant(profile.id);
  }
```

4. In `ensureSshTunnel`, replace `final grant = await credentialStore.loadRelayGrant(profile.id);` with `final grant = await relayGrantFor(profile);`.

5. In `app_shell.dart`, pass `vault: vaultService` to the registry.

- [ ] **Step 4: Run the test**

Run: `cd client && dart run tool/run_tests.dart test/services/connect`
Expected: `All tests passed!`

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/connect/paired_relay_tunnel_registry.dart client/lib/app/app_shell.dart client/test/services/connect/paired_relay_tunnel_registry_test.dart
git commit -m "feat(vault): resolve paired-relay grants from the vault"
```

---

### Task 11: One-shot legacy importer

**Files:**
- Create: `client/lib/services/vault/legacy_import.dart`
- Modify: `client/lib/services/github/github_credentials_store.dart` (add `storedVaultEntryId`)
- Test: `client/test/services/vault/legacy_import_test.dart`

**Interfaces:**
- Consumes: `VaultService`, `VaultCredentialCapture`, repositories/stores listed below.
- Produces: `class VaultLegacyImportService` with `Future<void> runOnce()`; constructor `VaultLegacyImportService({required VaultService vault, required VaultCredentialCapture capture, required SshProfileRepository sshProfiles, required SshCredentialStore sshCredentials, required AppProviderRepository appProviders, required ManagedProviderRepository managedProviders, required ManagedProviderSecretStore managedSecrets, required GithubCredentialsStore github})`.

- [ ] **Step 1: Add the GitHub pointer getter**

In `client/lib/services/github/github_credentials_store.dart`:

```dart
  Future<String?> storedVaultEntryId() async {
    final pointer = (await _kv.read(_vaultEntryKey))?.trim() ?? '';
    return pointer.isEmpty ? null : pointer;
  }
```

- [ ] **Step 2: Write the failing importer test**

Create `client/test/services/vault/legacy_import_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/app_provider_config.dart';
import 'package:teampilot/models/managed_provider.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/repositories/app_provider_repository.dart';
import 'package:teampilot/repositories/managed_provider_repository.dart';
import 'package:teampilot/repositories/ssh_credential_store.dart';
import 'package:teampilot/repositories/ssh_profile_repository.dart';
import 'package:teampilot/repositories/vault_repository.dart';
import 'package:teampilot/services/github/github_credentials_store.dart';
import 'package:teampilot/services/provider_usage/managed_provider_secret_store.dart';
import 'package:teampilot/services/vault/credential_capture.dart';
import 'package:teampilot/services/vault/encrypted_vault_backend.dart';
import 'package:teampilot/services/vault/keychain_vault_backend.dart';
import 'package:teampilot/services/vault/legacy_import.dart';
import 'package:teampilot/services/vault/vault_crypto.dart';
import 'package:teampilot/services/vault/vault_service.dart';

import '../../support/in_memory_filesystem.dart';

class _FakeStore implements SecureKeyValueStore {
  final values = <String, String>{};

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

class _Harness {
  _Harness(this.fs, this.storage, this.vault, this.capture);

  final InMemoryFilesystem fs;
  final dynamic storage;
  final VaultService vault;
  final VaultCredentialCapture capture;
}

Future<_Harness> _harness() async {
  final fs = InMemoryFilesystem();
  final storage = fakeHomeStorage(filesystem: fs);
  final vault = VaultService(
    keychainBackend: KeychainVaultBackend(_FakeStore()),
    encryptedBackend: EncryptedVaultBackend(
      repository: VaultRepository(
        rootDir: '/root/vault',
        fs: InMemoryFilesystem(pathContext: p.Context(style: p.Style.posix)),
      ),
      crypto: const VaultCrypto(memoryKiB: 256, iterations: 1, parallelism: 1),
    ),
  );
  await vault.initialize();
  return _Harness(fs, storage, vault, VaultCredentialCapture(vault: vault));
}

void main() {
  test('imports every legacy secret once', () async {
    final h = await _harness();
    final sshProfiles = SshProfileRepository(storage: h.storage);
    final sshCredentials = InMemorySshCredentialStore();
    await sshProfiles.save(
      const SshProfile(id: 'p1', name: 'Server', host: 'h', username: 'u'),
    );
    await sshCredentials.savePassword('p1', 'pw');

    final appProviders = AppProviderRepository(storage: h.storage, fs: h.fs);
    await appProviders.saveProviders(CliTool.claude, const [
      AppProviderConfig(id: 'openai', cli: CliTool.claude, name: 'OpenAI', apiKey: 'sk'),
    ]);

    final managedRepo = ManagedProviderRepository(
      storage: h.storage,
      fs: h.fs,
      configPath: '/tp/managed.json',
      onProvidersDeleted: (_) async {},
    );
    final managedSecrets = ManagedProviderSecretStore(_FakeStore());
    await managedRepo.save([
      ManagedProvider(
        id: 'm1',
        name: 'Usage',
        kind: ManagedProviderKind.apiBalance,
        adapterId: 'http_json_mapping',
        credentialRef: 'managed-provider:m1',
      ),
    ]);
    await managedSecrets.write('managed-provider:m1', {'apiKey': 'usage-key'});

    final githubKv = InMemorySecureKeyValueStore();
    await githubKv.write('teampilot.github.v1.token', 'ghp');
    await githubKv.write('teampilot.github.v1.login', 'me');
    await githubKv.write('teampilot.github.v1.source', 'oauth');
    final github = GithubCredentialsStore(
      kv: githubKv,
      vault: h.vault,
      vaultCapture: h.capture,
      ensureVaultUnlocked: () async => true,
    );

    final importer = VaultLegacyImportService(
      vault: h.vault,
      capture: h.capture,
      sshProfiles: sshProfiles,
      sshCredentials: sshCredentials,
      appProviders: appProviders,
      managedProviders: managedRepo,
      managedSecrets: managedSecrets,
      github: github,
    );
    await importer.runOnce();

    expect((await sshProfiles.loadAll()).single.vaultEntryId, isNotNull);
    expect(await sshCredentials.loadPassword('p1'), isNull);
    final provider = (await appProviders.loadProviders(CliTool.claude)).single;
    expect(provider.credentialLink, startsWith('vault:'));
    expect(provider.apiKey, isEmpty);
    final managed = (await managedRepo.load()).single;
    expect(managed.vaultEntryId, isNotNull);
    expect(await managedSecrets.read('managed-provider:m1'), isNotNull);
    expect(
      (await h.vault.list()).any(
        (entry) => entry.extra['ownerKind'] == vaultOwnerKindGithub,
      ),
      isTrue,
    );
    expect(h.vault.legacyImportVersion, 1);

    final before = (await h.vault.list()).length;
    await importer.runOnce();
    expect((await h.vault.list()).length, before, reason: 'idempotent');
  });

  test('a failed owner keeps its legacy data and blocks the marker', () async {
    final h = await _harness();
    final sshProfiles = SshProfileRepository(storage: h.storage);
    final sshCredentials = InMemorySshCredentialStore();
    await sshProfiles.save(
      const SshProfile(id: 'bad', name: 'Bad', host: 'h', username: 'u'),
    );
    await sshCredentials.savePassword('bad', 'pw');
    final importer = VaultLegacyImportService(
      vault: h.vault,
      capture: _FailingSshCapture(h.vault),
      sshProfiles: sshProfiles,
      sshCredentials: sshCredentials,
      appProviders: AppProviderRepository(storage: h.storage, fs: h.fs),
      managedProviders: ManagedProviderRepository(
        storage: h.storage,
        fs: h.fs,
        configPath: '/tp/managed.json',
        onProvidersDeleted: (_) async {},
      ),
      managedSecrets: ManagedProviderSecretStore(_FakeStore()),
      github: GithubCredentialsStore(kv: _FakeStore()),
    );

    await importer.runOnce();
    expect((await sshProfiles.loadAll()).single.vaultEntryId, isNull);
    expect(await sshCredentials.loadPassword('bad'), 'pw');
    expect(h.vault.legacyImportVersion, 0);
  });

  test('locked vault is a no-op', () async {
    final h = await _harness();
    final sshProfiles = SshProfileRepository(storage: h.storage);
    final sshCredentials = InMemorySshCredentialStore();
    await sshProfiles.save(
      const SshProfile(id: 'p1', name: 'Server', host: 'h', username: 'u'),
    );
    await sshCredentials.savePassword('p1', 'pw');
    final importer = VaultLegacyImportService(
      vault: _LockedVault(h.vault),
      capture: VaultCredentialCapture(vault: h.vault),
      sshProfiles: sshProfiles,
      sshCredentials: sshCredentials,
      appProviders: AppProviderRepository(storage: h.storage, fs: h.fs),
      managedProviders: ManagedProviderRepository(
        storage: h.storage,
        fs: h.fs,
        configPath: '/tp/managed.json',
        onProvidersDeleted: (_) async {},
      ),
      managedSecrets: ManagedProviderSecretStore(_FakeStore()),
      github: GithubCredentialsStore(kv: _FakeStore()),
    );

    await importer.runOnce();
    expect(await sshCredentials.loadPassword('p1'), 'pw');
    expect((await h.vault.list()), isEmpty);
  });
}

class _FailingSshCapture extends VaultCredentialCapture {
  _FailingSshCapture(VaultService vault) : super(vault: vault);

  @override
  Future<VaultCaptureResult> captureSsh(
    SshProfile profile, {
    String? password,
    String? privateKey,
    String? passphrase,
    String? relayGrant,
  }) async {
    if (profile.id == 'bad') {
      throw const VaultCaptureException('injected');
    }
    return super.captureSsh(
      profile,
      password: password,
      privateKey: privateKey,
      passphrase: passphrase,
      relayGrant: relayGrant,
    );
  }
}

class _LockedVault implements VaultService {
  _LockedVault(this._delegate);
  final VaultService _delegate;
  @override
  bool get isUnlocked => false;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/services/vault/legacy_import_test.dart`
Expected: FAIL — package file not found.

- [ ] **Step 4: Implement the importer**

Create `client/lib/services/vault/legacy_import.dart`:

```dart
import '../../models/app_provider_config.dart';
import '../../models/managed_provider.dart';
import '../../models/team_config.dart';
import '../../repositories/app_provider_repository.dart';
import '../../repositories/managed_provider_repository.dart';
import '../../repositories/ssh_credential_store.dart';
import '../../repositories/ssh_profile_repository.dart';
import '../../services/github/github_credentials_store.dart';
import '../../services/provider_usage/managed_provider_secret_store.dart';
import '../../utils/logging/logger.dart';
import 'credential_capture.dart';
import 'vault_service.dart';

/// Imports every legacy secret into the vault exactly once.
///
/// Order: GitHub → SSH → app providers → managed providers. Each owner is
/// isolated; failures keep the legacy value and the marker at 0 so the next
/// run retries only unfinished owners.
class VaultLegacyImportService {
  VaultLegacyImportService({
    required VaultService vault,
    required VaultCredentialCapture capture,
    required SshProfileRepository sshProfiles,
    required SshCredentialStore sshCredentials,
    required AppProviderRepository appProviders,
    required ManagedProviderRepository managedProviders,
    required ManagedProviderSecretStore managedSecrets,
    required GithubCredentialsStore github,
  }) : _vault = vault,
       _capture = capture,
       _sshProfiles = sshProfiles,
       _sshCredentials = sshCredentials,
       _appProviders = appProviders,
       _managedProviders = managedProviders,
       _managedSecrets = managedSecrets,
       _github = github;

  static const _version = 1;

  final VaultService _vault;
  final VaultCredentialCapture _capture;
  final SshProfileRepository _sshProfiles;
  final SshCredentialStore _sshCredentials;
  final AppProviderRepository _appProviders;
  final ManagedProviderRepository _managedProviders;
  final ManagedProviderSecretStore _managedSecrets;
  final GithubCredentialsStore _github;

  Future<void>? _running;

  Future<void> runOnce() {
    final active = _running;
    if (active != null) return active;
    final next = _run();
    _running = next.whenComplete(() => _running = null);
    return _running!;
  }

  Future<void> _run() async {
    if (!_vault.isUnlocked) return;
    if (_vault.legacyImportVersion >= _version) return;

    var failed = false;
    failed = !await _guard('github', _importGithub) || failed;
    failed = !await _guard('ssh', _importSsh) || failed;
    for (final cli in CliTool.values) {
      failed = !await _guard('appProvider:${cli.value}', () => _importProviders(cli)) || failed;
    }
    failed = !await _guard('managedProvider', _importManaged) || failed;

    if (!failed) {
      await _vault.markLegacyImported(_version);
    }
  }

  Future<bool> _guard(String label, Future<void> Function() body) async {
    try {
      await body();
      return true;
    } on Object catch (error, stackTrace) {
      AppLogger.instance.w(
        '[vault-import] $label failed: ${error.runtimeType}',
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  Future<void> _importGithub() async {
    if (await _github.storedVaultEntryId() != null) return;
    final snapshot = await _github.readStored();
    if (snapshot == null || snapshot.token.isEmpty) return;
    if (snapshot.source == GithubCredentialSource.pat) {
      await _github.savePat(snapshot.token, login: snapshot.login);
    } else {
      await _github.saveOAuth(
        token: snapshot.token,
        login: snapshot.login ?? '',
      );
    }
  }

  Future<void> _importSsh() async {
    for (final profile in await _sshProfiles.loadAll()) {
      try {
        if ((profile.vaultEntryId ?? '').isNotEmpty) continue;
        final password = profile.authType == SshAuthType.password
            ? await _sshCredentials.loadPassword(profile.id)
            : null;
        final privateKey = profile.authType == SshAuthType.password
            ? null
            : await _sshCredentials.loadPrivateKey(profile.id);
        final passphrase = profile.authType == SshAuthType.password
            ? null
            : await _sshCredentials.loadPrivateKeyPassphrase(profile.id);
        final relayGrant = await _sshCredentials.loadRelayGrant(profile.id);
        final hasSecret = (password ?? '').isNotEmpty ||
            (privateKey ?? '').isNotEmpty ||
            (passphrase ?? '').isNotEmpty ||
            (relayGrant ?? '').isNotEmpty;
        if (!hasSecret) continue;

        final result = await _capture.captureSsh(
          profile,
          password: password,
          privateKey: privateKey,
          passphrase: passphrase,
          relayGrant: relayGrant,
        );
        try {
          await _sshProfiles.save(profile.copyWith(vaultEntryId: result.entryId));
        } on Object {
          await _capture.rollback(result);
          rethrow;
        }
        await _sshCredentials.deleteAll(profile.id);
      } on Object catch (error, stackTrace) {
        AppLogger.instance.w(
          '[vault-import] ssh ${profile.id} failed: ${error.runtimeType}',
          stackTrace: stackTrace,
        );
      }
    }
  }

  Future<void> _importProviders(CliTool cli) async {
    final providers = await _appProviders.loadProviders(
      cli,
      reconcileCredentials: false,
    );
    for (var index = 0; index < providers.length; index++) {
      final provider = providers[index];
      try {
        final link = provider.credentialLink.trim();
        if (link.isNotEmpty) continue;
        if (provider.apiKey.isEmpty) continue;
        final result = await _capture.captureProvider(
          provider,
          apiKey: provider.apiKey,
        );
        providers[index] = provider.copyWith(
          credentialLink: 'vault:${result.entryId}',
          apiKey: '',
        );
      } on Object catch (error, stackTrace) {
        AppLogger.instance.w(
          '[vault-import] provider ${provider.id} failed: ${error.runtimeType}',
          stackTrace: stackTrace,
        );
      }
    }
    await _appProviders.saveProviders(cli, providers);
  }

  Future<void> _importManaged() async {
    final providers = await _managedProviders.load();
    final updated = <ManagedProvider>[];
    final legacyRefs = <String>[];
    for (final provider in providers) {
      try {
        if ((provider.vaultEntryId ?? '').isNotEmpty) {
          updated.add(provider);
          continue;
        }
        final ref = provider.credentialRef?.trim() ?? '';
        if (ref.isEmpty) {
          updated.add(provider);
          continue;
        }
        final scope = await _managedSecrets.read(ref);
        if (scope.isEmpty) {
          updated.add(provider);
          continue;
        }
        final values = {
          for (final field in scope.fields)
            if ((scope.valueFor(field) ?? '').isNotEmpty)
              field: scope.valueFor(field)!,
        };
        final result = await _capture.captureManaged(provider, values);
        updated.add(provider.copyWith(vaultEntryId: result.entryId));
        legacyRefs.add(ref);
      } on Object catch (error, stackTrace) {
        AppLogger.instance.w(
          '[vault-import] managed ${provider.id} failed: ${error.runtimeType}',
          stackTrace: stackTrace,
        );
        updated.add(provider);
      }
    }
    await _managedProviders.save(updated);
    for (final ref in legacyRefs) {
      await _managedSecrets.delete(ref);
    }
  }
}
```

Notes:
- `_importGithub` uses `saveOAuth` even for PAT snapshots; the GitHub source is cosmetic. To preserve the source, call `_github.savePat(snapshot.token, login: snapshot.login)` when `snapshot.source == GithubCredentialSource.pat`. Implement both branches.
- Provider save writes the whole list even when nothing changed; acceptable and keeps the file canonical.
- `_importManaged` saves the catalog before deleting legacy refs; a save failure throws before deletion. Captured entries may be orphaned on a save failure; they are reused by `ownerId` on the next run, so no duplicates.

- [ ] **Step 5: Run the importer tests**

Run: `cd client && dart run tool/run_tests.dart test/services/vault/legacy_import_test.dart`
Expected: `All tests passed!`

- [ ] **Step 6: Analyze and commit**

```bash
git add client/lib/services/vault/legacy_import.dart client/lib/services/github/github_credentials_store.dart client/test/services/vault/legacy_import_test.dart
git commit -m "feat(vault): import all legacy credentials once"
```

---

### Task 12: App wiring and unlock hook

**Files:**
- Modify: `client/lib/cubits/vault_cubit.dart`
- Modify: `client/lib/app/app_shell.dart`
- Modify: `client/lib/main.dart`
- Test: `client/test/cubits/vault_cubit_test.dart`

**Interfaces:**
- Consumes: all previous tasks.
- Produces: `VaultCubit({..., Future<void> Function()? onUnlocked})`; providers for `VaultCredentialCapture` and `VaultUnlockGate` in the widget tree.

- [ ] **Step 1: Write the failing cubit test**

Append to `client/test/cubits/vault_cubit_test.dart` inside `main()` (adapt to the file's existing service helper):

```dart
  test('onUnlocked fires after a successful unlock', () async {
    final service = _service(); // existing helper in this file
    await service.enableEncryptedBackend('pass');
    await service.lock();
    var calls = 0;
    final cubit = VaultCubit(
      service: service,
      sshProfiles: SshProfileRepository(storage: fakeHomeStorage()),
      appProviders: AppProviderRepository(storage: fakeHomeStorage()),
      onUnlocked: () async => calls++,
    );
    addTearDown(cubit.close);
    await cubit.unlock('pass');
    expect(calls, 1);
  });
```

If the file has no `_service()` helper, build the service exactly as in `client/test/services/vault/vault_service_test.dart` (`buildService()`), and add the imports.

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/cubits/vault_cubit_test.dart`
Expected: FAIL — `No named parameter with the name 'onUnlocked'`.

- [ ] **Step 3: Add the hook to the cubit**

In `client/lib/cubits/vault_cubit.dart`:

```dart
  VaultCubit({
    required VaultService service,
    required SshProfileRepository sshProfiles,
    required AppProviderRepository appProviders,
    Future<void> Function()? onUnlocked,
  }) : _service = service,
       _sshProfiles = sshProfiles,
       _appProviders = appProviders,
       _onUnlocked = onUnlocked,
       super(const VaultState());

  final Future<void> Function()? _onUnlocked;
```

After the successful `emit(...)` in `unlock`, and after the successful `emit(...)` in `enableEncryption`:

```dart
      await _onUnlocked?.call();
```

Place it after the emit so the vault state is already unlocked.

- [ ] **Step 4: Wire `app_shell.dart`**

1. Construct shared objects right after `vaultService.initialize()`:

```dart
  final vaultCredentialCapture = VaultCredentialCapture(vault: vaultService);
  final vaultUnlockGate = VaultUnlockGate(
    vault: vaultService,
    prompt: promptVaultUnlockFromRouter,
  );
```

2. Pass `vault: vaultService` to `PairedRelayTunnelRegistry` (Task 10).
3. Use `vaultCredentialCapture` and `vaultUnlockGate.ensureUnlocked` in the GitHub store (replace Task 9 temporaries).
4. `VaultCubit` construction:

```dart
  late final VaultLegacyImportService legacyImporter;
  vaultCubit = VaultCubit(
    service: vaultService,
    sshProfiles: sshProfileRepo,
    appProviders: AppProviderRepository(storage: homeStorage),
    onUnlocked: () => legacyImporter.runOnce(),
  );
```

5. After the managed-provider graph is constructed (after `resolvedManagedProviderSecretStore` / `resolvedManagedProviderRepository` / `githubCredentialsStore`):

```dart
  legacyImporter = VaultLegacyImportService(
    vault: vaultService,
    capture: vaultCredentialCapture,
    sshProfiles: sshProfileRepo,
    sshCredentials: sshCredentialStore,
    appProviders: AppProviderRepository(storage: homeStorage),
    managedProviders: resolvedManagedProviderRepository,
    managedSecrets: resolvedManagedProviderSecretStore,
    github: githubCredentialsStore,
  );
  unawaited(legacyImporter.runOnce());
```

Add `dart:async` if `unawaited` is not already imported, and imports for `credential_capture.dart`, `vault_unlock_gate.dart`, `legacy_import.dart`, `../../pages/vault/vault_status_section.dart`.

6. `AppProviderCubit`:

```dart
    vaultCapture: vaultCredentialCapture,
    ensureVaultUnlocked: vaultUnlockGate.ensureUnlocked,
```

7. `AppShell` class/constructor: add `required this.vaultCredentialCapture` and `required this.vaultUnlockGate`, fields, and pass them at the `AppShell(...)` construction site.

- [ ] **Step 5: Register providers in `main.dart`**

Inside `MultiRepositoryProvider.providers` next to `VaultService`:

```dart
                  RepositoryProvider<VaultCredentialCapture>.value(
                    value: shell.vaultCredentialCapture,
                  ),
                  RepositoryProvider<VaultUnlockGate>.value(
                    value: shell.vaultUnlockGate,
                  ),
```

Add imports for both service files.

- [ ] **Step 6: Run the cubit test and a smoke subset**

Run: `cd client && dart run tool/run_tests.dart test/cubits/vault_cubit_test.dart test/pages/vault test/pages/ssh_profiles test/cubits/app_provider_cubit_test.dart`
Expected: `All tests passed!`

- [ ] **Step 7: Analyze and commit**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: 0 errors.

```bash
git add client/lib/cubits/vault_cubit.dart client/lib/app/app_shell.dart client/lib/main.dart client/test/cubits/vault_cubit_test.dart
git commit -m "feat(vault): wire vault-first capture, gate and importer"
```

---

### Task 13: Docs and full verification

**Files:**
- Modify: `docs/workspace-storage-layout.md`
- Modify: `docs/ARCHITECTURE.md`
- Modify: `docs/superpowers/specs/2026-11-02-vault-first-credentials-design.md`

- [ ] **Step 1: Mark the spec implemented**

In `docs/superpowers/specs/2026-11-02-vault-first-credentials-design.md`, change:

```markdown
Status: Approved for implementation planning
```

to:

```markdown
Status: Implemented
```

- [ ] **Step 2: Update the storage doc**

In `docs/workspace-storage-layout.md`, after the existing vault paragraph, add:

```markdown
Credentials are **vault-first**: SSH passwords/keys/relay grants, provider API keys,
managed-provider (balance/usage) credentials and the GitHub token are captured into the
vault on save. Legacy keychain entries and `providers.json` `apiKey` values are imported
once in the background (marker: `VaultDocument.legacyImportVersion`) and then deleted.
```

- [ ] **Step 3: Update the architecture doc**

Update the vault row in `docs/ARCHITECTURE.md`:

```markdown
| Credential vault (SSH/provider/usage/GitHub secrets) | `services/vault/` — `VaultCredentialCapture` (find-or-create + verify + rollback), `VaultLegacyImportService` (one-shot migration), `VaultUnlockGate`; owners keep explicit references and read secrets only through the vault |
```

- [ ] **Step 4: Run the full verification**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: `34 issues found.` and 0 errors.

Run (background, once): `cd client && dart run tool/run_tests.dart`
Expected: `All tests passed!` (ignore the known environment flakes only after re-running the failing file standalone: Flutter tool temp-dir races and missing gitignored `google_fonts` assets — run `dart run tool/sync_bundled_google_fonts.dart` if the Noto test fails).

- [ ] **Step 5: Commit**

```bash
git add docs/workspace-storage-layout.md docs/ARCHITECTURE.md docs/superpowers/specs/2026-11-02-vault-first-credentials-design.md
git commit -m "docs(vault): document vault-first credential storage"
```

---

## Self-Review

**Spec coverage**

| Spec section | Task |
|---|---|
| 5.1 `VaultCredentialCapture` | 2 |
| 5.1 `VaultLegacyImportService` | 11 |
| 5.1 `VaultUnlockGate` | 3 |
| 5.2 entry conventions / `extra` owner keys | 2 |
| 5.3 SSH reference + relay grant | 4, 10 |
| 5.3 provider link | 6 |
| 5.3 managed `vaultEntryId` | 7, 8 |
| 5.3 GitHub pointer | 9 |
| 5.4 import marker | 1 |
| 6.1 SSH capture + UI removal | 4, 5 |
| 6.2 provider capture + delete cleanup | 6 |
| 6.3 managed capture + transaction | 8 |
| 6.4 GitHub capture | 9 |
| 7.1 trigger (boot + unlock) | 12 |
| 7.2 per-owner ordering / failure isolation | 11 |
| 7.3 marker only on zero failures | 11 |
| 8 read paths | 4, 7, 9, 10 |
| 9 UI changes | 5, 6 |
| 10 error handling | 3, 4, 5, 8, 9 |
| 11 testing matrix | every task + 13 |
| 12 risks | reflected in rollback/verify steps |
| 13 rollout | 1 (additive marker), 7 (optional field) |

**Placeholder scan:** no TBD/TODO; every code step carries complete code. The only conditional instruction is the `hub_publish` test path fallback in Task 9 redirection, which is intentional.

**Type consistency:** `VaultCaptureResult`, `VaultCaptureException`, `VaultSaveBlockedException`, `relayGrantFor`, `storedVaultEntryId`, `existingManagedFields`, `saveSshProfileWithVault`, `saveManagedProviderWithVault`, and all owner-kind constants are defined once and referenced consistently.

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-11-02-vault-first-credentials.md`.

Two execution options:

1. **Subagent-Driven (recommended)** — a fresh subagent per task with review between tasks.
2. **Inline Execution** — execute tasks in this session with checkpoints.

Note: OpenCode Go subagent models were unavailable during the previous plan (insufficient funds / free limit); if they are still unavailable, inline execution in this session is the fallback.
