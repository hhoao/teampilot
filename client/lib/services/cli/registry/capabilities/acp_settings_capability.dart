import '../installer/npm_installer_capability.dart';
import '../cli_capability.dart';

abstract interface class AcpSettingsCapability implements CliCapability {
  bool get usesSeparateAdapter;
  String? get adapterExecutableName;
  NpmInstallerCapability? get adapterInstaller;
  bool get showsPersonalAcpSwitch;
}

final class DefaultAcpSettingsCapability implements AcpSettingsCapability {
  const DefaultAcpSettingsCapability({
    this.usesSeparateAdapter = false,
    this.adapterExecutableName,
    this.adapterInstaller,
    this.showsPersonalAcpSwitch = true,
  });

  @override
  final bool usesSeparateAdapter;
  @override
  final String? adapterExecutableName;
  @override
  final NpmInstallerCapability? adapterInstaller;
  @override
  final bool showsPersonalAcpSwitch;
}
