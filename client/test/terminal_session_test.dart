import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:teampilot/services/terminal_session.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakePtyHandle implements TerminalPtyHandle {
  final outputController = StreamController<Uint8List>();
  Completer<int> exitCompleter = Completer<int>();
  var killed = false;
  final resizeCalls = <(int, int)>[];
  final writes = <Uint8List>[];

  @override
  Stream<Uint8List> get output => outputController.stream;

  @override
  Future<int> get exitCode => exitCompleter.future;

  @override
  void kill() {
    killed = true;
    if (!exitCompleter.isCompleted) {
      exitCompleter.complete(0);
    }
  }

  @override
  void resize(int rows, int columns) {
    resizeCalls.add((rows, columns));
  }

  @override
  void write(Uint8List data) {
    writes.add(data);
  }
}

/// Passes [CliExecutableValidator] on the current platform. Tests use a fake
/// PTY, but [TerminalSession.connect] still runs pre-flight validation first.
String get _ptyTestExecutable {
  if (Platform.isWindows) {
    final root = Platform.environment['SystemRoot'] ?? r'C:\Windows';
    return '$root\\System32\\cmd.exe';
  }
  // macOS runners often lack /bin/true; Linux has it at /bin/true.
  for (final candidate in ['/usr/bin/true', '/bin/true', '/bin/sh']) {
    if (File(candidate).existsSync()) return candidate;
  }
  return Platform.resolvedExecutable;
}

