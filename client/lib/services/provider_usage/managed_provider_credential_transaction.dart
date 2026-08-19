import 'managed_provider_secret_store.dart';

class ManagedProviderCredentialTransaction {
  const ManagedProviderCredentialTransaction(this.store);

  final ManagedProviderSecretStore store;

  Future<T> run<T>({
    required String credentialRef,
    required Map<String, String> nextValues,
    required Future<T> Function() persistProvider,
  }) async {
    final values = {
      for (final entry in nextValues.entries)
        if (entry.value.isNotEmpty) entry.key: entry.value,
    };
    if (values.isEmpty) return persistProvider();

    final previous = await store.read(credentialRef);
    final previousValues = {
      for (final field in previous.fields)
        if (previous.valueFor(field) != null) field: previous.valueFor(field)!,
    };

    await store.write(credentialRef, values);
    try {
      return await persistProvider();
    } on Object {
      if (previousValues.isEmpty) {
        await store.delete(credentialRef);
      } else {
        await store.write(credentialRef, previousValues);
      }
      rethrow;
    }
  }
}
