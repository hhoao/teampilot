import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:teampilot/services/terminal_session.dart';
import 'package:teampilot/services/terminal_transport.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeTransport implements TerminalTransport {
  final outputController = StreamController<Uint8List>();
  Completer<int> doneCompleter = Completer<int>();
  var closed = false;
  final resizeCalls = <(int, int)>[];
  final writes = <Uint8List>[];

  @override
  Stream<Uint8List> get output => outputController.stream;

  @override
  Future<int> get done => doneCompleter.future;

  @override
  void close() {
    closed = true;
    if (!doneCompleter.isCompleted) {
      doneCompleter.complete(0);
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
  test('confirms on first pty output before fallback timer', () async {
    final handle = _FakeTransport();
    var started = false;
    final session = TerminalSession(
      executable: _ptyTestExecutable,
      confirmFallback: const Duration(seconds: 5),
      transportStarter:
          (
            executable, {
            required arguments,
            required workingDirectory,
            required columns,
            required rows,
            environment,
          }) {
            return Future.value(handle);
          },
    );
    addTearDown(() async {
      session.dispose();
      await handle.outputController.close();
    });

    session.connect(
      workingDirectory: Directory.systemTemp.path,
      onProcessStarted: () => started = true,
    );
    session.terminal.onResize?.call(80, 24, 0, 0);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(started, isFalse);

    handle.outputController.add(Uint8List.fromList(utf8.encode('ready\r\n')));
    await Future<void>.delayed(Duration.zero);

    expect(started, isTrue);
    expect(session.isRunning, isTrue);
  });

  test('silent startup confirms on fallback timer', () async {
    final handle = _FakeTransport();
    var started = false;
    final session = TerminalSession(
      executable: _ptyTestExecutable,
      confirmFallback: const Duration(milliseconds: 50),
      transportStarter:
          (
            executable, {
            required arguments,
            required workingDirectory,
            required columns,
            required rows,
            environment,
          }) {
            return Future.value(handle);
          },
    );
    addTearDown(() async {
      session.dispose();
      await handle.outputController.close();
    });

    session.connect(
      workingDirectory: Directory.systemTemp.path,
      onProcessStarted: () => started = true,
    );
    session.terminal.onResize?.call(80, 24, 0, 0);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(started, isFalse);

    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(started, isTrue);
  });

  test('process exit during startup reports failure', () async {
    final handle = _FakeTransport();
    var failed = false;
    final session = TerminalSession(
      executable: _ptyTestExecutable,
      confirmFallback: const Duration(seconds: 5),
      transportStarter:
          (
            executable, {
            required arguments,
            required workingDirectory,
            required columns,
            required rows,
            environment,
          }) {
            return Future.value(handle);
          },
    );
    addTearDown(() async {
      session.dispose();
      await handle.outputController.close();
    });

    session.connect(
      workingDirectory: Directory.systemTemp.path,
      onProcessStarted: () {},
      onProcessFailed: () => failed = true,
    );
    session.terminal.onResize?.call(80, 24, 0, 0);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    handle.doneCompleter.complete(127);
    await Future<void>.delayed(Duration.zero);

    expect(failed, isTrue);
    expect(session.isRunning, isFalse);
    expect(
      session.terminal.buffer.getText(),
      contains('exited with code 127 during startup'),
    );
  });

  test('spawn timeout reports failure when transport never attaches', () async {
    final starter = Completer<TerminalTransport>();
    var failed = false;
    final session = TerminalSession(
      executable: _ptyTestExecutable,
      startupDeadline: const Duration(milliseconds: 80),
      transportStarter:
          (
            executable, {
            required arguments,
            required workingDirectory,
            required columns,
            required rows,
            environment,
          }) {
            return starter.future;
          },
    );
    addTearDown(session.dispose);

    session.connect(
      workingDirectory: Directory.systemTemp.path,
      onProcessFailed: () => failed = true,
    );
    session.terminal.onResize?.call(80, 24, 0, 0);
    await Future<void>.delayed(const Duration(milliseconds: 120));

    expect(failed, isTrue);
    expect(session.isRunning, isFalse);
    expect(session.terminal.buffer.getText(), contains('spawn timed out'));
  });

  test('missing absolute executable fails fast without starting pty', () {
    var started = false;
    final session = TerminalSession(
      executable: '/tmp/teampilot-missing-flashskyai-executable',
      transportStarter:
          (
            executable, {
            required arguments,
            required workingDirectory,
            required columns,
            required rows,
            environment,
          }) {
            started = true;
            return Future.value(_FakeTransport());
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
    final handle = _FakeTransport();
    final exitNever = Completer<int>();
    handle.doneCompleter = exitNever;

    final session = TerminalSession(
      executable: _ptyTestExecutable,
      transportStarter:
          (
            executable, {
            required arguments,
            required workingDirectory,
            required columns,
            required rows,
            environment,
          }) {
            return Future.value(handle);
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

  test('clean exit stops running and notifies onProcessExited', () async {
    final handle = _FakeTransport();
    var exited = false;

    final session = TerminalSession(
      executable: _ptyTestExecutable,
      validateLaunch: false,
      transportStarter:
          (
            executable, {
            required arguments,
            required workingDirectory,
            required columns,
            required rows,
            environment,
          }) {
            return Future.value(handle);
          },
    );
    addTearDown(() async {
      session.dispose();
      await handle.outputController.close();
    });

    session.connect(
      workingDirectory: Directory.systemTemp.path,
      onProcessExited: () => exited = true,
    );
    session.terminal.onResize?.call(80, 24, 0, 0);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(session.isRunning, isTrue);

    handle.doneCompleter.complete(0);
    await Future<void>.delayed(Duration.zero);
    await handle.done;

    expect(exited, isTrue);
    expect(session.isRunning, isFalse);
    expect(handle.closed, isTrue);
    expect(
      session.terminal.buffer.getText(),
      isNot(contains('[process exited]')),
    );
  });

  test('non-zero exit keeps terminal running for inspection', () async {
    final handle = _FakeTransport();

    final session = TerminalSession(
      executable: _ptyTestExecutable,
      validateLaunch: false,
      transportStarter:
          (
            executable, {
            required arguments,
            required workingDirectory,
            required columns,
            required rows,
            environment,
          }) {
            return Future.value(handle);
          },
    );
    addTearDown(() async {
      session.dispose();
      await handle.outputController.close();
    });

    session.connect(workingDirectory: Directory.systemTemp.path);
    session.terminal.onResize?.call(80, 24, 0, 0);
    await Future<void>.delayed(const Duration(milliseconds: 300));

    handle.doneCompleter.complete(1);
    await Future<void>.delayed(Duration.zero);
    await handle.done;

    expect(session.isRunning, isTrue);
    expect(
      session.terminal.buffer.getText(),
      contains('[process exited with code 1]'),
    );
  });

  test('exec failure output during confirming reports failure', () async {
    final handle = _FakeTransport();
    var failed = false;
    final session = TerminalSession(
      executable: _ptyTestExecutable,
      confirmFallback: const Duration(seconds: 5),
      transportStarter:
          (
            executable, {
            required arguments,
            required workingDirectory,
            required columns,
            required rows,
            environment,
          }) {
            return Future.value(handle);
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
    await Future<void>.delayed(const Duration(milliseconds: 20));
    handle.outputController.add(
      Uint8List.fromList(utf8.encode('execvp: No such file or directory\r\n')),
    );
    await Future<void>.delayed(Duration.zero);

    expect(failed, isTrue);
    expect(session.isRunning, isFalse);
  });

  test(
    'independent Claude sessions spawn concurrently with distinct agent args',
    () async {
    const team = TeamConfig(
      id: 'team',
      name: 'default-team-0',
      cli: TeamCli.claude,
    );
    const lead = TeamMemberConfig(id: 'lead', name: 'team-lead');
    const dev = TeamMemberConfig(id: 'dev', name: 'developer');
    final startedArgs = <List<String>>[];

    TerminalSession sessionFor(TeamMemberConfig member) {
      return TerminalSession(
        executable: _ptyTestExecutable,
        transportStarter:
            (
              executable, {
              required arguments,
              required workingDirectory,
              required columns,
              required rows,
              environment,
            }) {
              startedArgs.add(List<String>.from(arguments));
              return Future.value(_FakeTransport());
            },
      );
    }

    final leadSession = sessionFor(lead);
    final devSession = sessionFor(dev);
    addTearDown(() async {
      leadSession.dispose();
      devSession.dispose();
    });

    leadSession.connect(
      workingDirectory: Directory.systemTemp.path,
      team: team,
      member: lead,
    );
    devSession.connect(
      workingDirectory: Directory.systemTemp.path,
      team: team,
      member: dev,
    );
    await Future<void>.delayed(const Duration(milliseconds: 500));

    expect(startedArgs, hasLength(2));
    expect(
      startedArgs.any(
        (args) => args.contains('--agent-name') && args.contains('team-lead'),
      ),
      isTrue,
    );
    expect(
      startedArgs.any(
        (args) => args.contains('--agent-name') && args.contains('developer'),
      ),
      isTrue,
    );
    expect(leadSession.isRunning, isTrue);
    expect(devSession.isRunning, isTrue);
  });

  test(
    'independent flashskyai sessions use --team and --member per member',
    () async {
    const team = TeamConfig(
      id: 'team',
      name: 'default-team-0',
      cli: TeamCli.flashskyai,
    );
    const lead = TeamMemberConfig(id: 'lead', name: 'team-lead');
    const dev = TeamMemberConfig(id: 'dev', name: 'developer');
    final startedArgs = <List<String>>[];

    TerminalSession sessionFor(TeamMemberConfig member) {
      return TerminalSession(
        executable: _ptyTestExecutable,
        transportStarter:
            (
              executable, {
              required arguments,
              required workingDirectory,
              required columns,
              required rows,
              environment,
            }) {
              startedArgs.add(List<String>.from(arguments));
              return Future.value(_FakeTransport());
            },
      );
    }

    final leadSession = sessionFor(lead);
    final devSession = sessionFor(dev);
    addTearDown(() async {
      leadSession.dispose();
      devSession.dispose();
    });

    leadSession.connect(
      workingDirectory: Directory.systemTemp.path,
      team: team,
      member: lead,
    );
    devSession.connect(
      workingDirectory: Directory.systemTemp.path,
      team: team,
      member: dev,
    );
    await Future<void>.delayed(const Duration(milliseconds: 500));

    expect(startedArgs, hasLength(2));
    expect(
      startedArgs.any(
        (args) => args.contains('--member') && args.contains('team-lead'),
      ),
      isTrue,
    );
    expect(
      startedArgs.any(
        (args) => args.contains('--member') && args.contains('developer'),
      ),
      isTrue,
    );
  });

  test(
    'connect spawns pty with default viewport without TerminalView resize',
    () async {
      final starts = <({int columns, int rows})>[];
      final handle = _FakeTransport();
      final session = TerminalSession(
        executable: _ptyTestExecutable,
        transportStarter:
            (
              executable, {
              required arguments,
              required workingDirectory,
              required columns,
              required rows,
              environment,
            }) {
              starts.add((columns: columns, rows: rows));
              return Future.value(handle);
            },
      );
      addTearDown(() async {
        session.dispose();
        await handle.outputController.close();
      });

      session.connect(workingDirectory: Directory.systemTemp.path);
      await Future<void>.delayed(const Duration(milliseconds: 300));

      expect(starts, [(columns: 80, rows: 24)]);
      expect(session.isRunning, isTrue);
    },
  );

  test('connect starts pty on first terminal resize', () async {
    final starts = <({int columns, int rows})>[];
    final handle = _FakeTransport();
    final session = TerminalSession(
      executable: _ptyTestExecutable,
      transportStarter:
          (
            executable, {
            required arguments,
            required workingDirectory,
            required columns,
            required rows,
            environment,
          }) {
            starts.add((columns: columns, rows: rows));
            return Future.value(handle);
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
    final handle = _FakeTransport();
    final session = TerminalSession(
      executable: _ptyTestExecutable,
      transportStarter:
          (
            executable, {
            required arguments,
            required workingDirectory,
            required columns,
            required rows,
            environment,
          }) {
            starts.add((columns: columns, rows: rows));
            return Future.value(handle);
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

    expect(starts, [(columns: 80, rows: 24)]);
    expect(handle.resizeCalls, isNotEmpty);
    expect(handle.resizeCalls.last, (32, 120));
  });

  test('terminal resize resizes an already-started pty', () async {
    final handle = _FakeTransport();
    final session = TerminalSession(
      executable: _ptyTestExecutable,
      transportStarter:
          (
            executable, {
            required arguments,
            required workingDirectory,
            required columns,
            required rows,
            environment,
          }) {
            return Future.value(handle);
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
    final handle = _FakeTransport();
    final session = TerminalSession(
      executable: _ptyTestExecutable,
      transportStarter:
          (
            executable, {
            required arguments,
            required workingDirectory,
            required columns,
            required rows,
            environment,
          }) {
            return Future.value(handle);
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
    final handle = _FakeTransport();
    final session = TerminalSession(
      executable: _ptyTestExecutable,
      transportStarter:
          (
            executable, {
            required arguments,
            required workingDirectory,
            required columns,
            required rows,
            environment,
          }) {
            return Future.value(handle);
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
    final handle = _FakeTransport();
    final session = TerminalSession(
      executable: _ptyTestExecutable,
      transportStarter:
          (
            executable, {
            required arguments,
            required workingDirectory,
            required columns,
            required rows,
            environment,
          }) {
            return Future.value(handle);
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

    // Resize viewport without immediate PTY sync so output path can sync later.
    final savedOnResize = session.terminal.onResize;
    session.terminal.onResize = null;
    session.terminal.resize(100, 40);
    session.terminal.onResize = savedOnResize;
    expect(session.terminal.viewWidth, 100);
    expect(session.terminal.viewHeight, 40);

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
      final handle = _FakeTransport();
      final session = TerminalSession(
        executable:
            r'\\wsl.localhost\Ubuntu\home\hhoa\flashskyai\dist\flashskyai',
        transportStarter:
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
              return Future.value(handle);
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
    final handle = _FakeTransport();
    final session = TerminalSession(
      executable:
          r'\wsl.localhost\Ubuntu\home\hhoa\flashskai-ubuntu-wsl\dist\flashskyai',
      transportStarter:
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
            return Future.value(handle);
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
    final handle = _FakeTransport();
    final session = TerminalSession(
      executable:
          r'\wsl.localhost\Ubuntu\home\hhoa\flashskai-ubuntu-wsl\dist\flashskyai',
      transportStarter:
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
            return Future.value(handle);
          },
    );
    addTearDown(() async {
      session.dispose();
      await handle.outputController.close();
    });

    const team = TeamConfig(
      id: 'team',
      name: 'default-team-0',
      cli: TeamCli.flashskyai,
    );
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
    final handle = _FakeTransport();
    final session = TerminalSession(
      executable:
          r'\wsl.localhost\Ubuntu\home\hhoa\flashskai-ubuntu-wsl\dist\flashskyai',
      transportStarter:
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
            return Future.value(handle);
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
