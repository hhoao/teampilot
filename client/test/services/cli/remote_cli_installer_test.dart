import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/registry/capabilities/remote_cli_locator_capability.dart';
import 'package:teampilot/services/cli/remote_cli_installer.dart';

/// Mutable fake: the (fake) install can extend [byCommand] so the post-install
/// re-locate succeeds.
class _FakeRun {
  _FakeRun(this.byCommand);
  final Map<String, SshCommandResult> byCommand;
  final calls = <String>[];
  Future<SshCommandResult> call(String command) async {
    calls.add(command);
    return byCommand[command] ??
        const SshCommandResult(exitCode: 1, stdout: '');
  }
}

void main() {
  final installer = RemoteCliInstaller();

  test('already installed → returns located path, no install attempted',
      () async {
    final run = _FakeRun({
      'command -v claude':
          const SshCommandResult(exitCode: 0, stdout: '/usr/bin/claude\n'),
    });
    var installed = false;
    final path = await installer.ensure(
      cli: CliTool.claude,
      run: run.call,
      optIn: true,
      supportsInstaller: true,
      install: ({required run, required onProgress}) async {
        installed = true;
        return '';
      },
    );
    expect(path, '/usr/bin/claude');
    expect(installed, isFalse);
  });

  test('opt-in off + missing → error suggesting manual path', () async {
    final run = _FakeRun({});
    await expectLater(
      installer.ensure(
        cli: CliTool.claude,
        run: run.call,
        optIn: false,
        supportsInstaller: true,
      ),
      throwsA(isA<RemoteCliUnavailableException>().having(
        (e) => e.reason,
        'reason',
        RemoteCliUnavailableReason.optInOff,
      )),
    );
  });

  test('no installer capability → clear error', () async {
    final run = _FakeRun({});
    await expectLater(
      installer.ensure(
        cli: CliTool.cursor,
        run: run.call,
        optIn: true,
        supportsInstaller: false,
      ),
      throwsA(isA<RemoteCliUnavailableException>().having(
        (e) => e.reason,
        'reason',
        RemoteCliUnavailableReason.noInstaller,
      )),
    );
  });

  test('opt-in on + supportsInstaller → runs install and uses reported path',
      () async {
    final fakeRun = _FakeRun({});
    final progress = <String>[];
    final path = await installer.ensure(
      cli: CliTool.codex,
      run: fakeRun.call,
      optIn: true,
      supportsInstaller: true,
      onProgress: progress.add,
      install: ({required run, required onProgress}) async {
        onProgress('installing codex');
        return '/usr/local/bin/codex';
      },
    );
    expect(path, '/usr/local/bin/codex');
    expect(progress, contains('installing codex'));
  });

  test('install runs but reports no path → installFailed', () async {
    final run = _FakeRun({}); // stays missing even after install
    await expectLater(
      installer.ensure(
        cli: CliTool.codex,
        run: run.call,
        optIn: true,
        supportsInstaller: true,
        install: ({required run, required onProgress}) async {
          return '';
        },
      ),
      throwsA(isA<RemoteCliUnavailableException>().having(
        (e) => e.reason,
        'reason',
        RemoteCliUnavailableReason.installFailed,
      )),
    );
  });
}