void main() {
  test('missing absolute executable fails fast without starting pty', () {
    var started = false;
    final session = TerminalSession(
      executable: '/tmp/teampilot-missing-flashskyai-executable',
      ptyStarter:
          (
            executable, {
            required arguments,
            required workingDirectory,
            required columns,
            required rows,
            environment,
          }) {
            started = true;
            return _FakePtyHandle();
          },
    );
    addTearDown(session.dispose);

    session.connect(workingDirectory: Directory.current.path);

    expect(started, isFalse);
    expect(session.isRunning, isFalse);
    expect(
      session.terminal.buffer.getText(),
      contains('not found'),
    );
  });

  test('stays running while exitCode has not completed', () async {
    final handle = _FakePtyHandle();
    final exitNever = Completer<int>();
    handle.exitCompleter = exitNever;

    final session = TerminalSession(
      executable: _ptyTestExecutable,
      ptyStarter:
          (
            executable, {
            required arguments,
            required workingDirectory,
            required columns,
            required rows,
            environment,
          }) {
            return handle;
          },
    );
    addTearDown(() async {
      session.dispose();
      await handle.outputController.close();
    });

    session.connect(workingDirectory: Directory.systemTemp.path);
    session.terminal.onResize?.call(80, 24, 0, 0);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(session.isRunning, isTrue);

    await Future<void>.delayed(const Duration(seconds: 2));
    expect(session.isRunning, isTrue);
  });

  test('early pty exit reports failure and stops running', () async {
    final handle = _FakePtyHandle();
    var failed = false;
    final session = TerminalSession(
      executable: _ptyTestExecutable,
      ptyStarter:
          (
            executable, {
            required arguments,
            required workingDirectory,
            required columns,
            required rows,
            environment,
          }) {
            return handle;
          },
    );
    addTearDown(() async {
      session.dispose();
      await handle.outputController.close();
    });

    session.connect(
      workingDirectory: Directory.current.path,
      onProcessFailed: () => failed = true,
    );
    session.terminal.onResize?.call(80, 24, 0, 0);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    handle.outputController.add(
      Uint8List.fromList(utf8.encode('execvp: No such file or directory\r\n')),
    );
    await Future<void>.delayed(Duration.zero);

    expect(failed, isTrue);
    expect(session.isRunning, isFalse);
  });

  test('connect starts pty on first terminal resize', () async {
    final starts = <({int columns, int rows})>[];
    final handle = _FakePtyHandle();
    final session = TerminalSession(
      executable: _ptyTestExecutable,
      ptyStarter:
          (
            executable, {
            required arguments,
            required workingDirectory,
            required columns,
            required rows,
            environment,
          }) {
            starts.add((columns: columns, rows: rows));
            return handle;
          },
    );
    addTearDown(() async {
      session.dispose();
      await handle.outputController.close();
    });

    session.connect(workingDirectory: Directory.systemTemp.path);
    session.terminal.onResize?.call(80, 24, 0, 0);
    await Future<void>.delayed(const Duration(milliseconds: 300));

    expect(starts, [(columns: 80, rows: 24)]);
    expect(session.isRunning, isTrue);
  });

  test('rapid layout resizes debounce to final geometry', () async {
    final starts = <({int columns, int rows})>[];
    final handle = _FakePtyHandle();
    final session = TerminalSession(
      executable: _ptyTestExecutable,
      ptyStarter:
          (
            executable, {
            required arguments,
            required workingDirectory,
            required columns,
            required rows,
            environment,
          }) {
            starts.add((columns: columns, rows: rows));
            return handle;
          },
    );
    addTearDown(() async {
      session.dispose();
      await handle.outputController.close();
    });

    session.connect(workingDirectory: Directory.systemTemp.path);
    session.terminal.onResize?.call(80, 24, 0, 0);
    session.terminal.onResize?.call(100, 30, 0, 0);
    session.terminal.onResize?.call(120, 32, 0, 0);
    await Future<void>.delayed(const Duration(milliseconds: 300));

    expect(starts, [(columns: 120, rows: 32)]);
  });

  test('terminal resize resizes an already-started pty', () async {
    final handle = _FakePtyHandle();
    final session = TerminalSession(
      executable: _ptyTestExecutable,
      ptyStarter:
          (
            executable, {
            required arguments,
            required workingDirectory,
            required columns,
            required rows,
            environment,
          }) {
            return handle;
          },
    );
    addTearDown(() async {
      session.dispose();
      await handle.outputController.close();
    });

    session.connect(workingDirectory: Directory.systemTemp.path);
    session.terminal.onResize?.call(80, 24, 0, 0);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    handle.resizeCalls.clear();

    session.terminal.onResize?.call(80, 24, 0, 0);
    session.terminal.onResize?.call(120, 32, 0, 0);
    await Future<void>.delayed(const Duration(milliseconds: 300));

    expect(handle.resizeCalls, contains((32, 120)));
    expect(handle.resizeCalls.last, (32, 120));
  });

  test('pty output is written to the terminal buffer', () async {
    final handle = _FakePtyHandle();
    final session = TerminalSession(
      executable: _ptyTestExecutable,
      ptyStarter:
          (
            executable, {
            required arguments,
            required workingDirectory,
            required columns,
            required rows,
            environment,
          }) {
            return handle;
          },
    );
    addTearDown(() async {
      session.dispose();
      await handle.outputController.close();
    });

    session.connect(workingDirectory: Directory.systemTemp.path);
    session.terminal.onResize?.call(80, 24, 0, 0);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    handle.outputController.add(Uint8List.fromList(utf8.encode('hello\r\n')));
    await Future<void>.delayed(Duration.zero);

    expect(session.terminal.buffer.getText(), contains('hello'));
  });

  test('decodes pty output across utf8 chunk boundaries', () async {
    final handle = _FakePtyHandle();
    final session = TerminalSession(
      executable: _ptyTestExecutable,
      ptyStarter:
          (
            executable, {
            required arguments,
            required workingDirectory,
            required columns,
            required rows,
            environment,
          }) {
            return handle;
          },
    );
    addTearDown(() async {
      session.dispose();
      await handle.outputController.close();
    });

    session.connect(workingDirectory: Directory.systemTemp.path);
    session.terminal.onResize?.call(80, 24, 0, 0);
    await Future<void>.delayed(const Duration(milliseconds: 300));

    final bytes = utf8.encode('╰────任务已经完成了────╯\r\n');
    final split = bytes.indexOf(0xe4) + 1;
    handle.outputController
      ..add(Uint8List.fromList(bytes.take(split).toList()))
      ..add(Uint8List.fromList(bytes.skip(split).toList()));
    await Future<void>.delayed(Duration.zero);

    final text = session.terminal.buffer.getText();
    expect(text, contains('任务已经完成了'));
    expect(text, isNot(contains('\uFFFD')));
  });

  test('pty output schedules viewport sync resize', () async {
    final handle = _FakePtyHandle();
    final session = TerminalSession(
      executable: _ptyTestExecutable,
      ptyStarter:
          (
            executable, {
            required arguments,
            required workingDirectory,
            required columns,
            required rows,
            environment,
          }) {
            return handle;
          },
    );
    addTearDown(() async {
      session.dispose();
      await handle.outputController.close();
    });

    session.connect(workingDirectory: Directory.systemTemp.path);
    session.terminal.resize(100, 40);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    handle.resizeCalls.clear();

    handle.outputController.add(Uint8List.fromList(utf8.encode('draw\r\n')));
    await Future<void>.delayed(const Duration(milliseconds: 250));

    expect(handle.resizeCalls, isNotEmpty);
    expect(handle.resizeCalls.last, (40, 100));
  });

  test(
    'wsl sessions do not pass UNC working directory to Windows pty',
    () async {
      if (!Platform.isWindows) return;
      String? capturedExecutable;
      String? capturedWorkingDirectory;
      List<String>? capturedArguments;
      final handle = _FakePtyHandle();
      final session = TerminalSession(
        executable:
            r'\\wsl.localhost\Ubuntu\home\hhoa\flashskyai\dist\flashskyai',
        ptyStarter:
            (
              executable, {
              required arguments,
              required workingDirectory,
              required columns,
              required rows,
              environment,
            }) {
              capturedExecutable = executable;
              capturedArguments = List<String>.from(arguments);
              capturedWorkingDirectory = workingDirectory;
              return handle;
            },
      );
      addTearDown(() async {
        session.dispose();
        await handle.outputController.close();
      });

      session.connect(
        workingDirectory: r'\\wsl.localhost\Ubuntu\home\hhoa\project',
      );
      session.terminal.onResize?.call(80, 24, 0, 0);
      await Future<void>.delayed(const Duration(milliseconds: 300));

      if (capturedExecutable == 'wsl.exe') {
        expect(capturedWorkingDirectory, isNot(startsWith(r'\\wsl')));
        expect(
          capturedArguments,
          contains('/home/hhoa/flashskyai/dist/flashskyai'),
        );
        expect(capturedArguments, contains('/home/hhoa/project'));
      }
    },
  );

  test('single-slash wsl executable converts Windows project dir', () async {
    if (!Platform.isWindows) return;
    String? capturedExecutable;
    List<String>? capturedArguments;
    final handle = _FakePtyHandle();
    final session = TerminalSession(
      executable:
          r'\wsl.localhost\Ubuntu\home\hhoa\flashskai-ubuntu-wsl\dist\flashskyai',
      ptyStarter:
          (
            executable, {
            required arguments,
            required workingDirectory,
            required columns,
            required rows,
            environment,
          }) {
            capturedExecutable = executable;
            capturedArguments = List<String>.from(arguments);
            return handle;
          },
    );
    addTearDown(() async {
      session.dispose();
      await handle.outputController.close();
    });

    session.connect(workingDirectory: r'C:\Users\haung\git\teampilot\client');
    session.terminal.onResize?.call(80, 24, 0, 0);
    await Future<void>.delayed(const Duration(milliseconds: 300));

    if (capturedExecutable == 'wsl.exe') {
      expect(
        capturedArguments,
        contains('/home/hhoa/flashskai-ubuntu-wsl/dist/flashskyai'),
      );
      expect(
        capturedArguments,
        contains('/mnt/c/Users/haung/git/teampilot/client'),
      );
    }
  });

  test('wsl launch matches the manually verified command shape', () async {
    if (!Platform.isWindows) return;
    String? capturedExecutable;
    List<String>? capturedArguments;
    final handle = _FakePtyHandle();
    final session = TerminalSession(
      executable:
          r'\wsl.localhost\Ubuntu\home\hhoa\flashskai-ubuntu-wsl\dist\flashskyai',
      ptyStarter:
          (
            executable, {
            required arguments,
            required workingDirectory,
            required columns,
            required rows,
            environment,
          }) {
            capturedExecutable = executable;
            capturedArguments = List<String>.from(arguments);
            return handle;
          },
    );
    addTearDown(() async {
      session.dispose();
      await handle.outputController.close();
    });

    const team = TeamConfig(id: 'team', name: 'default-team-0');
    const member = TeamMemberConfig(id: 'member', name: 'team-lead');
    session.connect(
      workingDirectory: r'C:\Users\haung\git\teampilot\client',
      team: team,
      member: member,
    );
    session.terminal.onResize?.call(80, 24, 0, 0);
    await Future<void>.delayed(const Duration(milliseconds: 300));

    if (capturedExecutable == 'wsl.exe') {
      expect(capturedArguments, [
        '/home/hhoa/flashskai-ubuntu-wsl/dist/flashskyai',
        '--dir',
        '/mnt/c/Users/haung/git/teampilot/client',
        '--team',
        'default-team-0',
        '--member',
        'team-lead',
      ]);
    }
  });

  test('windows pty launch receives full environment for wsl.exe', () async {
    if (!Platform.isWindows) return;
    Map<String, String>? capturedEnvironment;
    final handle = _FakePtyHandle();
    final session = TerminalSession(
      executable:
          r'\wsl.localhost\Ubuntu\home\hhoa\flashskai-ubuntu-wsl\dist\flashskyai',
      ptyStarter:
          (
            executable, {
            required arguments,
            required workingDirectory,
            required columns,
            required rows,
            environment,
          }) {
            capturedEnvironment = environment == null
                ? null
                : Map<String, String>.from(environment);
            return handle;
          },
    );
    addTearDown(() async {
      session.dispose();
      await handle.outputController.close();
    });

    session.connect(
      workingDirectory: r'C:\Users\haung\git\teampilot\client',
      extraEnvironment: const {'LLM_CONFIG_PATH': r'C:\config.json'},
    );
    session.terminal.onResize?.call(80, 24, 0, 0);
    await Future<void>.delayed(const Duration(milliseconds: 300));

    expect(capturedEnvironment, isNotNull);
    expect(
      capturedEnvironment,
      containsPair('LLM_CONFIG_PATH', '/mnt/c/config.json'),
    );
    expect(capturedEnvironment!.keys, contains(anyOf('Path', 'PATH')));
    expect(
      capturedEnvironment!.keys,
      contains(anyOf('SystemRoot', 'windir', 'WINDIR')),
    );
  });
}
