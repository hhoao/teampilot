import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/session_preferences.dart';
import 'package:teampilot/services/cli/git_installer.dart';
import 'package:teampilot/services/cli/registry/capabilities/remote_cli_locator_capability.dart';
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

  test('locateLocalTool finds node via which', () async {
    final discovery = ToolchainExecutableDiscovery(
      detectGit: () async => const GitInstallResult.notFound('skip'),
      processRunner: (executable, arguments, {stdoutEncoding, stderrEncoding}) async {
        if (arguments.isNotEmpty && arguments.first == 'node') {
          return ProcessResult(0, 0, '/usr/bin/node', '');
        }
        return ProcessResult(0, 1, '', '');
      },
    );
    final path = await discovery.locateLocalTool(
      SessionPreferences.toolchainNode,
    );
    expect(path, '/usr/bin/node');
  });

  test('locateLocalTool finds git via detectGit', () async {
    final discovery = ToolchainExecutableDiscovery(
      detectGit: () async => const GitInstallResult.found('/usr/bin/git'),
    );
    final path = await discovery.locateLocalTool(
      SessionPreferences.toolchainGit,
    );
    expect(path, '/usr/bin/git');
  });

  test('locateLocalTool returns null for unknown toolId', () async {
    final discovery = ToolchainExecutableDiscovery(
      detectGit: () async => const GitInstallResult.notFound('skip'),
    );
    expect(await discovery.locateLocalTool('unknown'), isNull);
  });

  test('locateRemoteTool finds git via DefaultRemoteCliLocator probe', () async {
    final discovery = ToolchainExecutableDiscovery(
      detectGit: () async => const GitInstallResult.notFound('skip'),
    );
    final path = await discovery.locateRemoteTool(
      toolId: SessionPreferences.toolchainGit,
      run: (command) async {
        expect(command, contains('git'));
        return const SshCommandResult(exitCode: 0, stdout: '/usr/bin/git\n');
      },
    );
    expect(path, '/usr/bin/git');
  });

  test('locateRemoteTool finds node via DefaultRemoteCliLocator probe', () async {
    final discovery = ToolchainExecutableDiscovery(
      detectGit: () async => const GitInstallResult.notFound('skip'),
    );
    final path = await discovery.locateRemoteTool(
      toolId: SessionPreferences.toolchainNode,
      run: (command) async {
        expect(command, contains('node'));
        return const SshCommandResult(exitCode: 0, stdout: '/usr/bin/node\n');
      },
    );
    expect(path, '/usr/bin/node');
  });

  test('locateRemoteTool returns null for unknown toolId', () async {
    final discovery = ToolchainExecutableDiscovery(
      detectGit: () async => const GitInstallResult.notFound('skip'),
    );
    expect(
      await discovery.locateRemoteTool(toolId: 'unknown', run: (_) async {
        fail('must not run');
      }),
      isNull,
    );
  });

  test('locateRemoteTool returns null when remote probe empty', () async {
    final discovery = ToolchainExecutableDiscovery(
      detectGit: () async => const GitInstallResult.notFound('skip'),
    );
    final path = await discovery.locateRemoteTool(
      toolId: SessionPreferences.toolchainGit,
      run: (_) async => const SshCommandResult(exitCode: 1, stdout: ''),
    );
    expect(path, isNull);
  });
}
