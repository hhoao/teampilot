import '../../models/app_provider_config.dart';
import '../../services/provider/opencode/opencode_provider_credentials_service.dart';
import 'provider_persistence_strategy.dart';

/// Opencode: probe official-account credentials on load. No native tool-config
/// materialization on save.
final class OpencodeProviderPersistence extends ProviderPersistenceStrategy
    with CredentialProbeSupport {
  OpencodeProviderPersistence({
    required OpencodeProviderCredentialsService credentials,
  }) : _credentials = credentials;

  final OpencodeProviderCredentialsService _credentials;

  @override
  CliTool get cli => CliTool.opencode;

  @override
  bool appliesToProbe(AppProviderConfig provider) =>
      provider.cli == CliTool.opencode && provider.isOfficial;

  @override
  CredentialProbeFn get credentialProbe =>
      (provider) => _credentials.probe(provider.id);

  @override
  CredentialImportFn get credentialImport =>
      (provider, {required homeDirectory, replace = false}) =>
          _credentials.importFromGlobal(
            provider.id,
            homeDirectory: homeDirectory,
            replace: replace,
          );

  @override
  Future<List<AppProviderConfig>> reconcileLoaded(
    ProviderPersistenceContext ctx,
    List<AppProviderConfig> providers,
  ) => probeOfficialCredentials(ctx, providers);
}
