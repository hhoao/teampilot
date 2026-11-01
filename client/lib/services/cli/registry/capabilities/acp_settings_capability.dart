import '../installer/npm_installer_capability.dart';
import '../cli_capability.dart';

abstract interface class AcpSettingsCapability implements CliCapability {
  bool get usesSeparateAdapter;
  String? get adapterExecutableName;
  NpmInstallerCapability? get adapterInstaller;
}

final class DefaultAcpSettingsCapability implements AcpSettingsCapability {
  const DefaultAcpSettingsCapability({
    this.usesSeparateAdapter = false,
    this.adapterExecutableName,
    this.adapterInstaller,
  });

  @override
  final bool usesSeparateAdapter;
  @override
  final String? adapterExecutableName;
  @override
  final NpmInstallerCapability? adapterInstaller;
}
