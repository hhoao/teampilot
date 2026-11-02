// client/lib/services/vault/vault_service.dart
import '../../models/vault_document.dart';
import '../../models/vault_entry.dart';
import 'encrypted_vault_backend.dart';
import 'keychain_vault_backend.dart';
import 'vault_errors.dart';

class VaultService {
  VaultService({
    required KeychainVaultBackend keychainBackend,
    required EncryptedVaultBackend encryptedBackend,
  }) : _keychainBackend = keychainBackend,
       _encryptedBackend = encryptedBackend;

  final KeychainVaultBackend _keychainBackend;
  final EncryptedVaultBackend _encryptedBackend;

  VaultDocument? _document;
  bool _encrypted = false;
  bool _locked = false;
  bool _initialized = false;
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
      if (reloaded != null) _document = reloaded;
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
      _locked = true;
      _document = null;
      _initialized = true;
      return;
    }
    _locked = false;
    _document = await _keychainBackend.load();
    _initialized = true;
  }

  Future<void> unlock(String passphrase) async {
    if (!_encrypted) return;
    await _encryptedBackend.unlock(passphrase);
    _document = await _encryptedBackend.load();
    _locked = false;
  }

  void lock() {
    if (!_encrypted) return;
    _encryptedBackend.lock();
    _document = null;
    _locked = true;
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
    for (final entry in _requireDocument().entries) {
      if (entry.id == id) return entry;
    }
    return null;
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
    await _encryptedBackend.initialize(document, passphrase);
    await _keychainBackend.clear();
    _document = document;
    _encrypted = true;
    _locked = false;
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
    _document = verified;
    _encrypted = false;
    _locked = false;
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
      _document = document;
    });
    _writeTail = next.catchError((_) {});
    return next;
  }
}
