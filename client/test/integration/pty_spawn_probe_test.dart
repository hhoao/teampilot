@Tags(['integration'])
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_pty/flutter_pty.dart';
import 'package:teampilot/services/terminal/terminal_session.dart';

/// Fixed ConPTY probes. Compare with TeamPilot app spawn (uses [TerminalSession.buildPtyEnvironment]).
///
/// Run (after `flutter build windows --debug`):
///   $env:PATH = "$PWD\build\windows\x64\runner\Debug;" + $env:PATH
///   flutter test test/integration/pty_spawn_probe_test.dart --name "profile B"
abstract final class PtySpawnFixtures {
  static const workingDirectory = r'C:\Users\haung\Documents';

  static const smokeExecutable = 'cmd';
  static const smokeArguments = ['/c', 'echo TEAMPILOT_PTY_SMOKE_OK'];

  static const shortExecutable = 'claude';
  static const claudeArguments = <String>[];

  static String? resolveClaudeAbsolutePath() {
    if (!Platform.isWindows) return null;
    try {
      final result = Process.runSync('where', ['claude']);
      if (result.exitCode != 0) return null;
      for (final raw in result.stdout.toString().split(RegExp(r'\r?\n'))) {
        final line = raw.trim();
        if (line.isEmpty) continue;
        final resolved = _resolveWindowsExecutablePath(line);
        if (resolved != null) return resolved;
      }
    } on ProcessException {
      return null;
    }
    return null;
  }

  static String? _resolveWindowsExecutablePath(String candidate) {
    for (final suffix in ['.cmd', '.exe', '.bat']) {
      final withSuffix = '$candidate$suffix';
      if (File(withSuffix).existsSync()) return withSuffix;
    }
    final lower = candidate.toLowerCase();
    if (File(candidate).existsSync() &&
        (lower.endsWith('.exe') ||
            lower.endsWith('.cmd') ||
            lower.endsWith('.bat'))) {
      return candidate;
    }
    return null;
  }
}

String? _requireClaudeExecutable() {
  final absolute = PtySpawnFixtures.resolveClaudeAbsolutePath();
  if (absolute == null) {
    markTestSkipped('claude not found on PATH');
  }
  return absolute;
}

final _nativePtyAvailable = _detectNativePty();

bool _detectNativePty() {
  if (Platform.isLinux) {
    try {
      DynamicLibrary.open('libflutter_pty.so');
      return true;
    } catch (_) {
      return false;
    }
  }
  if (Platform.isWindows) {
    for (final path in [
      'flutter_pty.dll',
      r'build\windows\x64\debug\flutter_pty.dll',
      r'build\windows\x64\runner\Debug\flutter_pty.dll',
    ]) {
      try {
        DynamicLibrary.open(path);
        return true;
      } catch (_) {}
    }
  }
  return false;
}

const _skipWithoutNativePty =
    'Requires flutter_pty native library (run `flutter build windows` first on Windows)';

String _formatExitCode(int code) {
  final unsigned = code & 0xFFFFFFFF;
  return '$code (0x${unsigned.toRadixString(16)})';
}

Future<String> _collectPtyOutput(
  Pty pty, {
  Duration listenFor = const Duration(seconds: 8),
}) async {
  final chunks = <String>[];
  final sub = pty.output.listen((data) {
    chunks.add(utf8.decode(data, allowMalformed: true));
  });
  await Future<void>.delayed(listenFor);
  await sub.cancel();
  return chunks.join();
}

