import 'vault_document_store.dart';

/// Public facade over the vault document store.
///
/// UI and cubits depend on this type; the storage/encryption/maintenance
/// implementation lives in [VaultDocumentStore] so it can be tested and
/// evolved without widening the facade.
class VaultService extends VaultDocumentStore {
  VaultService({
    required super.keychainBackend,
    required super.encryptedBackend,
    super.masterKeyStore,
    super.homeVault,
  });
}
