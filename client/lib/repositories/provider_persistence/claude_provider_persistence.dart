import '../../models/app_provider_config.dart';
import '../../services/provider/claude/claude_official_provider.dart';
import '../../services/provider/claude/claude_provider_credentials_service.dart';
import 'provider_persistence_strategy.dart';

/// Claude: probe official-account credentials on load; clean stale native dirs
/// on save.
final class ClaudeProviderPersistence extends ProviderPersistenceStrategy
    with CredentialProbeSupport {
  ClaudeProviderPersistence({
    required ClaudeProviderCredentialsService credentials,
  }) : _credentials = credentials;

  final ClaudeProviderCredentialsService _credentials;

  @override
  CliTool get cli => CliTool.claude;

  @override
  bool appliesToProbe(AppProviderConfig provider) =>
      provider.cli == CliTool.claude &&
      isOfficialClaudeSettings(provider.config);

  @override
  CredentialProbeFn get credentialProbe => _credentials.probe;

  @override
  CredentialImportFn get credentialImport => _credentials.importFromGlobal;

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
