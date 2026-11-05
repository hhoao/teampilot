// client/lib/services/vault/vault_document_store.dart
import 'dart:async';

import '../../models/vault_document.dart';
import '../../models/vault_entry.dart';
import '../../repositories/ssh_credential_store.dart';
import '../../utils/logging/logger.dart';
import 'encrypted_vault_backend.dart';
import 'keychain_vault_backend.dart';
import 'vault_errors.dart';

class VaultDocumentStore {
  VaultDocumentStore({
    required KeychainVaultBackend keychainBackend,
    required EncryptedVaultBackend encryptedBackend,
    SecureKeyValueStore? masterKeyStore,
  }) : _keychainBackend = keychainBackend,
       _encryptedBackend = encryptedBackend,
       _masterKeyStore = masterKeyStore;

  static const _masterKey = 'teampilot.vault.v1.master';

  final KeychainVaultBackend _keychainBackend;
  final EncryptedVaultBackend _encryptedBackend;
  final SecureKeyValueStore? _masterKeyStore;

  VaultDocument? _document;
  Map<String, VaultEntry> _index = const {};
  bool _encrypted = false;
  bool _locked = false;
  bool _initialized = false;
  String? _masterPassphrase;
  Future<void>? _writeTail;

  bool get isEncrypted => _encrypted;

  bool get isLocked => _locked;

  bool get isUnlocked => !_locked;

  /// `0` until the one-shot legacy import has completed.
  int get legacyImportVersion => _requireDocument().legacyImportVersion;

  /// Re-reads the keychain document so a marker written by another
  /// `VaultService` over the same store is visible.
  ///
  /// A retried bootstrap builds a second service whose in-memory document
  /// predates the first shell's import pass; without this the new shell would
  /// start the migration again.
  Future<void> refreshMarkerFromBackend() async {
    if (_locked || _encrypted || !_initialized) return;
    // Serialize with in-flight writes: reloading outside the tail could replace
    // `_document` with a pre-write copy, and the next mutation would then
    // persist that stale document and drop a freshly captured entry.
    final pending = _writeTail;
    if (pending != null) {
      try {
        await pending;
      } on Object {
        // A failed write already surfaced to its caller; the reload below
        // still needs to run against whatever the backend holds.
      }
    }
    try {
      final reloaded = await _keychainBackend.load();
      if (reloaded != null) _setDocument(reloaded);
    } on Object {
      // Keep the in-memory document.
    }
  }

  Future<void> markLegacyImported(int version) {
    return _mutate(
      (document) => document.copyWith(legacyImportVersion: version),
    );
  }

  Future<void> initialize() async {
    if (_initialized) return;
    _encrypted = await _encryptedBackend.isInitialized;
    if (_encrypted) {
      _masterPassphrase = await _readRememberedPassphrase();
      _locked = true;
      _setDocument(null);
      _initialized = true;
      return;
    }
    _locked = false;
    _setDocument(await _keychainBackend.load());
    _initialized = true;
  }

  /// Unlocks silently with the remembered master password when available.
  ///
  /// Used at boot and by functional read paths; it never prompts. The UI still
  /// requires a fresh password before revealing a stored value.
  Future<bool> tryAutoUnlock() async {
    if (!_encrypted || !_locked) return true;
    final passphrase = _masterPassphrase ?? await _readRememberedPassphrase();
    if (passphrase == null || passphrase.isEmpty) return false;
    try {
      await unlock(passphrase, remember: false);
      return true;
    } on Object {
      return false;
    }
  }

  /// Verifies a password entered for an explicit reveal.
  Future<bool> verifyMasterPassphrase(String passphrase) async {
    final expected = _masterPassphrase ?? await _readRememberedPassphrase();
    if (expected == null || expected.isEmpty) return false;
    return expected == passphrase;
  }

  Future<void> unlock(String passphrase, {bool remember = true}) async {
    if (!_encrypted) return;
    await _encryptedBackend.unlock(passphrase);
    _setDocument(await _encryptedBackend.load());
    _locked = false;
    _masterPassphrase = passphrase;
    if (remember) await _writeRememberedPassphrase(passphrase);
  }

  Future<void> lock() async {
    if (!_encrypted) return;
    _encryptedBackend.lock();
    _setDocument(null);
    _locked = true;
    _masterPassphrase = null;
    // An explicit lock forgets the remembered password so the next functional
    // read prompts instead of silently re-unlocking. Await the delete so a
    // quick unlock cannot race it and re-arm auto-unlock.
    await _deleteRememberedPassphrase();
  }

