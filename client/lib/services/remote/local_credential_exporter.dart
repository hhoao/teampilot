import '../../models/team_config.dart';
import '../../repositories/app_provider_repository.dart';
import '../provider/claude/claude_provider_credentials_service.dart';
import '../provider/codex/codex_auth_artifacts.dart';
import '../provider/codex/codex_provider_credentials_service.dart';
import '../provider/credential_binding.dart';
import '../provider/cursor/cursor_provider_credentials_service.dart';
import '../provider/opencode/opencode_data_layout.dart';
import '../provider/opencode/opencode_provider_credentials_service.dart';
import '../storage/app_storage.dart';
import 'remote_credential_materializer.dart';

/// Exports home (control-plane) provider catalog + credential files for
/// opt-in push to a remote work machine.
class LocalCredentialExporter {
  LocalCredentialExporter({
    String? basePath,
    String? home,
  }) : _basePath = basePath ?? AppStorage.appDataRoot,
       _home = home ?? AppStorage.home;

  final String _basePath;
  final String _home;

  Future<List<CredentialFile>> export(CliTool cli) async {
    final fs = AppStorage.fs;
    final repo = AppProviderRepository(basePath: _basePath, fs: fs);
    final files = <CredentialFile>[];

    final providersJson = await fs.readString(repo.providersPath(cli));
    if (providersJson != null && providersJson.trim().isNotEmpty) {
      files.add(
        CredentialFile(relativePath: 'providers.json', content: providersJson),
      );
    }

    final providers = await repo.loadProviders(cli);
    for (final provider in providers) {
      final exported = await _exportCredential(cli, provider.id);
      if (exported != null) files.add(exported);
    }

    return files;
  }

  Future<CredentialFile?> _exportCredential(CliTool cli, String providerId) async {
    final fs = AppStorage.fs;
    final toolRoot = fs.pathContext.join(_basePath, 'providers', cli.value);
    switch (cli) {
      case CliTool.claude:
        final providers = await AppProviderRepository(
          basePath: _basePath,
          fs: fs,
        ).loadProviders(cli);
        final provider = providers.where((p) => p.id == providerId).firstOrNull;
        if (provider == null) return null;
        final binding = resolveCredentialBinding(provider);
        final svc = ClaudeProviderCredentialsService(
          fs: fs,
          basePath: _basePath,
          resolveHomeDirectory: () => _home,
        );
        final path = svc.effectiveCredentialPath(
          providerId,
          binding: binding,
          homeDirectory: _home,
        );
        final content = await fs.readString(path);
        if (content == null || content.trim().isEmpty) return null;
        return CredentialFile(
          relativePath:
              '$providerId/${ClaudeProviderCredentialsService.credentialsFileName}',
          content: content,
        );
      case CliTool.codex:
        final path = CodexProviderCredentialsService(
          fs: fs,
          basePath: _basePath,
        ).credentialPath(providerId);
        final content = await fs.readString(path);
        if (content == null || content.trim().isEmpty) return null;
        return CredentialFile(
          relativePath: '$providerId/${CodexAuthArtifacts.authFileName}',
          content: content,
        );
      case CliTool.cursor:
        final probe = await CursorProviderCredentialsService(
          fs: fs,
          basePath: _basePath,
        ).probe(providerId);
        if (!probe.isReady) return null;
        final content = await fs.readString(probe.credentialPath);
        if (content == null || content.trim().isEmpty) return null;
        final relative = fs.pathContext.relative(
          probe.credentialPath,
          from: toolRoot,
        );
        return CredentialFile(relativePath: relative, content: content);
      case CliTool.opencode:
        final path = OpencodeProviderCredentialsService(
          fs: fs,
          basePath: _basePath,
        ).credentialPath(providerId);
        final content = await fs.readString(path);
        if (content == null || content.trim().isEmpty) return null;
        return CredentialFile(
          relativePath: '$providerId/${OpencodeDataLayout.authFileName}',
          content: content,
        );
      case CliTool.flashskyai:
        return null;
    }
  }
}
