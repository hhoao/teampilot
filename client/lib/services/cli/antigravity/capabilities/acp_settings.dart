import 'dart:io';

import '../../registry/capabilities/acp_settings_capability.dart';
import '../../registry/installer/acp_adapter_installer.dart';

final class AntigravityAcpSettings implements AcpSettingsCapability {
  const AntigravityAcpSettings({this.installer});

  final AcpAdapterInstaller? installer;

  @override
  bool get usesSeparateAdapter => true;

  @override
  String? get adapterExecutableName =>
      Platform.isWindows ? 'agy_acp_server.exe' : 'agy_acp_server.par';

  @override
  AcpAdapterInstaller? get adapterInstaller => installer;
}
