import '../../models/app_provider_config.dart';
import '../../models/claude_credential_link_result.dart';
import '../../models/credential_action_result.dart';
import '../../services/io/filesystem.dart';
import '../../services/provider/tool_config_generator.dart';
import '../../utils/logger_utils.dart';

/// Thrown when persisting a provider's native tool config fails (e.g. an
/// invalid Codex `config.toml`).
class AppProviderRepositoryException implements Exception {
  AppProviderRepositoryException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Persists refreshed providers for [cli] (used by credential probing to
/// write back updated credential status).
typedef SaveProviders =
    Future<void> Function(CliTool cli, List<AppProviderConfig> providers);

typedef CredentialProbeFn =
    Future<CredentialProbe> Function(AppProviderConfig provider);

typedef CredentialImportFn =
    Future<CredentialActionResult> Function(
      AppProviderConfig provider, {
      required String homeDirectory,
      bool replace,
    });

/// Collaborators the repository hands to a [ProviderPersistenceStrategy].
class ProviderPersistenceContext {
  const ProviderPersistenceContext({
    required this.fs,
    required this.basePath,
    required this.generator,
    required this.resolveHome,
    required this.save,
  });

  final Filesystem fs;
  final String basePath;
  final ToolConfigGenerator generator;

  /// Resolves the user home dir (`AppStorage.home`) used for credential
  /// import-from-global. Lazy: only invoked when a provider needs importing, so
  /// save/load paths that never import don't touch global storage state.
  final String Function() resolveHome;

  /// Persists refreshed providers back to disk.
  final SaveProviders save;
}

/// Per-CLI provider persistence concerns: credential reconciliation on load and
/// native tool-config materialization on save. One implementation per CLI,
/// keeping each CLI's logic in its own file instead of a repository switch.
abstract class ProviderPersistenceStrategy {
  const ProviderPersistenceStrategy();

  /// CLI this strategy handles.
  CliTool get cli;

  /// Reconcile providers just loaded from disk (default: no change).
  Future<List<AppProviderConfig>> reconcileLoaded(
    ProviderPersistenceContext ctx,
    List<AppProviderConfig> providers,
  ) async => providers;

  /// Materialize / clean native tool configs after a save (default: nothing).
  Future<void> reconcileSaved(
    ProviderPersistenceContext ctx,
    List<AppProviderConfig> providers,
  ) async {}
}

/// Shared official-account credential probe loop for the OAuth-style CLIs.
mixin CredentialProbeSupport on ProviderPersistenceStrategy {
  /// Whether [provider] is an official account row that should be probed.
  bool appliesToProbe(AppProviderConfig provider);

  CredentialProbeFn get credentialProbe;
  CredentialImportFn get credentialImport;

  /// Imports official-account credentials from the global home dir when not
  /// yet ready locally. Only call from explicit user/wizard import flows.
  Future<List<AppProviderConfig>> importOfficialCredentialsFromGlobal(
    ProviderPersistenceContext ctx,
    List<AppProviderConfig> providers, {
    bool replace = false,
  }) async {
    final home = ctx.resolveHome();
    if (home.isEmpty) return providers;

    for (final provider in providers) {
      if (!appliesToProbe(provider)) continue;
      final probe = await credentialProbe(provider);
      if (probe.isReady) continue;
      final importResult = await credentialImport(
        provider,
        homeDirectory: home,
        replace: replace,
      );
      if (!importResult.ok) {
        AppLogger.instance.d(
          'Credential import failed for ${provider.id}: '
          '${importResult.failure?.code.name}'
          '${importResult.failure?.path == null ? '' : ' (${importResult.failure!.path})'}',
        );
      }
    }
    return providers;
  }

  /// Probes each applicable provider and persists refreshed credential status
  /// when it changes. Does not import from global home — use
  /// [importOfficialCredentialsFromGlobal] for that.
  Future<List<AppProviderConfig>> probeOfficialCredentials(
    ProviderPersistenceContext ctx,
    List<AppProviderConfig> providers,
  ) async {
    var changed = false;
    final probed = <AppProviderConfig>[];
    for (final provider in providers) {
      if (!appliesToProbe(provider)) {
        probed.add(provider);
        continue;
      }
      final probe = await credentialProbe(provider);
      final next = provider.withCredentialProbe(probe);
      if (next.credentialStatus != provider.credentialStatus ||
          next.credentialUpdatedAt != provider.credentialUpdatedAt) {
        changed = true;
      }
      probed.add(next);
    }
    if (changed) await ctx.save(cli, probed);
    return probed;
  }
}

/// Removes `providers/<cli>/<id>` directories no longer backed by a provider.
Future<void> removeStaleProviderDirs(
  ProviderPersistenceContext ctx,
  CliTool cli,
  List<AppProviderConfig> providers,
) async {
  final path = ctx.fs.pathContext;
  final expected = providers.map((p) => p.id).toSet();
  final root = path.join(ctx.basePath, 'providers', cli.value);
  if (!(await ctx.fs.stat(root)).isDirectory) return;
  for (final entry in await ctx.fs.listDir(root)) {
    if (!entry.isDirectory) continue;
    if (!expected.contains(entry.name)) {
      await ctx.fs.removeRecursive(path.join(root, entry.name));
    }
  }
}
