// client/lib/services/vault/keychain_vault_backend.dart
import 'dart:convert';

import '../../models/vault_document.dart';
import '../../repositories/ssh_credential_store.dart';
import 'credential_backend.dart';
import 'vault_errors.dart';

/// 默认后端：整份文档放在系统钥匙串的单个 key 下。
class KeychainVaultBackend implements CredentialBackend {
  const KeychainVaultBackend(this._store);

  static const storageKey = 'teampilot.vault.v1.document';

  final SecureKeyValueStore _store;

  @override
  String get kind => 'keychain';

  @override
  bool get needsUnlock => false;

  @override
  Future<VaultDocument?> load() async {
    final raw = await _store.read(storageKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) throw const FormatException();
      return VaultDocument.fromJson(Map<String, Object?>.from(decoded));
    } on Object {
      throw const VaultFormatException('keychain document is malformed');
    }
  }

  @override
  Future<void> save(VaultDocument document) async {
    try {
      await _store.write(storageKey, jsonEncode(document.toJson()));
    } on Object {
      throw const VaultStorageException('keychainWriteFailed');
    }
  }

  @override
  Future<void> clear() async {
    try {
      await _store.delete(storageKey);
    } on Object {
      throw const VaultStorageException('keychainDeleteFailed');
    }
  }
}
