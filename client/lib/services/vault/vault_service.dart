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