  Future<List<VaultEntry>> list({
    String query = '',
    VaultEntryType? type,
    Set<String> tags = const {},
  }) async {
    final document = _requireDocument();
    final needle = query.trim().toLowerCase();
    final matches = document.entries.where((entry) {
      if (type != null && entry.type != type) return false;
      if (tags.isNotEmpty && !tags.every(entry.tags.contains)) return false;
      if (needle.isEmpty) return true;
      if (entry.title.toLowerCase().contains(needle)) return true;
      if (entry.tags.any((tag) => tag.toLowerCase().contains(needle))) {
        return true;
      }
      return entry.fields.values.any(
        (value) => value.toLowerCase().contains(needle),
      );
    }).toList();
    matches.sort((a, b) {
      if (a.favorite != b.favorite) return a.favorite ? -1 : 1;
      return b.updatedAt.compareTo(a.updatedAt);
    });
    return List.unmodifiable(matches);
  }

  Future<VaultEntry?> get(String id) async {
    _requireDocument();
    return _index[id];
  }

  Future<void> upsert(VaultEntry entry) {
    return _mutate((document) {
      final now = DateTime.now().millisecondsSinceEpoch;
      final normalized = entry.copyWith(
        createdAt: entry.createdAt == 0 ? now : entry.createdAt,
        updatedAt: now,
      );
      final entries = [...document.entries];
      final index = entries.indexWhere((e) => e.id == entry.id);
      if (index >= 0) {
        entries[index] = normalized;
      } else {
        entries.add(normalized);
      }
      return document.copyWith(entries: entries);
    });
  }

  Future<void> delete(String id) {
    return _mutate(
      (document) => document.copyWith(
        entries: [
          for (final entry in document.entries)
            if (entry.id != id) entry,
        ],
      ),
    );
  }

  Future<String?> readField(String entryId, String field) async {
    final entry = await get(entryId);
    final value = entry?.fields[field];
    return (value == null || value.isEmpty) ? null : value;
  }

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
    VaultEntry? entry;
    for (final candidate in source?.entries ?? const <VaultEntry>[]) {
      if (candidate.id == entryId) {
        entry = candidate;
        break;
      }
    }
    if (entry == null) return false;
    for (final field in fields.entries) {
      if (entry.fields[field.key] != field.value) return false;
    }
    return true;
  }

  Future<void> enableEncryptedBackend(String passphrase) async {
    if (_encrypted) throw const VaultStorageException('alreadyEncrypted');
    final document = _requireDocument();
    AppLogger.instance.i('[vault] enable: encrypting');
    await _encryptedBackend.initialize(document, passphrase);
    AppLogger.instance.i('[vault] enable: clearing keychain');
    await _keychainBackend.clear();
    _setDocument(document);
    _encrypted = true;
    _locked = false;
    _masterPassphrase = passphrase;
    AppLogger.instance.i('[vault] enable: remembering master');
    await _writeRememberedPassphrase(passphrase);
    AppLogger.instance.i('[vault] enable: done');
  }

  Future<void> disableEncryptedBackend() async {
    if (!_encrypted) throw const VaultStorageException('notEncrypted');
    final document = _requireDocument();
    await _keychainBackend.save(document);
    final verified = await _keychainBackend.load();
    if (verified == null) {
      throw const VaultStorageException('keychainVerifyFailed');
    }
    await _encryptedBackend.clear();
    _setDocument(verified);
    _encrypted = false;
    _locked = false;
    _masterPassphrase = null;
    await _deleteRememberedPassphrase();
  }

  Future<String?> _readRememberedPassphrase() async {
    try {
      return await _masterKeyStore?.read(_masterKey);
    } on Object {
      return null;
    }
  }

  Future<void> _writeRememberedPassphrase(String passphrase) async {
    try {
      await _masterKeyStore?.write(_masterKey, passphrase);
    } on Object {
      // Auto-unlock is best-effort; the session still works after an unlock.
    }
  }

  Future<void> _deleteRememberedPassphrase() async {
    try {
      await _masterKeyStore?.delete(_masterKey);
    } on Object {
      // Ignore: the in-memory password is already cleared.
    }
  }

  void _setDocument(VaultDocument? document) {
    _document = document;
    _index = {
      for (final entry in document?.entries ?? const <VaultEntry>[])
        entry.id: entry,
    };
  }

  VaultDocument _requireDocument() {
    if (_locked) throw const VaultLockedException();
    return _document ?? const VaultDocument();
  }

  Future<void> _mutate(VaultDocument Function(VaultDocument) update) {
    if (!_initialized) {
      return Future<void>.error(
        const VaultStorageException('notInitialized'),
      );
    }
    final previous = _writeTail ?? Future<void>.value();
    final next = previous.then((_) async {
      final document = update(_requireDocument());
      if (_encrypted) {
        await _encryptedBackend.save(document);
      } else {
        await _keychainBackend.save(document);
      }
      _setDocument(document);
    });
    _writeTail = next.catchError((_) {});
    return next;
  }
}
