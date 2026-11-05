import '../../repositories/ssh_credential_store.dart';
import 'encrypted_vault_backend.dart';
import 'keychain_vault_backend.dart';
import 'vault_document_store.dart';

/// Public facade over the vault document store.
///
/// UI and cubits depend on this type; the storage/encryption/maintenance
/// implementation lives in [VaultDocumentStore] so it can be tested and
/// evolved without widening the facade.
class VaultService extends VaultDocumentStore {
  VaultService({
    required KeychainVaultBackend keychainBackend,
    required EncryptedVaultBackend encryptedBackend,
    SecureKeyValueStore? masterKeyStore,
  }) : super(
         keychainBackend: keychainBackend,
         encryptedBackend: encryptedBackend,
         masterKeyStore: masterKeyStore,
       );
}
