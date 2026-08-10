import '../../../../models/app_provider_config.dart';
import '../../../io/filesystem.dart';
import '../../../remote/remote_credential_materializer.dart';
import '../cli_capability.dart';

/// Exports a local credential file for remote push.
///
/// Replaces the `switch(cli)` in [LocalCredentialExporter._exportCredential].
/// Returns `null` when the CLI has no credential export (flashskyai) or when
/// the credential file does not exist.
abstract interface class CredentialExportCapability implements CliCapability {
  Future<CredentialFile?> exportCredential({
    required Filesystem fs,
    required String basePath,
    required String home,
    required AppProviderConfig provider,
  });
}
