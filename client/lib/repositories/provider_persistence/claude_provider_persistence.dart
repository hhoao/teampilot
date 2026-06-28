import '../../models/app_provider_config.dart';
import '../../models/credential_action_result.dart';
import '../../services/provider/claude/claude_official_provider.dart';
import '../../services/provider/claude/claude_provider_credentials_service.dart';
import '../../services/provider/credential_binding.dart';
import '../../utils/logger_utils.dart';
import 'provider_persistence_strategy.dart';

/// Claude: probe official-account credentials on load; clean stale native dirs
/// on save; materialize linked bindings to global `~/.claude`.
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
  CredentialProbeFn get credentialProbe => (provider) {
    final binding = resolveCredentialBinding(provider);
    return _credentials.probe(
      provider.id,
      binding: binding,
    );
  };

  @override
  CredentialImportFn get credentialImport => (provider, {required homeDirectory, replace = false}) {
    final binding = resolveCredentialBinding(provider);
    return _credentials.importFromGlobal(
      provider.id,
      homeDirectory: homeDirectory,
      replace: replace || binding == CredentialBindingKind.linked,
      binding: binding,
    );
  };

  @override
  Future<List<AppProviderConfig>> reconcileLoaded(
    ProviderPersistenceContext ctx,
    List<AppProviderConfig> providers,
  ) async {
    final home = ctx.resolveHome();
    if (home.isNotEmpty) {
      await Future.wait(
        providers.map((provider) async {
          if (!appliesToProbe(provider)) return;
          if (resolveCredentialBinding(provider) != CredentialBindingKind.linked) {
            return;
          }
          await _credentials.materializeLinkedBinding(
            provider.id,
            homeDirectory: home,
            replace: true,
          );
        }),
      );
    }
    return probeOfficialCredentials(ctx, providers);
  }

  @override
  Future<List<AppProviderConfig>> importOfficialCredentialsFromGlobal(
    ProviderPersistenceContext ctx,
    List<AppProviderConfig> providers, {
    bool replace = false,
  }) async {
    final home = ctx.resolveHome();
    if (home.isEmpty) return providers;

    for (final provider in providers) {
      if (!appliesToProbe(provider)) continue;
      final binding = resolveCredentialBinding(provider);
      if (binding == CredentialBindingKind.linked) {
        final importResult = await _credentials.importFromGlobal(
          provider.id,
          homeDirectory: home,
          replace: true,
          binding: binding,
        );
        if (!importResult.ok) {
          _logImportFailure(provider.id, importResult);
        }
        continue;
      }
      final probe = await _credentials.probe(
        provider.id,
        binding: binding,
        homeDirectory: home,
      );
      if (probe.isReady) continue;
      final importResult = await _credentials.importFromGlobal(
        provider.id,
        homeDirectory: home,
        replace: replace,
        binding: binding,
      );
      if (!importResult.ok) {
        _logImportFailure(provider.id, importResult);
      }
    }
    return providers;
  }

  @override
  Future<void> reconcileSaved(
    ProviderPersistenceContext ctx,
    List<AppProviderConfig> providers,
  ) async {
    final home = ctx.resolveHome();
    if (home.isNotEmpty) {
      for (final provider in providers) {
        if (!appliesToProbe(provider)) continue;
        if (resolveCredentialBinding(provider) != CredentialBindingKind.linked) {
          continue;
        }
        await _credentials.materializeLinkedBinding(
          provider.id,
          homeDirectory: home,
          replace: true,
        );
      }
    }
    await removeStaleProviderDirs(ctx, cli, providers);
  }

  void _logImportFailure(String providerId, CredentialActionResult importResult) {
    AppLogger.instance.d(
      'Credential import failed for $providerId: '
      '${importResult.failure?.code.name}'
      '${importResult.failure?.path == null ? '' : ' (${importResult.failure!.path})'}',
    );
  }
}
