import 'connection_mode.dart';

class LaunchTarget {
  const LaunchTarget.local({
    required this.executable,
    this.workingDirectory = '',
    this.environment = const {},
  }) : connectionMode = ConnectionMode.localPty,
       sshProfileId = '',
       remoteExecutable = '',
       remoteWorkingDirectory = '',
       remoteEnvironment = const {},
       useLoginShell = false;

  const LaunchTarget.ssh({
    required this.sshProfileId,
    required this.remoteExecutable,
    this.remoteWorkingDirectory = '',
    this.remoteEnvironment = const {},
    this.useLoginShell = false,
  }) : connectionMode = ConnectionMode.ssh,
       executable = '',
       workingDirectory = '',
       environment = const {};

  final ConnectionMode connectionMode;

  // local PTY
  final String executable;
  final String workingDirectory;
  final Map<String, String> environment;

  // SSH
  final String sshProfileId;
  final String remoteExecutable;
  final String remoteWorkingDirectory;
  final Map<String, String> remoteEnvironment;
  final bool useLoginShell;
}
