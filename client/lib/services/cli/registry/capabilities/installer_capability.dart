import '../cli_capability.dart';

abstract interface class InstallerCapability implements CliCapability {
  bool get supportsInstaller;
}
