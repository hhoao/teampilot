import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_alacritty/links/terminal_link_provider.dart';
import 'package:flutter_alacritty/links/url_link_provider.dart';
import 'package:teampilot/services/terminal/file_path_link_provider.dart';
import 'package:teampilot/services/terminal/terminal_export.dart';
import 'package:teampilot/services/terminal/terminal_session.dart';
import 'package:teampilot/services/terminal/terminal_uri_opener.dart';
import 'package:teampilot/services/terminal/terminal_transport.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/session/shell_launch_spec.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/flush_terminal_engine.dart';

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
    session.onViewportResize(80, 24);
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
    session.onViewportResize(80, 24);
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
      onProcessFailed: (_) => failed = true,
    );
    session.onViewportResize(80, 24);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    handle.doneCompleter.complete(127);
    await Future<void>.delayed(Duration.zero);

    expect(failed, isTrue);
    expect(session.isRunning, isFalse);
    await flushTerminalEngine(session.engine);
    expect(
      exportTerminalScrollback(session.engine),
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
      onProcessFailed: (_) => failed = true,
    );
    session.onViewportResize(80, 24);
    await Future<void>.delayed(const Duration(milliseconds: 120));

    expect(failed, isTrue);
    expect(session.isRunning, isFalse);
    await flushTerminalEngine(session.engine);
    expect(exportTerminalScrollback(session.engine), contains('spawn timed out'));
  });

  test('missing absolute executable fails fast without starting pty', () async {
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
    session.onViewportResize(80, 24);
    await flushTerminalEngine(session.engine);

    expect(started, isFalse);
    expect(session.isRunning, isFalse);
    await flushTerminalEngine(session.engine);
    expect(
      exportTerminalScrollback(session.engine),
      anyOf(contains('not found'), contains('未找到')),
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
    session.onViewportResize(80, 24);
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
    session.onViewportResize(80, 24);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(session.isRunning, isTrue);

    handle.doneCompleter.complete(0);
    await Future<void>.delayed(Duration.zero);
    await handle.done;

    expect(exited, isTrue);
    expect(session.isRunning, isFalse);
    expect(handle.closed, isTrue);
    await flushTerminalEngine(session.engine);
    expect(
      exportTerminalScrollback(session.engine),
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
    session.onViewportResize(80, 24);
    await Future<void>.delayed(const Duration(milliseconds: 300));

    handle.doneCompleter.complete(1);
    await Future<void>.delayed(Duration.zero);
    await handle.done;

    expect(session.isRunning, isTrue);
    await flushTerminalEngine(session.engine);
    expect(
      exportTerminalScrollback(session.engine),
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
      onProcessFailed: (_) => failed = true,
    );
    session.onViewportResize(80, 24);
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
    const team = TeamProfile(
      id: 'team',
      name: 'default-team-0',
      cli: CliTool.claude,
    );
    const lead = TeamMemberConfig(id: 'team-lead', name: 'team-lead');
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

    final shellLaunch = ShellLaunchSpec.teamMember(
      team: team,
      member: lead,
      workingDirectory: Directory.systemTemp.path,
    );
    leadSession.connect(
      workingDirectory: Directory.systemTemp.path,
      shellLaunch: shellLaunch,
    );
    devSession.connect(
      workingDirectory: Directory.systemTemp.path,
      shellLaunch: ShellLaunchSpec.teamMember(
        team: team,
        member: dev,
        workingDirectory: Directory.systemTemp.path,
      ),
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
        (args) => args.contains('--agent-name') && args.contains('dev'),
      ),
      isTrue,
    );
    expect(leadSession.isRunning, isTrue);
    expect(devSession.isRunning, isTrue);
  });

  test(
    'independent flashskyai sessions use --team and --member per member',
    () async {
    const team = TeamProfile(
      id: 'team',
      name: 'default-team-0',
      cli: CliTool.flashskyai,
    );
    const lead = TeamMemberConfig(id: 'team-lead', name: 'team-lead');
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
      shellLaunch: ShellLaunchSpec.teamMember(
        team: team,
        member: lead,
        workingDirectory: Directory.systemTemp.path,
      ),
    );
    devSession.connect(
      workingDirectory: Directory.systemTemp.path,
      shellLaunch: ShellLaunchSpec.teamMember(
        team: team,
        member: dev,
        workingDirectory: Directory.systemTemp.path,
      ),
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
        (args) => args.contains('--member') && args.contains('dev'),
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
    session.onViewportResize(80, 24);
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
    session.onViewportResize(80, 24);
    session.onViewportResize(100, 30);
    session.onViewportResize(120, 32);
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
    session.onViewportResize(80, 24);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    handle.resizeCalls.clear();

    session.onViewportResize(80, 24);
    session.onViewportResize(120, 32);
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
    session.onViewportResize(80, 24);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    handle.outputController.add(Uint8List.fromList(utf8.encode('hello\r\n')));
    await Future<void>.delayed(Duration.zero);
    await flushTerminalEngine(session.engine);

    expect(exportTerminalScrollback(session.engine), contains('hello'));
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
    session.onViewportResize(80, 24);
    await Future<void>.delayed(const Duration(milliseconds: 300));

    final bytes = utf8.encode('café finished\r\n');
    // Split inside é (UTF-8 c3 a9).
    final split = bytes.indexOf(0xc3) + 1;
    handle.outputController
      ..add(Uint8List.fromList(bytes.take(split).toList()))
      ..add(Uint8List.fromList(bytes.skip(split).toList()));
    await Future<void>.delayed(Duration.zero);
    await flushTerminalEngine(session.engine);

    final text = exportTerminalScrollback(session.engine);
    expect(text, contains('café finished'));
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
    session.onViewportResize(80, 24);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    handle.resizeCalls.clear();

    // Resize viewport without immediate PTY sync so output path can sync later.
    session.onViewportResize(100, 40);
    expect(session.viewWidth, 100);
    expect(session.viewHeight, 40);

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
        workingDirectory: r'\\wsl.localhost\Ubuntu\home\hhoa\workspace',
      );
      session.onViewportResize(80, 24);
      await Future<void>.delayed(const Duration(milliseconds: 300));

      if (capturedExecutable == 'wsl.exe') {
        expect(capturedWorkingDirectory, isNot(startsWith(r'\\wsl')));
        expect(
          capturedArguments,
          contains('/home/hhoa/flashskyai/dist/flashskyai'),
        );
        expect(capturedArguments, contains('/home/hhoa/workspace'));
      }
    },
  );

  test('single-slash wsl executable converts Windows workspace dir', () async {
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
    session.onViewportResize(80, 24);
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

    const team = TeamProfile(
      id: 'team',
      name: 'default-team-0',
      cli: CliTool.flashskyai,
    );
    const member = TeamMemberConfig(id: 'member', name: 'team-lead', dangerouslySkipPermissions: false);
    session.connect(
      workingDirectory: r'C:\Users\haung\git\teampilot\client',
      shellLaunch: ShellLaunchSpec.teamMember(
        team: team,
        member: member,
        workingDirectory: r'C:\Users\haung\git\teampilot\client',
      ),
    );
    session.onViewportResize(80, 24);
    await Future<void>.delayed(const Duration(milliseconds: 300));

    if (capturedExecutable == 'wsl.exe') {
      expect(capturedArguments, [
        '/home/hhoa/flashskai-ubuntu-wsl/dist/flashskyai',
        '--dir',
        '/mnt/c/Users/haung/git/teampilot/client',
        '--team',
        'default-team-0',
        '--member',
        'member',
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
    session.onViewportResize(80, 24);
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

  test('submitFullScreenInput writes bracketed paste then a standalone CR',
      () async {
    final handle = _FakeTransport();
    final session = TerminalSession(
      executable: _ptyTestExecutable,
      confirmFallback: const Duration(milliseconds: 20),
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
    session.onViewportResize(80, 24);
    handle.outputController.add(Uint8List.fromList(utf8.encode('ready\r\n')));
    await Future<void>.delayed(Duration.zero);
    expect(session.isRunning, isTrue);

    await session.submitFullScreenInput('hello team');

    final writes = handle.writes.map(utf8.decode).toList();
    // Text arrives wrapped in bracketed-paste markers, and the CR is a separate
    // write — so Claude Code's full-screen TUI registers a discrete Enter
    // (submit) rather than a literal newline inside a paste burst.
    expect(writes, ['\x1B[200~hello team\x1B[201~', '\r']);
  });

  test('writeln writes text and CR as a single chunk (line CLIs)', () async {
    final handle = _FakeTransport();
    final session = TerminalSession(
      executable: _ptyTestExecutable,
      confirmFallback: const Duration(milliseconds: 20),
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
    session.onViewportResize(80, 24);
    handle.outputController.add(Uint8List.fromList(utf8.encode('ready\r\n')));
    await Future<void>.delayed(Duration.zero);

    session.writeln('hello team');

    final writes = handle.writes.map(utf8.decode).toList();
    expect(writes, ['hello team\r']);
  });

  group('linkProviders', () {
    TerminalSession _makeSession() => TerminalSession(
          executable: _ptyTestExecutable,
          validateLaunch: false,
          transportStarter: (
            executable, {
            required arguments,
            required workingDirectory,
            required columns,
            required rows,
            environment,
          }) =>
              Future.value(_FakeTransport()),
        );

    test('returns a UrlLinkProvider and a FilePathLinkProvider', () {
      final session = _makeSession();
      addTearDown(session.dispose);

      final providers = session.linkProviders;
      expect(providers, hasLength(2));
      expect(providers[0], isA<UrlLinkProvider>());
      expect(providers[1], isA<FilePathLinkProvider>());
    });

    test('returns the same list instance on repeated access (lazy/cached)', () {
      final session = _makeSession();
      addTearDown(session.dispose);

      final first = session.linkProviders;
      final second = session.linkProviders;
      expect(identical(first, second), isTrue);
    });

    test('dispose clears and disposes the providers', () {
      final session = _makeSession();

      // Force allocation before dispose.
      final providers = List<TerminalLinkProvider>.from(session.linkProviders);
      session.dispose();

      // A disposed ChangeNotifier throws FlutterError on addListener.
      for (final p in providers) {
        expect(() => p.addListener(() {}), throwsFlutterError);
      }
    });

    test('parseOsc7Cwd maps a file:// report to a local path', () {
      // Compare against the same resolver the parser uses so the expectation
      // holds on both Windows and POSIX path styles.
      final expected = TerminalUriOpener.resolveLocalFilePath(
        'file://localhost/tmp/proj',
      );
      expect(TerminalSession.parseOsc7Cwd('file://localhost/tmp/proj'), expected);
      expect(expected, isNotNull);
    });

    test('parseOsc7Cwd returns null for empty or unparseable reports', () {
      expect(TerminalSession.parseOsc7Cwd(''), isNull);
      expect(TerminalSession.parseOsc7Cwd('   '), isNull);
    });
  });
}
