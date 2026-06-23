import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/host/host_execution_environment.dart';
import 'package:teampilot/services/host/host_script_dialect.dart';
import 'package:teampilot/services/storage/runtime_context.dart';

void main() {
  test('linux native → bash', () {
    final env = HostExecutionEnvironment.resolve(
      isWindowsHost: false,
      storageMode: StorageBackendMode.native,
    );
    expect(env.dialect, HostScriptDialect.bash);
  });

  test('windows native storage → powershell', () {
    final env = HostExecutionEnvironment.resolve(
      isWindowsHost: true,
      storageMode: StorageBackendMode.native,
    );
    expect(env.dialect, HostScriptDialect.powershell);
  });

  test('windows wsl storage → bash', () {
    final env = HostExecutionEnvironment.resolve(
      isWindowsHost: true,
      storageMode: StorageBackendMode.wsl,
    );
    expect(env.dialect, HostScriptDialect.bash);
  });

  test('ssh storage → bash', () {
    final env = HostExecutionEnvironment.resolve(
      isWindowsHost: true,
      storageMode: StorageBackendMode.ssh,
      forceRemoteUnix: true,
    );
    expect(env.dialect, HostScriptDialect.bash);
  });

  test('forceRemoteUnix → bash on windows native', () {
    final env = HostExecutionEnvironment.resolve(
      isWindowsHost: true,
      storageMode: StorageBackendMode.native,
      forceRemoteUnix: true,
    );
    expect(env.dialect, HostScriptDialect.bash);
  });
}
