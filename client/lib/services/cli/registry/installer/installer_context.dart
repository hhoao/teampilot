import '../../../../models/ssh_profile.dart';
import '../../installer_types.dart';
import 'teampilot_node_install.dart';

/// Runtime facade for [InstallerCapability] implementations.
abstract interface class CliInstallerHost {
  bool get isWindows;

  void report(CliInstallPhase phase, {String? detail});

  Future<CliInstallerCommandResult> runLocal(
    CliInstallerCommand command, {
    required CliInstallPhase phase,
    bool streamOutput = false,
  });

  Future<CliInstallerCommandResult> runSsh(
    SshProfile profile,
    CliInstallerCommand command,
  );

  Future<String?> locateExecutable(String name);

  Future<String?> locateLocalNpm();

  Future<String?> locateRemoteNpm(SshProfile profile);
}

class CliInstallContext {
  const CliInstallContext({
    required this.mode,
    required this.host,
    this.sshProfile,
    this.node = TeampilotNodeInstall.standard,
  });

  final CliInstallMode mode;
  final CliInstallerHost host;
  final SshProfile? sshProfile;

  /// Shared Node/npm bootstrap (version, scripts, resolve-or-bootstrap).
  final TeampilotNodeInstall node;
}
