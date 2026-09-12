import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/remote_cli_locator.dart';

/// Map-based fake: returns a configured result per exact command, else exit 1.
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

/// Runner that raises a dartssh2-style channel request error on every command,
/// as when the remote refuses `exec` requests.
class _ThrowingRun {
  final calls = <String>[];

  Future<SshCommandResult> call(String command) async {
    calls.add(command);
    throw Exception('SSHChannelRequestError(Failed to execute)');
  }
}

/// Runner that raises on commands in [raiseFor] and returns [byCommand] for
/// everything else, so one probe can fail while a later one succeeds.
class _FlakyRun {
  _FlakyRun(this.byCommand, this.raiseFor);
  final Map<String, SshCommandResult> byCommand;
  final Set<String> raiseFor;

  Future<SshCommandResult> call(String command) async {
    if (raiseFor.contains(command)) {
      throw Exception('SSHChannelRequestError(Failed to execute)');
    }
    return byCommand[command] ??
        const SshCommandResult(exitCode: 1, stdout: '');
  }
}

const _bins = {
  CliTool.claude: 'claude',
  CliTool.flashskyai: 'flashskyai',
  CliTool.codex: 'codex',
  CliTool.opencode: 'opencode',
  CliTool.cursor: 'cursor-agent',
};

void main() {
  final locator = RemoteCliLocator();

  test('locates each of the 5 CLIs via its `command -v <bin>` probe', () async {
    for (final entry in _bins.entries) {
      final bin = entry.value;
      final run = _FakeRun({
        'command -v $bin': SshCommandResult(
          exitCode: 0,
          stdout: '/usr/bin/$bin\n',
        ),
      });
      final path = await locator.resolve(cli: entry.key, run: run.call);
      expect(path, '/usr/bin/$bin', reason: 'CLI ${entry.key}');
    }
  });

  test('falls back to a login shell when the direct probe misses', () async {
    final run = _FakeRun({
      "bash -ilc 'command -v claude'": const SshCommandResult(
        exitCode: 0,
        stdout: '/opt/claude\n',
      ),
    });
    final path = await locator.resolve(cli: CliTool.claude, run: run.call);
    expect(path, '/opt/claude');
    expect(run.calls.first, 'command -v claude'); // direct tried first
  });

  test('falls back to bash -lc when -ilc probes miss', () async {
    final run = _FakeRun({
      "bash -lc 'command -v claude'": const SshCommandResult(
        exitCode: 0,
        stdout: '/opt/claude\n',
      ),
    });
    final path = await locator.resolve(cli: CliTool.claude, run: run.call);
    expect(path, '/opt/claude');
  });

  test('falls back to ~/.local/bin when PATH probes miss', () async {
    final run = _FakeRun({
      "sh -c 'test -x \"\$HOME/.local/bin/claude\" && printf \"%s\\n\" \"\$HOME/.local/bin/claude\"'":
          const SshCommandResult(
            exitCode: 0,
            stdout: '/home/testuser/.local/bin/claude\n',
          ),
    });
    final path = await locator.resolve(cli: CliTool.claude, run: run.call);
    expect(path, '/home/testuser/.local/bin/claude');
  });

  test('manual override wins without probing', () async {
    final run = _FakeRun({});
    final path = await locator.resolve(
      cli: CliTool.claude,
      run: run.call,
      manualPathOverride: '/custom/claude',
    );
    expect(path, '/custom/claude');
    expect(run.calls, isEmpty);
  });

  test('returns null when every probe fails', () async {
    final run = _FakeRun({});
    expect(await locator.resolve(cli: CliTool.codex, run: run.call), isNull);
  });

  test('returns null without rethrowing when probes raise exec errors',
      () async {
    final run = _ThrowingRun();
    expect(await locator.resolve(cli: CliTool.claude, run: run.call), isNull);
    expect(run.calls, isNotEmpty); // all probes were attempted
  });

  test('ignores an earlier probe error when a later probe succeeds', () async {
    final run = _FlakyRun(
      {
        "bash -ilc 'command -v claude'": const SshCommandResult(
          exitCode: 0,
          stdout: '/opt/claude\n',
        ),
      },
      {'command -v claude'},
    );
    final path = await locator.resolve(cli: CliTool.claude, run: run.call);
    expect(path, '/opt/claude');
  });
}
