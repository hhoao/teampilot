import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/host/host_execution_environment.dart';
import 'package:teampilot/services/host/script_file_hook_provisioner.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/storage/runtime_context.dart';

void main() {
  test('provision writes ps1 and command uses powershell on windows native', () async {
    final base = await Directory.systemTemp.createTemp('tp-hook-');
    addTearDown(() => base.deleteSync(recursive: true));

    final env = HostExecutionEnvironment.resolve(
      isWindowsHost: true,
      storageMode: StorageBackendMode.native,
    );
    final provisioner = ScriptFileHookProvisioner(
      fs: LocalFilesystem(),
      runner: env.scriptRunner,
      baseFileName: 'test-hook',
      loadScript: (_) async => '# test',
    );

    final path = await provisioner.provision(base.path);
    expect(path, contains('hooks'));
    expect(path, endsWith('test-hook.ps1'));
    expect(
      provisioner.commandForPath(path),
      contains('powershell'),
    );
  });
}