Future<void> _runProbe({
  required String label,
  required String executable,
  required List<String> arguments,
  Duration listenFor = const Duration(seconds: 8),
  bool expectProcess = true,
  Map<String, String>? environment,
}) async {
  final cwd = Directory(PtySpawnFixtures.workingDirectory);
  if (!cwd.existsSync()) {
    markTestSkipped(
      'Working directory missing: ${PtySpawnFixtures.workingDirectory}',
    );
  }

  // ignore: avoid_print
  print('\n========== PTY PROBE: $label ==========');
  // ignore: avoid_print
  print('Executable: $executable');
  // ignore: avoid_print
  print(
    'Arguments: ${arguments.isEmpty ? '(none)' : arguments.join(' ')}',
  );
  // ignore: avoid_print
  print('WorkingDirectory: ${PtySpawnFixtures.workingDirectory}');
  // ignore: avoid_print
  print(
    'Environment keys: ${environment?.length ?? 0} '
    '(flutter_pty default if 0; TeamPilot merges full Platform.environment)',
  );
  // ignore: avoid_print
  print('Platform.environment keys in test runner: ${Platform.environment.length}');
  // ignore: avoid_print
  print(
    'ConPTY command line (approx): $executable${arguments.isEmpty ? '' : ' ${arguments.join(' ')}'}',
  );

  Pty? pty;
  try {
    pty = Pty.start(
      executable,
      arguments: arguments,
      workingDirectory: PtySpawnFixtures.workingDirectory,
      columns: 120,
      rows: 30,
      environment: environment,
    );
  } on Object catch (error) {
    // ignore: avoid_print
    print('Pty.start failed: $error');
    if (expectProcess) rethrow;
    return;
  }

  // ignore: avoid_print
  print('PID: ${pty.pid}');

  final output = await _collectPtyOutput(pty, listenFor: listenFor);
  // ignore: avoid_print
  print('--- PTY stdout (${output.length} chars) ---');
  // ignore: avoid_print
  print(output.isEmpty ? '(empty)' : output);
  // ignore: avoid_print
  print('--- end stdout ---');

  final exitCode = await pty.exitCode.timeout(
    const Duration(seconds: 3),
    onTimeout: () {
      pty!.kill();
      return -1;
    },
  );
  // ignore: avoid_print
  print('Exit code: ${_formatExitCode(exitCode)}');
  if (exitCode == 3221226505) {
    // ignore: avoid_print
    print(
      'Hint: 0xC0000409 = process crashed on startup. '
      'Common in flutter test when env is sparse — use teamPilotEnvironment profile.',
    );
  }
  _printExecutableEchoHint(output);
  // ignore: avoid_print
  print('========== end probe ==========\n');
}

Future<void> _runProcessProbe({
  required String label,
  required String executable,
  required List<String> arguments,
  Duration listenFor = const Duration(seconds: 15),
  Map<String, String>? environment,
  bool runInShell = false,
}) async {
  final cwd = Directory(PtySpawnFixtures.workingDirectory);
  if (!cwd.existsSync()) {
    markTestSkipped(
      'Working directory missing: ${PtySpawnFixtures.workingDirectory}',
    );
  }

  // ignore: avoid_print
  print('\n========== PROCESS PROBE: $label ==========');
  // ignore: avoid_print
  print('Executable: $executable');
  // ignore: avoid_print
  print(
    'Arguments: ${arguments.isEmpty ? '(none)' : arguments.join(' ')}',
  );
  // ignore: avoid_print
  print('WorkingDirectory: ${PtySpawnFixtures.workingDirectory}');
  // ignore: avoid_print
  print('runInShell: $runInShell');
  // ignore: avoid_print
  print(
    'Environment keys: ${environment?.length ?? 'inherit Platform.environment'}',
  );
  // ignore: avoid_print
  print(
    'Note: uses Process.start (pipe stdout, no PTY). '
    'Process.run would block on interactive TUI.',
  );

  Process? process;
  try {
    process = await Process.start(
      executable,
      arguments,
      workingDirectory: PtySpawnFixtures.workingDirectory,
      environment: environment,
      runInShell: runInShell,
    );
  } on Object catch (error) {
    // ignore: avoid_print
    print('Process.start failed: $error');
    rethrow;
  }

  // ignore: avoid_print
  print('PID: ${process.pid}');

  final chunks = <String>[];
  final sub = process.stdout
      .transform(utf8.decoder)
      .listen((chunk) => chunks.add(chunk));
  final errSub = process.stderr
      .transform(utf8.decoder)
      .listen((chunk) => chunks.add(chunk));

  await Future<void>.delayed(listenFor);

  final output = chunks.join();
  await sub.cancel();
  await errSub.cancel();

  process.kill();
  final exitCode = await process.exitCode.timeout(
    const Duration(seconds: 3),
    onTimeout: () => -1,
  );

  // ignore: avoid_print
  print('--- Process stdout+stderr (${output.length} chars) ---');
  // ignore: avoid_print
  print(output.isEmpty ? '(empty)' : output);
  // ignore: avoid_print
  print('--- end output ---');
  // ignore: avoid_print
  print('Exit code: ${_formatExitCode(exitCode)}');
  _printExecutableEchoHint(output);
  // ignore: avoid_print
  print('========== end process probe ==========\n');
}

