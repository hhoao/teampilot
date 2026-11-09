import 'dart:async';
import 'dart:convert';

import '../../models/vault_document.dart';
import '../../repositories/ssh_credential_store.dart';
import '../../repositories/vault_repository.dart';
import '../../services/storage/home_storage.dart';
import '../../utils/logging/logger.dart';
import 'credential_backend.dart';
import 'encrypted_vault_backend.dart';
import 'vault_errors.dart';
import 'vault_service.dart';

/// Plain-JSON credential backend stored on the home plane.
///
/// The device keychain is intentionally not used here: business credentials
/// must live on the remote host so every device paired with the same home sees
/// the same set. `EncryptedVaultBackend` (also home-plane) takes over when the
/// user enables encryption.
class RemoteVaultBackend implements CredentialBackend {
  const RemoteVaultBackend(this._repository);

  final VaultRepository _repository;

  @override
  String get kind => 'remote';

  @override
  bool get needsUnlock => false;

  @override
  Future<VaultDocument?> load() async {
    final raw = await _repository.readRaw();
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) throw const FormatException();
      return VaultDocument.fromJson(Map<String, Object?>.from(decoded));
    } on Object {
      throw const VaultFormatException('remote vault document is malformed');
    }
  }

  @override
  Future<void> save(VaultDocument document) =>
      _repository.writeRaw(jsonEncode(document.toJson()));

  @override
  Future<void> clear() => _repository.archive();
}

/// Business-credential vault. Both backends resolve through the live
/// [HomeStorage], so the data follows the current home plane (the remote host).
class HomeVaultService extends VaultService {
  HomeVaultService({
    required HomeStorage storage,
    required SecureKeyValueStore keyStore,
  }) : super(
         keychainBackend: RemoteVaultBackend(VaultRepository.forHome(storage)),
         // Distinct file: `enableEncryptedBackend` writes the encrypted
         // document here, then clears the plain backend. Sharing one file
         // would archive the document it just wrote.
         encryptedBackend: EncryptedVaultBackend(
           repository: VaultRepository.forHome(
             storage,
             fileName: 'business.enc.json',
           ),
         ),
         masterKeyStore: keyStore,
       );
}

/// Owns the current [HomeVaultService] and rebuilds it when the home plane
/// changes. Readers resolve [service] at call time, so a swap never leaves a
/// stale vault pointing at the previous host.
class HomeVaultScope {
  HomeVaultScope({
    required HomeStorage storage,
    required SecureKeyValueStore keyStore,
  }) : _storage = storage,
       _keyStore = keyStore {
    _service = _build();
    _subscription = storage.changes.listen((_) {
      _service = _build();
      unawaited(prepare());
    });
  }

  final HomeStorage _storage;
  final SecureKeyValueStore _keyStore;
  late HomeVaultService _service;
  StreamSubscription<StoragePlaneChange>? _subscription;

  HomeVaultService get service => _service;

  HomeVaultService _build() =>
      HomeVaultService(storage: _storage, keyStore: _keyStore);

  /// Initialize + best-effort auto-unlock. Safe to call after every swap.
  Future<void> prepare() async {
    try {
      await _service.initialize();
      await _service.tryAutoUnlock();
    } on Object catch (error, stackTrace) {
      appLogger.w(
        '[home-vault] prepare failed: $error',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
  }
}
