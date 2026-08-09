import '../../../../models/app_provider_config.dart';
import '../../../io/filesystem.dart';
import '../../../provider/credential_binding.dart';
import '../../../remote/remote_credential_materializer.dart';
import '../../registry/capabilities/credential_export_capability.dart';
import '../provider/claude_provider_credentials_service.dart';

final class ClaudeCredentialExport implements CredentialExportCapability {
  const ClaudeCredentialExport();

  @override
  Future<CredentialFile?> exportCredential({
    required Filesystem fs,
    required String basePath,
    required String home,
    required AppProviderConfig provider,
  }) async {
    final binding = resolveCredentialBinding(provider);
    final svc = ClaudeProviderCredentialsService(
      fs: fs,
      basePath: basePath,
      resolveHomeDirectory: () => home,
    );
    final path = svc.effectiveCredentialPath(
      provider.id,
      binding: binding,
      homeDirectory: home,
    );
    final content = await fs.readString(path);
    if (content == null || content.trim().isEmpty) return null;
    return CredentialFile(
      relativePath:
          '${provider.id}/${ClaudeProviderCredentialsService.credentialsFileName}',
      content: content,
    );
  }
}
