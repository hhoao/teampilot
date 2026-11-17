import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/services/cli/cli_installer_service.dart';
import 'package:teampilot/services/cli/registry/installer/acp_adapter_installer.dart';
import 'package:teampilot/services/cli/registry/installer/installer_context.dart';
import 'package:teampilot/services/ssh/ssh_client_factory.dart';
import 'package:teampilot/services/ssh/worker/ssh_worker_member_session.dart';
import 'package:teampilot/services/ssh/worker/ssh_worker_storage_types.dart';

const _profile = SshProfile(
  id: 'p1',
  name: 'box',
  host: 'example.com',
  port: 22,
  username: 'dev',
);

void main() {
  test('SSH adapter install opens and closes exactly one task channel', () async {
    final transport = _FakeMemberTransport();
    final factory = _FakeFactory(transport);
    final service = CliInstallerService(sshClientFactory: factory);

    final result = await service.installAdapter(
      installer: _FakeAdapter(),
      mode: CliInstallMode.ssh,
      sshProfile: _profile,
    );

    expect(result.success, isTrue);
    expect(result.executablePath, '/usr/local/bin/test-adapter');
    expect(transport.opened, 1);
    expect(transport.closed, 1);
    expect(transport.commands.single, contains('test-adapter'));
  });
}

final class _FakeAdapter implements AcpAdapterInstaller {
  @override
  String get adapterJobTarget => 'adapter:test';
  @override
  String get executableName => 'test-adapter';
  @override
  String get displayName => 'Test adapter';
  @override
  bool get supportsInstaller => true;
  @override
  Future<String?> resolveInstalledPath() async => null;
  @override
  Future<String?> latestVersion() async => null;

  @override
  Future<CliInstallResult> install(CliInstallContext context) async {
    final result = await context.host.runSsh(
      context.sshProfile!,
      CliInstallerCommand.unixShellScript(
        'echo /usr/local/bin/test-adapter',
      ),
    );
    return CliInstallResult(
      success: result.exitCode == 0,
      message: 'ok',
      executablePath: result.stdout.trim(),
    );
  }
}

final class _FakeFactory implements SshClientFactory {
  _FakeFactory(this.transport);
  final SshWorkerMemberTransport transport;

  @override
  Future<SshWorkerMemberTransport> openMemberTransport(
    SshProfile profile, {
    Duration timeout = const Duration(seconds: 10),
  }) async => transport;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

final class _FakeMemberTransport implements SshWorkerMemberTransport {
  var opened = 0;
  var closed = 0;
  final commands = <String>[];

  @override
  Future<void> open(
    SshProfile profile, {
    Duration timeout = const Duration(seconds: 10),
  }) async => opened++;

  @override
  Future<SshWorkerRunResult> run(String command, {bool stderr = true}) async {
    commands.add(command);
    return SshWorkerRunResult(
      stdout: Uint8List.fromList('/usr/local/bin/test-adapter\n'.codeUnits),
      stderr: Uint8List(0),
      exitCode: 0,
    );
  }

  @override
  Future<SshWorkerExecChannel> startProcess(String command) =>
      throw UnimplementedError();

  @override
  Future<SshWorkerPtyChannel> openPty({
    String? command,
    required int columns,
    required int rows,
    Map<String, String>? environment,
  }) => throw UnimplementedError();

  @override
  Future<void> close() async => closed++;
}
