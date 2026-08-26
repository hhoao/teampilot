import 'dart:async';
import 'dart:io';

import 'package:flutter_pty_new/flutter_pty_new.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/services/terminal/local_pty_transport.dart';
import 'package:teampilot/services/terminal/terminal_session.dart';
import 'package:teampilot/services/terminal/terminal_transport.dart';

import 'integration_prerequisites.dart';
import 'cli_store_env.dart';

/// Boots a [TerminalSession] on a real local PTY for screen-probe integration tests.
abstract final class LocalPtyProbeHarness {
  static const needle = '和你的队员打个招呼吧';

  static String get shellExecutable {
    if (Platform.isWindows) {
      final root = Platform.environment['SystemRoot'] ?? r'C:\Windows';
      return p.join(root, 'System32', 'cmd.exe');
    }
    for (final candidate in ['/bin/bash', '/usr/bin/bash', '/bin/sh']) {
      if (File(candidate).existsSync()) return candidate;
    }
    return Platform.resolvedExecutable;
  }

  static List<String> get shellArguments {
    if (Platform.isWindows) {
      // Keep the PTY session alive — bare cmd.exe would exit immediately.
      return const ['/K', '@echo off'];
    }
    return const ['-i'];
  }

  static String get cjkEchoBytes {
    if (Platform.isWindows) {
      return 'chcp 65001 >nul\r\n'
          '${List.filled(18, '\r\n').join()}'
          'echo $needle\r\n';
    }
    return '${List.filled(18, '\r\n').join()}'
        'printf "%s\\n" "$needle"\r\n';
  }

  static String? resolvePythonPath() {
    final commands = Platform.isWindows
        ? const ['python', 'python3', 'py']
        : const ['python3', 'python'];
    for (final cmd in commands) {
      try {
        final result = Process.runSync(
          Platform.isWindows ? 'where' : 'which',
          [cmd],
        );
        if (result.exitCode != 0) continue;
        for (final raw in result.stdout.toString().split(RegExp(r'\r?\n'))) {
          final line = raw.trim();
          if (line.isEmpty) continue;
          if (File(line).existsSync()) return line;
          if (Platform.isWindows) {
            for (final suffix in ['.exe', '']) {
              final withSuffix = '$line$suffix';
              if (File(withSuffix).existsSync()) return withSuffix;
            }
          }
        }
      } on ProcessException {
        continue;
      }
    }
    if (Platform.isWindows) {
      try {
        final py = Process.runSync('py', [
          '-3',
          '-c',
          'import sys; print(sys.executable)',
        ]);
        if (py.exitCode == 0) {
          final line = py.stdout.toString().trim();
          if (line.isNotEmpty && File(line).existsSync()) return line;
        }
      } on ProcessException {
        return null;
      }
    }
    return null;
  }

  static String bracketedPasteFixturePath() {
    final candidates = [
      p.normalize(
        p.join('test', 'integration', 'fixtures', 'bracketed_paste_prompt.py'),
      ),
      p.normalize(
        p.join(
          Directory.current.path,
          'test',
          'integration',
          'fixtures',
          'bracketed_paste_prompt.py',
        ),
      ),
    ];
    for (final path in candidates) {
      if (File(path).existsSync()) return path;
    }
    return candidates.last;
  }

  static Future<TerminalTransport> _startBarePty(
    String executable,
    List<String> arguments, {
    required String workingDirectory,
    required int columns,
    required int rows,
    Map<String, String>? environment,
  }) async {
    final pty = Pty.start(
      executable,
      arguments: arguments,
      workingDirectory: workingDirectory,
      columns: columns,
      rows: rows,
      environment: environment,
    );
    return LocalPtyTransport(pty);
  }

  static Future<TerminalSession> connectShell({
    required String executable,
    List<String> arguments = const [],
    Duration confirmFallback = const Duration(seconds: 2),
    Map<String, String>? extraEnvironment,
    String? workingDirectory,
    int viewportColumns = 80,
    int viewportRows = 24,
  }) async {
    IntegrationPrerequisites.skipUnlessNativePty();
    // The bare PTY must launch with exactly the caller's arguments.
    // TerminalSession.connect() synthesizes CLI session args that
    // plain shells / fixtures reject — the closure param would shadow these in.
    final callerArguments = arguments;
    final session = TerminalSession(
      executable: executable,
      validateLaunch: false,
      parseExecutable: false,
      confirmFallback: confirmFallback,
      transportStarter:
          (
            _executable,
            {
            required List<String> arguments,
            required String workingDirectory,
            required int columns,
            required int rows,
            Map<String, String>? environment,
          }) {
            return _startBarePty(
              executable,
              callerArguments,
              workingDirectory: workingDirectory,
              columns: columns,
              rows: rows,
              // Probes must never inherit TeamPilot-injected CLI store
              // redirects: launched from an agent PTY they would boot the
              // real CLI against the live session store and corrupt it.
              environment: sanitizeCliStoreEnvironment(
                extraEnvironment ?? environment ?? const {},
              ),
            );
          },
    );
    session.connect(
      workingDirectory: workingDirectory ?? Directory.systemTemp.path,
    );
    session.onViewportResize(viewportColumns, viewportRows);
    await waitUntilConnected(session);
    return session;
  }

  static Future<TerminalSession> connectDefaultShell() {
    return connectShell(
      executable: shellExecutable,
      arguments: shellArguments,
    );
  }

  static Future<TerminalSession> connectBracketedPasteFixture() async {
    final python = resolvePythonPath();
    if (python == null) {
      markTestSkipped('python not on PATH (needed for bracketed-paste fixture)');
    }
    final script = p.absolute(bracketedPasteFixturePath());
    if (!File(script).existsSync()) {
      markTestSkipped('bracketed_paste_prompt.py fixture missing at $script');
    }

    if (Platform.isWindows) {
      // Direct Pty.start(python.exe, …) is flaky with some Windows venv layouts;
      // cmd /K matches how interactive shells are usually spawned.
      final quoted = script.contains(' ') ? '"$script"' : script;
      return connectShell(
        executable: shellExecutable,
        arguments: ['/K', '@echo off', '$python -u $quoted'],
      );
    }

    return connectShell(
      executable: python!,
      arguments: ['-u', script],
    );
  }

  static Future<void> waitUntilConnected(
    TerminalSession session, {
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (session.isConnected) {
        await session.probe.syncDisplayGrid();
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    throw StateError('TerminalSession did not reach connected state');
  }

  static Future<void> settleGrid(TerminalSession session) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await session.probe.syncDisplayGrid();
  }
}
