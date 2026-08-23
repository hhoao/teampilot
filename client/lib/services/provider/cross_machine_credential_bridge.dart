import '../../models/app_provider_config.dart';
import '../../models/team_config.dart';
import '../cli/registry/config_profile/config_profile_context.dart';
import '../launch/work_plane_paths.dart';
import '../provider/credential_binding.dart';
import '../cli/claude/provider/claude_provider_credentials_service.dart';
import '../cli/codex/provider/codex_auth_artifacts.dart';
import '../cli/codex/provider/codex_provider_credentials_service.dart';
import '../cli/cursor/provider/cursor_auth_artifacts.dart';
import '../cli/cursor/provider/cursor_home_layout.dart';
import '../cli/cursor/provider/cursor_provider_credentials_service.dart';
import '../cli/opencode/provider/opencode_credential_materializer.dart';
import '../cli/opencode/provider/opencode_data_layout.dart';
import '../storage/runtime_layout.dart';
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
    await ensureWorkDir(work.fs, workSvc.providerDir(providerId));
    await writeWorkBytes(work.fs, dest, bytes);
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

    final dest = work.joinWork(
      work.basePath,
      'providers',
      CliTool.codex.value,
      providerId,
      CodexAuthArtifacts.authFileName,
    );
    await ensureWorkDir(work.fs, work.workPathContext.dirname(dest));
    await writeWorkBytes(work.fs, dest, bytes);
    return true;
  }

  static Future<bool> materializeCursorCredential({
    required ConfigProfilePaths catalog,
    required ConfigProfileDelegate work,
    required String providerId,
  }) async {
    final catalogSvc = CursorProviderCredentialsService(
      fs: catalog.fs,
      basePath: catalog.basePath,
    );
    final probe = await catalogSvc.probe(providerId);
    if (!probe.isReady) return false;

    final bytes = await catalog.fs.readBytes(probe.credentialPath);
    if (bytes == null || bytes.isEmpty) return false;

    final workSvc = CursorProviderCredentialsService(
      fs: work.fs,
      basePath: work.basePath,
    );
    final workLayout = CursorHomeLayout(pathContext: work.workPathContext);
    final workHome = workSvc.providerHome(providerId);
    final dest = workLayout.authJson(workHome);
    await ensureWorkDir(work.fs, work.workPathContext.dirname(dest));
    await writeWorkBytes(work.fs, dest, bytes);

    final catalogHome = catalogSvc.providerHome(providerId);
    final catalogLayout = CursorHomeLayout(pathContext: catalog.fs.pathContext);
    final srcCursorDir = catalogLayout.cursorDir(catalogHome);
    final destCursorDir = workLayout.cursorDir(workHome);
    for (final relativePath in [
      ...CursorAuthArtifacts.cursorDirRequired,
      ...CursorAuthArtifacts.cursorDirOptional,
    ]) {
      final src = catalog.fs.pathContext.join(srcCursorDir, relativePath);
      final artifactBytes = await catalog.fs.readBytes(src);
      if (artifactBytes == null || artifactBytes.isEmpty) continue;
      final artifactDest = work.joinWork(destCursorDir, relativePath);
      await ensureWorkDir(
        work.fs,
        work.workPathContext.dirname(artifactDest),
      );
      await writeWorkBytes(work.fs, artifactDest, artifactBytes);
    }
    return true;
  }

  /// Copies merged `cli-defaults/flashskyai/llm_config.json` to the work plane.
  static Future<bool> materializeFlashskyaiLlmConfig({
    required ConfigProfilePaths catalog,
    required ConfigProfileDelegate work,
  }) async {
    final catalogLayout = RuntimeLayout(
      teampilotRoot: catalog.basePath,
      fs: catalog.fs,
    );
    final workLayout = RuntimeLayout(teampilotRoot: work.basePath, fs: work.fs);
    final src = catalogLayout.appFlashskyaiLlmConfigFile;
    final dest = work.normalizeWork(workLayout.appFlashskyaiLlmConfigFile);
    final content = await catalog.fs.readString(src);
    if (content != null && content.trim().isNotEmpty) {
      await ensureWorkDir(work.fs, work.workPathContext.dirname(dest));
      await writeWorkString(work.fs, dest, content);
      return true;
    }
    final bytes = await catalog.fs.readBytes(src);
    if (bytes == null || bytes.isEmpty) return false;
    await ensureWorkDir(work.fs, work.workPathContext.dirname(dest));
    await writeWorkBytes(work.fs, dest, bytes);
    return true;
  }

  static Future<bool> materializeOpencodeAuth({
    required ConfigProfilePaths catalog,
    required ConfigProfileDelegate work,
    required AppProviderConfig provider,
  }) async {
    if (!OpencodeCredentialMaterializer.isReady(provider)) return false;

    const layout = OpencodeDataLayout();
    final providerId = provider.id.trim();
    final workProviderDir = work.joinWork(
      work.basePath,
      'providers',
      CliTool.opencode.value,
      providerId,
    );
    final dest = work.normalizeWork(
      layout.providerAuthJsonPath(workProviderDir),
    );
    return await OpencodeCredentialMaterializer.writeAuthArtifact(
      fs: work.fs,
      basePath: work.basePath,
      provider: provider,
    ) &&
        (await work.fs.stat(dest)).isFile;
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
