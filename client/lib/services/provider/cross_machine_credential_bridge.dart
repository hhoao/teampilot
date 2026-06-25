import '../../models/team_config.dart';
import '../../repositories/app_provider_repository.dart';
import '../cli/registry/config_profile/config_profile_context.dart';
import '../provider/credential_binding.dart';
import 'claude/claude_provider_credentials_service.dart';
import 'codex/codex_auth_artifacts.dart';
import 'codex/codex_provider_credentials_service.dart';
import 'provider_catalog_access.dart';

/// Copies provider credential artifacts from the control plane onto a work
/// machine before launch-time linking / provisioning.
abstract final class CrossMachineCredentialBridge {
  CrossMachineCredentialBridge._();

  static Future<bool> materializeClaudeCredential({
    required ConfigProfilePaths catalog,
    required ConfigProfileDelegate work,
    required String providerId,
    required CredentialBindingKind binding,
  }) async {
    final catalogSvc = ClaudeProviderCredentialsService(
      fs: catalog.fs,
      basePath: catalog.basePath,
      resolveHomeDirectory: () => catalog.home,
    );
    final workSvc = ClaudeProviderCredentialsService(
      fs: work.fs,
      basePath: work.basePath,
      resolveHomeDirectory: () => work.home,
    );
    final src = catalogSvc.effectiveCredentialPath(
      providerId,
      binding: binding,
      homeDirectory: catalog.home,
    );
    final bytes = await catalog.fs.readBytes(src);
    if (bytes == null || bytes.isEmpty) return false;

    final dest = workSvc.credentialPath(providerId);
    await work.fs.ensureDir(workSvc.providerDir(providerId));
    await work.fs.writeBytes(dest, bytes);
    return true;
  }

  static Future<bool> materializeCodexAuth({
    required ConfigProfilePaths catalog,
    required ConfigProfileDelegate work,
    required String providerId,
  }) async {
    final catalogSvc = CodexProviderCredentialsService(
      fs: catalog.fs,
      basePath: catalog.basePath,
    );
    final src = catalogSvc.credentialPath(providerId);
    final bytes = await catalog.fs.readBytes(src);
    if (bytes == null || bytes.isEmpty) return false;

    final dest = work.pathContext.join(
      work.basePath,
      'providers',
      CliTool.codex.value,
      providerId,
      CodexAuthArtifacts.authFileName,
    );
    await work.fs.ensureDir(work.pathContext.dirname(dest));
    await work.fs.writeBytes(dest, bytes);
    return true;
  }

  static Future<CredentialBindingKind> claudeBindingFor(
    ConfigProfilePaths catalog,
    String providerId,
  ) async {
    final providers = await providerCatalogRepository(
      catalog,
    ).loadProviders(CliTool.claude);
    final provider = providers.where((p) => p.id == providerId).firstOrNull;
    if (provider == null) return CredentialBindingKind.linked;
    return resolveCredentialBinding(provider);
  }
}
