import 'managed_provider_secret_store.dart';

class ManagedProviderCredentialTransaction {
  const ManagedProviderCredentialTransaction(this.store);

  final ManagedProviderSecretStore store;

  Future<T> run<T>({
    required String credentialRef,
    required Map<String, String> nextValues,
    required Future<T> Function() persistProvider,
  }) => store.runCredentialTransaction(
    credentialRef: credentialRef,
    nextValues: nextValues,
    persistProvider: persistProvider,
  );
}
