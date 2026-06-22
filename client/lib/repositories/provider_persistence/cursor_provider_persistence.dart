import '../../models/app_provider_config.dart';
import '../../services/provider/cursor/cursor_provider_credentials_service.dart';
import 'provider_persistence_strategy.dart';

/// Cursor: probe official-account credentials on load; clean stale native dirs
/// on save.
final class CursorProviderPersistence extends ProviderPersistenceStrategy
    with CredentialProbeSupport {
  CursorProviderPersistence({
    required CursorProviderCredentialsService credentials,
  }) : _credentials = credentials;

  final CursorProviderCredentialsService _credentials;

  @override
  CliTool get cli => CliTool.cursor;

  @override
  bool appliesToProbe(AppProviderConfig provider) =>
      provider.cli == CliTool.cursor && provider.isOfficial;

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

  @override
  Future<void> reconcileSaved(
    ProviderPersistenceContext ctx,
    List<AppProviderConfig> providers,
  ) => removeStaleProviderDirs(ctx, cli, providers);
}
