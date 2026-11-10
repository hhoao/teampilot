import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/qoder/capabilities/executable_cn.dart';
import 'package:teampilot/services/cli/registry/capabilities/cli_executable_capability.dart';

void main() {
  test('CN executable identity and installer availability', () {
    const cap = QoderCnExecutableCapability();

    expect(cap.defaultExecutableName, 'qoderclicn');
    expect(cap.preferencesPathKey, 'qoder-cn');
    expect(cap.supportsInstaller, !Platform.isWindows);
    expect(
      QoderCnExecutableCapability.installScript,
      'curl -fsSL https://qoder.com.cn/install | bash',
    );
  });

  test('remote locate probes qoderclicn', () async {
    var command = '';
    final path = await const QoderCnExecutableCapability().locateRemote((
      value,
    ) async {
      command = value;
      return const SshCommandResult(
        exitCode: 0,
        stdout: '/usr/local/bin/qoderclicn\n',
      );
    });

    expect(command, contains('qoderclicn'));
    expect(path, '/usr/local/bin/qoderclicn');
  });
}
