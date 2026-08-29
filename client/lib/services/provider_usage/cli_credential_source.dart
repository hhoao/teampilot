import '../../models/managed_provider.dart';
import 'managed_provider_usage_adapter.dart';

/// Reads CLI-owned authentication for `cli:<id>` credential sources.
///
/// Implementations may use OAuth sessions, a platform credential store, or a
/// remote runtime. They must not read CLI provider configuration files.
abstract interface class OfficialSubscriptionAuthReader {
  Future<ProviderCredentialScope?> read(ManagedProvider provider);
}

class CliCredentialSourceResolver {
  const CliCredentialSourceResolver({required this.readers});

  final Map<String, OfficialSubscriptionAuthReader> readers;

  Future<ProviderCredentialScope> read(String source) async {
    const prefix = 'cli:';
    if (!source.startsWith(prefix)) {
      throw const ManagedProviderUsageQueryError(
        ManagedProviderUsageQueryErrorCode.missingCredential,
      );
    }
    final id = source.substring(prefix.length);
    final reader = readers[id];
    if (reader == null) {
      throw const ManagedProviderUsageQueryError(
        ManagedProviderUsageQueryErrorCode.missingCredential,
      );
    }
    final dummy = ManagedProvider(
      id: id,
      name: id,
      kind: ManagedProviderKind.subscriptionQuota,
      adapterId: 'http-json',
    );
    final scope = await reader.read(dummy);
    if (scope == null || scope.isEmpty) {
      throw const ManagedProviderUsageQueryError(
        ManagedProviderUsageQueryErrorCode.missingCredential,
      );
    }
    return scope;
  }
}
