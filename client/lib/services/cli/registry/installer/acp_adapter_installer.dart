import '../../installer_types.dart';
import 'installer_context.dart';

/// Neutral installer contract for a separate ACP adapter binary.
///
/// Adapters are not necessarily npm packages: Claude/Codex ship npm adapters
/// (see [NpmInstallerCapability]), while other CLIs ship a standalone binary
/// archive. Readiness UI and install jobs depend only on this contract so they
/// never need to know how an adapter is acquired.
abstract interface class AcpAdapterInstaller {
  /// Stable install-job target id, distinct from any `CliTool.value`.
  /// Claude/Codex keep their existing static `jobTarget` field.
  String get adapterJobTarget;
  String get executableName;
  String get displayName;
  bool get supportsInstaller;
  Future<String?> resolveInstalledPath();
  Future<String?> latestVersion();
  Future<CliInstallResult> install(CliInstallContext context);
}
