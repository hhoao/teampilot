import '../../../models/app_provider_config.dart';
import '../../../models/team_config.dart';
import '../../../repositories/provider_persistence/provider_persistence_strategy.dart';
import 'provider/opencode_credential_kind.dart';
import 'provider/opencode_credential_materializer.dart';

/// OpenCode: probe catalog-stored credentials on load. No separate auth store.
final class OpencodeProviderPersistence extends ProviderPersistenceStrategy {
  const OpencodeProviderPersistence();

  @override
  CliTool get cli => CliTool.opencode;

  @override
  Future<List<AppProviderConfig>> reconcileLoaded(
    ProviderPersistenceContext ctx,
    List<AppProviderConfig> providers,
  ) async {
    final probed = providers.map((provider) {
      if (!OpencodeCredentialKindResolver.needsCredential(provider)) {
        return provider;
      }
      return provider.withCredentialProbe(
        OpencodeCredentialMaterializer.probe(provider),
      );
    }).toList();

    final changed = probed.any(
      (next) => providers.any(
        (previous) =>
            previous.id == next.id &&
            (previous.credentialStatus != next.credentialStatus ||
                previous.credentialUpdatedAt != next.credentialUpdatedAt),
      ),
    );
    if (changed) {
      await ctx.save(cli, probed);
    }
    return probed;
  }
}
