import '../../models/app_provider_config.dart';
import '../../services/provider/codex/codex_official_provider.dart';
import '../../services/provider/codex/codex_provider_credentials_service.dart';
import 'provider_persistence_strategy.dart';

/// Codex: probe official OAuth credentials on load; write native `auth.json` /
/// `config.toml` and clean stale dirs on save.
final class CodexProviderPersistence extends ProviderPersistenceStrategy
    with CredentialProbeSupport {
  CodexProviderPersistence({
    required CodexProviderCredentialsService credentials,
  }) : _credentials = credentials;

  final CodexProviderCredentialsService _credentials;

  @override
  CliTool get cli => CliTool.codex;

  @override
  bool appliesToProbe(AppProviderConfig provider) =>
      isOfficialCodexOAuthProvider(provider);

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
  ) async {
    await _writeNativeToolConfigs(ctx, providers);
    await removeStaleProviderDirs(ctx, cli, providers);
  }

  Future<void> _writeNativeToolConfigs(
    ProviderPersistenceContext ctx,
    List<AppProviderConfig> providers,
  ) async {
    final path = ctx.fs.pathContext;
    final root = path.join(ctx.basePath, 'providers', 'codex');
    for (final provider in providers) {
      final codexDir = path.join(root, provider.id);
      await ctx.fs.ensureDir(codexDir);
      final authPath = path.join(codexDir, 'auth.json');
      final auth = ctx.generator.buildCodexAuth(provider);
      if (isOfficialCodexOAuthProvider(provider) && auth.isEmpty) {
        if ((await ctx.fs.stat(authPath)).isFile) {
          // Preserve OAuth credentials from `codex login` / import.
        } else {
          await ctx.generator.writeJsonAtomic(authPath, auth, fs: ctx.fs);
        }
      } else {
        await ctx.generator.writeJsonAtomic(authPath, auth, fs: ctx.fs);
      }
      final toml = ctx.generator.buildCodexConfigToml(provider);
      final error = ctx.generator.validateCodexToml(toml);
      if (error != null) {
        throw AppProviderRepositoryException(
          'Codex config.toml invalid for ${provider.id}: $error',
        );
      }
      final tomlPath = path.join(codexDir, 'config.toml');
      if (toml.trim().isNotEmpty) {
        await ctx.generator.writeTextAtomic(tomlPath, toml, fs: ctx.fs);
      } else if ((await ctx.fs.stat(tomlPath)).exists) {
        await ctx.fs.removeRecursive(tomlPath);
      }
    }
  }
}
