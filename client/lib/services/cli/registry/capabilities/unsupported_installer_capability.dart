import '../../installer_types.dart';
import '../installer/installer_context.dart';
import 'installer_capability.dart';

final class UnsupportedInstallerCapability implements InstallerCapability {
  const UnsupportedInstallerCapability();

  @override
  bool get supportsInstaller => false;

  @override
  Future<CliInstallResult> install(CliInstallContext context) async {
    return const CliInstallResult(
      success: false,
      message: 'In-app installation is not supported for this CLI.',
    );
  }
}
