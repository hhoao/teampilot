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
      executable: 'flashskyai',
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

    session.connect(workingDirectory: '/tmp');
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(session.isRunning, isTrue);

    await Future<void>.delayed(const Duration(seconds: 2));
    expect(session.isRunning, isTrue);
  });

  test('early pty exit reports failure and stops running', () async {
    final handle = _FakePtyHandle();
    var failed = false;
    final session = TerminalSession(
      executable: 'flashskyai',
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
    handle.outputController.add(
      Uint8List.fromList(utf8.encode('execvp: No such file or directory\r\n')),
    );
    await Future<void>.delayed(Duration.zero);

    expect(failed, isTrue);
    expect(session.isRunning, isFalse);
  });

  test('connect starts pty immediately before terminal resize', () async {
    final starts = <({int columns, int rows})>[];
    final handle = _FakePtyHandle();
    final session = TerminalSession(
      executable: 'flashskyai',
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

    session.connect(workingDirectory: '/tmp');

    expect(starts, [(columns: 80, rows: 24)]);
    expect(session.isRunning, isTrue);
  });

  test('terminal resize resizes an already-started pty', () async {
    final handle = _FakePtyHandle();
    final session = TerminalSession(
      executable: 'flashskyai',
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

    session.connect(workingDirectory: '/tmp');
    session.terminal.onResize?.call(120, 32, 0, 0);

    expect(handle.resizeCalls, [(32, 120)]);
  });

  test('pty output is written to the terminal buffer', () async {
    final handle = _FakePtyHandle();
    final session = TerminalSession(
      executable: 'flashskyai',
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

    session.connect(workingDirectory: '/tmp');
    handle.outputController.add(Uint8List.fromList(utf8.encode('hello\r\n')));
    await Future<void>.delayed(Duration.zero);

    expect(session.terminal.buffer.getText(), contains('hello'));
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
