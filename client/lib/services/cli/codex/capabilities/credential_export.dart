import '../../../../models/app_provider_config.dart';
import '../../../io/filesystem.dart';
import '../../../remote/remote_credential_materializer.dart';
import '../../registry/capabilities/credential_export_capability.dart';
import '../provider/codex_auth_artifacts.dart';
import '../provider/codex_provider_credentials_service.dart';

final class CodexCredentialExport implements CredentialExportCapability {
  const CodexCredentialExport();

  @override
  Future<CredentialFile?> exportCredential({
    required Filesystem fs,
    required String basePath,
    required String home,
    required AppProviderConfig provider,
  }) async {
    final path = CodexProviderCredentialsService(
      fs: fs,
      basePath: basePath,
    ).credentialPath(provider.id);
    final content = await fs.readString(path);
    if (content == null || content.trim().isEmpty) return null;
    return CredentialFile(
      relativePath: '${provider.id}/${CodexAuthArtifacts.authFileName}',
      content: content,
    );
  }
}