void _printExecutableEchoHint(String output) {
  final short = PtySpawnFixtures.shortExecutable;
  final absolute = PtySpawnFixtures.resolveClaudeAbsolutePath();
  final patterns = <String>[short, if (absolute != null) absolute];
  for (final pattern in patterns) {
    if (output.contains('> $pattern') || output.contains('> $pattern\r')) {
      // ignore: avoid_print
      print('Hint: output contains pseudo-prompt "> $pattern"');
    }
  }
}

void main() {
  test(
    'profile 0 — baseline Process.run claude --version (no PTY)',
    () async {
      if (!Platform.isWindows) return;
      final claude = _requireClaudeExecutable();
      // ignore: avoid_print
      print('\n--- baseline: Process.run claude --version ---');
      // ignore: avoid_print
      print('Platform.environment keys: ${Platform.environment.length}');
      final result = await Process.run(claude!, ['--version']);
      // ignore: avoid_print
      print('exit=${result.exitCode} stdout=${result.stdout} stderr=${result.stderr}');
      expect(result.exitCode, 0);
    },
    skip: _nativePtyAvailable ? false : _skipWithoutNativePty,
  );

  test(
    'profile A — cmd echo smoke',
    () async {
      if (!Platform.isWindows) return;
      await _runProbe(
        label: 'A cmd smoke',
        executable: PtySpawnFixtures.smokeExecutable,
        arguments: PtySpawnFixtures.smokeArguments,
        listenFor: const Duration(seconds: 2),
      );
    },
    skip: _nativePtyAvailable ? false : _skipWithoutNativePty,
  );

  test(
    'profile A2 — cmd echo preserves spaced argument via ConPTY quoting',
    () async {
      if (!Platform.isWindows) return;
      const spaced = 'TEAMPILOT_SPACE_OK=Default Team';
      await _runProbe(
        label: 'A2 cmd spaced arg',
        executable: PtySpawnFixtures.smokeExecutable,
        arguments: const [
          '/c',
          'echo',
          spaced,
        ],
        listenFor: const Duration(seconds: 2),
      );
    },
    skip: _nativePtyAvailable ? false : _skipWithoutNativePty,
  );

  test(
    'profile B — claude short name (flutter_pty default env)',
    () async {
      if (!Platform.isWindows) return;
      await _runProbe(
        label: 'B claude / default sparse env',
        executable: PtySpawnFixtures.shortExecutable,
        arguments: PtySpawnFixtures.claudeArguments,
        listenFor: const Duration(seconds: 10),
        expectProcess: false,
      );
    },
    skip: _nativePtyAvailable ? false : _skipWithoutNativePty,
  );

  test(
    'profile B2 — claude short name (TeamPilot full env)',
    () async {
      if (!Platform.isWindows) return;
      final claude = _requireClaudeExecutable();
      await _runProbe(
        label: 'B2 claude / TeamPilot buildPtyEnvironment',
        executable: claude!,
        arguments: PtySpawnFixtures.claudeArguments,
        environment: TerminalSession.buildPtyEnvironment(null),
        listenFor: const Duration(seconds: 15),
      );
    },
    skip: _nativePtyAvailable ? false : _skipWithoutNativePty,
  );

  test(
    'profile C — claude absolute path (TeamPilot full env)',
    () async {
      if (!Platform.isWindows) return;
      final absolute = _requireClaudeExecutable();
      await _runProbe(
        label: 'C claude.exe / TeamPilot env',
        executable: absolute!,
        arguments: PtySpawnFixtures.claudeArguments,
        environment: TerminalSession.buildPtyEnvironment(null),
        listenFor: const Duration(seconds: 15),
      );
    },
    skip: _nativePtyAvailable ? false : _skipWithoutNativePty,
  );

  test(
    'profile D — claude via cmd PTY (non-interactive --version)',
    () async {
      if (!Platform.isWindows) return;
      await _runProbe(
        label: 'D cmd /c claude --version',
        executable: 'cmd',
        arguments: ['/c', 'claude', '--version'],
        environment: TerminalSession.buildPtyEnvironment(null),
        listenFor: const Duration(seconds: 5),
      );
    },
    skip: _nativePtyAvailable ? false : _skipWithoutNativePty,
  );

  test(
    'profile E — cmd /c claude bare via PTY (shell-wrapped, like manual terminal)',
    () async {
      if (!Platform.isWindows) return;
      await _runProbe(
        label: 'E cmd /c claude / TeamPilot env',
        executable: 'cmd',
        arguments: ['/c', PtySpawnFixtures.shortExecutable],
        environment: TerminalSession.buildPtyEnvironment(null),
        listenFor: const Duration(seconds: 15),
      );
    },
    skip: _nativePtyAvailable ? false : _skipWithoutNativePty,
  );

  test(
    'profile P — claude bare via Process.start (pipe, no PTY)',
    () async {
      if (!Platform.isWindows) return;
      final claude = _requireClaudeExecutable();
      await _runProcessProbe(
        label: 'P Process.start claude / TeamPilot env',
        executable: claude!,
        arguments: PtySpawnFixtures.claudeArguments,
        environment: TerminalSession.buildPtyEnvironment(null),
        listenFor: const Duration(seconds: 15),
      );
    },
  );

  test(
    'profile P2 — cmd /c claude via Process.start (pipe, no PTY)',
    () async {
      if (!Platform.isWindows) return;
      await _runProcessProbe(
        label: 'P2 Process.start cmd /c claude / TeamPilot env',
        executable: 'cmd',
        arguments: ['/c', PtySpawnFixtures.shortExecutable],
        environment: TerminalSession.buildPtyEnvironment(null),
        listenFor: const Duration(seconds: 15),
      );
    },
  );

  test(
    'profile R — Process.run cmd /c claude --version (no PTY)',
    () async {
      if (!Platform.isWindows) return;
      // ignore: avoid_print
      print('\n========== PROCESS PROBE: R Process.run cmd /c claude --version ==========');
      final result = await Process.run(
        'cmd',
        ['/c', PtySpawnFixtures.shortExecutable, '--version'],
        workingDirectory: PtySpawnFixtures.workingDirectory,
        environment: TerminalSession.buildPtyEnvironment(null),
      );
      final stdout = result.stdout.toString();
      final stderr = result.stderr.toString();
      // ignore: avoid_print
      print('exit=${result.exitCode}');
      // ignore: avoid_print
      print('stdout=$stdout');
      // ignore: avoid_print
      print('stderr=$stderr');
      _printExecutableEchoHint('$stdout$stderr');
      // ignore: avoid_print
      print('========== end process probe ==========\n');
      expect(result.exitCode, 0);
    },
  );

  test(
    'profile R2 — Process.run claude bare (pipe, no TTY — exits without TUI)',
    () async {
      if (!Platform.isWindows) return;
      final claude = _requireClaudeExecutable();
      // ignore: avoid_print
      print('\n========== PROCESS PROBE: R2 Process.run claude bare ==========');
      // ignore: avoid_print
      print(
        'No PTY: claude detects non-TTY pipe and falls back to --print mode, '
        'then exits (does not hang).',
      );
      final result = await Process.run(
        claude!,
        PtySpawnFixtures.claudeArguments,
        workingDirectory: PtySpawnFixtures.workingDirectory,
        environment: TerminalSession.buildPtyEnvironment(null),
      );
      final combined =
          '${result.stdout}${result.stderr}';
      // ignore: avoid_print
      print('exit=${result.exitCode}');
      // ignore: avoid_print
      print('output=$combined');
      _printExecutableEchoHint(combined);
      // ignore: avoid_print
      print('========== end process probe ==========\n');
      expect(result.exitCode, isNot(0));
      expect(combined, contains('--print'));
    },
  );
}
