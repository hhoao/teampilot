import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/host/host_executable_locator.dart';
import 'package:teampilot/services/host/host_execution_environment.dart';
import 'package:teampilot/services/storage/runtime_storage_context.dart';

void main() {
  test('whichCommand follows host environment', () {
    final windows = HostExecutableLocator(
      HostExecutionEnvironment.resolve(
        isWindowsHost: true,
        storageMode: StorageBackendMode.native,
      ),
    );
    expect(windows.whichCommand, 'where');

    final unix = HostExecutableLocator(
      HostExecutionEnvironment.resolve(
        isWindowsHost: false,
        storageMode: StorageBackendMode.native,
      ),
    );
    expect(unix.whichCommand, 'which');
  });

  test('parsePathLookupOutput prefers exe on Windows', () {
    const stdout =
        '/usr/bin/foo\nC:\\Tools\\claude.cmd\nC:\\Tools\\claude\n';
    expect(
      HostExecutableLocator.parsePathLookupOutput(stdout, isWindows: true),
      r'C:\Tools\claude.cmd',
    );
    expect(
      HostExecutableLocator.parsePathLookupOutput('/usr/bin/foo\n', isWindows: false),
      '/usr/bin/foo',
    );
  });
}
