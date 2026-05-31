import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/host/host_execution_environment.dart';
import 'package:teampilot/services/host/host_script_runner.dart';
import 'package:teampilot/services/storage/runtime_storage_context.dart';

void main() {
  test('commandStringForScriptFile uses bash or powershell', () {
    final bashRunner = HostExecutionEnvironment.resolve(
      isWindowsHost: false,
      storageMode: StorageBackendMode.native,
    ).scriptRunner;
    expect(
      bashRunner.commandStringForScriptFile('/tmp/hooks/foo.sh'),
      'bash "/tmp/hooks/foo.sh"',
    );

    final psRunner = HostExecutionEnvironment.resolve(
      isWindowsHost: true,
      storageMode: StorageBackendMode.native,
    ).scriptRunner;
    expect(
      psRunner.commandStringForScriptFile(r'C:\hooks\foo.ps1'),
      r'powershell -NoProfile -ExecutionPolicy Bypass -File "C:\hooks\foo.ps1"',
    );
  });

  test('hookFileName adds extension', () {
    final runner = HostScriptRunner(
      HostExecutionEnvironment.resolve(
        isWindowsHost: true,
        storageMode: StorageBackendMode.native,
      ),
    );
    expect(runner.hookFileName('rtk-rewrite'), 'rtk-rewrite.ps1');
  });

  test('installerCommandForInline', () {
    final bashRunner = HostExecutionEnvironment.resolve(
      isWindowsHost: false,
      storageMode: StorageBackendMode.native,
    ).scriptRunner;
    final cmd = bashRunner.installerCommandForInline('echo hi');
    expect(cmd.executable, 'sh');
    expect(cmd.arguments, ['-c', 'echo hi']);
  });
}
