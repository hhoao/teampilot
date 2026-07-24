import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/session_preferences.dart';
import 'package:teampilot/services/cli/git_installer.dart';
import 'package:teampilot/services/cli/toolchain_executable_discovery.dart';

void main() {
  test('locateLocal records git and node when both are found', () async {
    final discovery = ToolchainExecutableDiscovery(
      detectGit: () async => const GitInstallResult.found('/usr/bin/git'),
      processRunner: (executable, arguments, {stdoutEncoding, stderrEncoding}) async {
        if (arguments.isNotEmpty && arguments.first == 'node') {
          return ProcessResult(0, 0, '/usr/bin/node', '');
        }
        return ProcessResult(0, 1, '', '');
      },
    );

    final located = await discovery.locateLocal();

    expect(located[SessionPreferences.toolchainGit], '/usr/bin/git');
    expect(located[SessionPreferences.toolchainNode], '/usr/bin/node');
  });

  test('locateLocal omits tools that are not found', () async {
    final discovery = ToolchainExecutableDiscovery(
      detectGit: () async => const GitInstallResult.notFound('missing'),
      processRunner: (executable, arguments, {stdoutEncoding, stderrEncoding}) async {
        throw ProcessException('where', const [], 'not found', -1);
      },
    );

    final located = await discovery.locateLocal();

    expect(located, isEmpty);
  });
}
