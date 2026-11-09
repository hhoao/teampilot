import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/services/cli/installer_types.dart';
import 'package:teampilot/services/cli/registry/installer/installer_context.dart';
import 'package:teampilot/services/host/host_execution_environment.dart';
import 'package:teampilot/services/host/host_script_runner.dart';
import 'package:teampilot/services/storage/runtime_context.dart';

typedef FakeSshResponse =
    CliInstallerCommandResult Function(CliInstallerCommand command);

final class FakeCliInstallerHost implements CliInstallerHost {
  FakeCliInstallerHost({required this.sshResponses});

  final FakeSshResponse sshResponses;
  final sshCommands = <String>[];
  final reported = <CliInstallPhase>[];

  @override
  HostExecutionEnvironment get hostEnvironment =>
      HostExecutionEnvironment.resolve(
        isWindowsHost: false,
        storageMode: StorageBackendMode.native,
      );

  @override
  bool get isWindows => false;

  @override
  HostScriptRunner get scriptRunner => hostEnvironment.scriptRunner;

  @override
  void report(CliInstallPhase phase, {String? detail}) => reported.add(phase);

  @override
  Future<CliInstallerCommandResult> runLocal(
    CliInstallerCommand command, {
    required CliInstallPhase phase,
    bool streamOutput = false,
  }) async => const CliInstallerCommandResult(exitCode: 1);

  @override
  Future<CliInstallerCommandResult> runSsh(
    SshProfile profile,
    CliInstallerCommand command,
  ) async {
    sshCommands.add(command.commandLine);
    return sshResponses(command);
  }

  @override
  Future<String?> locateExecutable(String name) async => null;

  @override
  Future<String?> locateLocalNpm() async => null;

  @override
  Future<String?> locateRemoteNpm(SshProfile profile) async => null;

  @override
  bool get isCancelled => false;
}
