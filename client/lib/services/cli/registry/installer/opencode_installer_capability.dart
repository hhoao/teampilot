import 'npm_installer_capability.dart';

/// In-app npm installer for OpenCode CLI (`opencode-ai`).
final class OpencodeInstallerCapability extends NpmInstallerCapability {
  const OpencodeInstallerCapability();

  @override
  String get npmPackage => 'opencode-ai';

  @override
  String get executableName => 'opencode';

  @override
  String get displayName => 'OpenCode';
}
