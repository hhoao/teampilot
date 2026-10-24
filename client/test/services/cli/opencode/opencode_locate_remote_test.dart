import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/opencode/capabilities/executable.dart';
import 'package:teampilot/services/cli/opencode/opencode_bin.dart';
import 'package:teampilot/services/cli/registry/capabilities/cli_executable_capability.dart';

/// Mirrors the production `--version` probe format. Kept literal on purpose so
/// a format change in the implementation fails these tests.
String _versionCmd(String path) =>
    "sh -c 'test -x \"$path\" && \"$path\" --version'";

void main() {
  const capability = OpencodeExecutableCapability();

  SshCommandRunner runner(Map<String, SshCommandResult> byCommand) {
    return (command) async =>
        byCommand[command] ?? const SshCommandResult(exitCode: 1, stdout: '');
  }

  SshCommandResult ok(String stdout) =>
      SshCommandResult(exitCode: 0, stdout: '$stdout\n');

  test('locateRemote returns the official v2 bin when it reports a v2 banner',
      () async {
    const path = '/home/alice/.opencode/bin/opencode';
    final located = await capability.locateRemote(
      runner({
        opencodeOfficialRemoteBinProbe: ok(path),
        _versionCmd(path): ok('2.0.24'),
        'command -v opencode': ok('/home/alice/.local/bin/opencode'),
      }),
    );
    expect(located, path);
  });

  test('locateRemote rejects a v1-only remote so the panel offers v2 install',
      () async {
    const path = '/home/alice/.local/bin/opencode';
    final located = await capability.locateRemote(
      runner({
        'command -v opencode': ok(path),
        _versionCmd(path): ok('1.18.4'),
      }),
    );
    expect(located, isNull);
  });

  test('locateRemote keeps the path when the version banner is unreadable',
      () async {
    const path = '/opt/opencode';
    final located = await capability.locateRemote(
      runner({'command -v opencode': ok(path)}),
    );
    expect(located, path);
  });
}
