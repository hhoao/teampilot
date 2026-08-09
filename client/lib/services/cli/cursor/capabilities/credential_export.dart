import '../../../../models/app_provider_config.dart';
import '../../../io/filesystem.dart';
import '../../../remote/remote_credential_materializer.dart';
import '../../registry/capabilities/credential_export_capability.dart';
import '../provider/cursor_provider_credentials_service.dart';

final class CursorCredentialExport implements CredentialExportCapability {
  const CursorCredentialExport();

  @override
  Future<CredentialFile?> exportCredential({
    required Filesystem fs,
    required String basePath,
    required String home,
    required AppProviderConfig provider,
  }) async {
    final toolRoot = fs.pathContext.join(basePath, 'providers', provider.cli.value);
    final probe = await CursorProviderCredentialsService(
      fs: fs,
      basePath: basePath,
    ).probe(provider.id);
    if (!probe.isReady) return null;
    final content = await fs.readString(probe.credentialPath);
    if (content == null || content.trim().isEmpty) return null;
    final relative = fs.pathContext.relative(
      probe.credentialPath,
      from: toolRoot,
    );
    return CredentialFile(relativePath: relative, content: content);
  }
}
