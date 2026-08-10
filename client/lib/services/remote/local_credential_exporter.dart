import '../../models/app_provider_config.dart';
import '../../repositories/app_provider_repository.dart';
import '../cli/registry/capabilities/credential_export_capability.dart';
import '../cli/registry/cli_tool_registry.dart';
import '../storage/app_storage.dart';
import 'remote_credential_materializer.dart';

/// Exports home (control-plane) provider catalog + credential files for
/// opt-in push to a remote work machine.
class LocalCredentialExporter {
  LocalCredentialExporter({String? basePath, String? home})
    : _basePath = basePath ?? AppStorage.appDataRoot,
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
      final exported = await _exportCredential(cli, provider);
      if (exported != null) files.add(exported);
    }

    return files;
  }

  Future<CredentialFile?> _exportCredential(
    CliTool cli,
    AppProviderConfig provider,
  ) async {
    final cap = CliToolRegistry.builtIn()
        .capability<CredentialExportCapability>(cli);
    if (cap == null) return null;
    return cap.exportCredential(
      fs: AppStorage.fs,
      basePath: _basePath,
      home: _home,
      provider: provider,
    );
  }
}
