import '../../models/managed_provider.dart';
import 'managed_provider_cli_binding.dart';
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
    final rowId = source.substring(prefix.length).trim();
    if (rowId.isEmpty) {
      throw const ManagedProviderUsageQueryError(
        ManagedProviderUsageQueryErrorCode.missingCredential,
      );
    }
    // Readers are keyed by CLI value; any row id (per-entry or legacy)
    // resolves through its CLI's reader, which reads the isolated
    // `providers/<cli>/<rowId>/` directory.
    final cli = ManagedProviderCliBinding().cliForCredentialSource(source);
    final reader = cli == null ? null : readers[cli.value];
    if (reader == null) {
      throw const ManagedProviderUsageQueryError(
        ManagedProviderUsageQueryErrorCode.missingCredential,
      );
    }
    final dummy = ManagedProvider(
      id: rowId,
      name: rowId,
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
