import '../../../../models/app_provider_config.dart';
import '../../../io/filesystem.dart';
import '../../../remote/remote_credential_materializer.dart';
import '../../registry/capabilities/credential_export_capability.dart';

final class NoCredentialExport implements CredentialExportCapability {
  const NoCredentialExport();

  @override
  Future<CredentialFile?> exportCredential({
    required Filesystem fs,
    required String basePath,
    required String home,
    required AppProviderConfig provider,
  }) async => null;
}
