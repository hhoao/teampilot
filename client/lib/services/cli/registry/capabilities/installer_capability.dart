import '../../installer_types.dart';
import '../installer/installer_context.dart';
import '../cli_capability.dart';

abstract interface class InstallerCapability implements CliCapability {
  bool get supportsInstaller;

  Future<CliInstallResult> install(CliInstallContext context);
}
