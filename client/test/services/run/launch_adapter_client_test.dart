import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/run/launch_type_contribution.dart';
import 'package:teampilot/services/run/launch_adapter_client.dart';
import 'package:teampilot/services/run/launch_adapter_protocol.dart';

String get _fakeAdapterScript {
  final testDir = Directory.current.path.endsWith('client')
      ? Directory.current.path
      : '${Directory.current.path}/client';
  return '$testDir/test/fixtures/fake_launch_adapter/fake_launch_adapter.dart';
}

Future<LaunchAdapterProcess> startFakeAdapter({
  required String command,
  required List<String> args,
}) async {
  // Use the Dart SDK binary — Platform.resolvedExecutable under flutter test
  // is flutter_tester and prints VM-service noise on stdout.
  final process = await Process.start(
    'dart',
    ['--disable-dart-dev', _fakeAdapterScript],
  );
  return LaunchAdapterProcess.fromIo(
    stdin: process.stdin,
    stdout: process.stdout,
    stderr: process.stderr,
    exitCode: process.exitCode,
    kill: process.kill,
  );
}

LaunchAdapterClient createClient({
  LaunchAdapterProcessStarter? startProcess,
  Duration? initializeTimeout,
  Duration? launchTimeout,
}) {
  return LaunchAdapterClient(
    startProcess: startProcess ?? startFakeAdapter,
    extensionPathResolver: (_) => '/ext/fake',
    initializeTimeout: initializeTimeout,
    launchTimeout: launchTimeout,
  );
}

void main() {
  test('encodeNotification omits id', () {
    final encoded = LaunchAdapterProtocol.encodeNotification(
      method: 'output',
      params: {'sessionId': 's1', 'category': 'stdout', 'data': 'x'},
    );
    final decoded = jsonDecode(encoded) as Map<String, Object?>;
    expect(decoded.containsKey('id'), isFalse);
    expect(decoded['method'], 'output');
  });

  test('initialize launch output exited', () async {
    final client = createClient();
    addTearDown(client.dispose);

    await client.initialize(
      type: 'flutter',
      targetId: 'local',
      adapterCommand: r'${extensionPath}/bin/fake',
      extensionId: 'ext.fake',
      lifecycle: LaunchAdapterLifecycle.sticky,
    );

    const sessionId = 's1';
    final outputFuture = client.outputStream
        .where((e) => e.sessionId == sessionId)
        .timeout(const Duration(seconds: 5))
        .first;

    await client.launch(
      sessionId: sessionId,
      configuration: {
        'id': 'main',
        'name': 'Main',
        'type': 'flutter',
        'request': 'launch',
      },
    );

    final output = await outputFuture;
    expect(output.data, contains('ok'));

    final exited = await client.waitExited(sessionId).timeout(
      const Duration(seconds: 5),
    );
    expect(exited.exitCode, 0);
  });

  test('configureAction requires explicit type', () async {
    final client = createClient();
    addTearDown(client.dispose);

    await client.initialize(
      type: 'flutter',
      targetId: 'local',
      adapterCommand: r'${extensionPath}/bin/fake',
      extensionId: 'ext.fake',
    );

    final draft = await client.configureAction(
      type: 'flutter',
      targetId: 'local',
      actionId: 'select_entry',
      workspaceFolder: '/proj',
      result: {'kind': 'file', 'path': '/proj/lib/main.dart'},
    );
    expect(draft.cancelled, isFalse);
    expect(draft.configuration?['id'], isNotEmpty);
  });

  test('provideOptions and optionsChanged are scoped to type+targetId', () async {
    final client = createClient();
    addTearDown(client.dispose);

    final optionsChangedFuture = client.optionsChanged
        .timeout(const Duration(seconds: 5))
        .first;

    await client.initialize(
      type: 'flutter',
      targetId: 'local',
      adapterCommand: r'${extensionPath}/bin/fake',
      extensionId: 'ext.fake',
    );

    final pushed = await optionsChangedFuture;
    expect(pushed.type, 'flutter');
    expect(pushed.targetId, 'local');
    expect(pushed.options, isNotEmpty);
    expect(pushed.options.single.id, 'device');

    final options = await client.provideOptions(
      configurationId: 'main',
      configuration: {'type': 'flutter'},
      type: 'flutter',
      targetId: 'local',
    );
    expect(options.single.id, 'device');
    expect(options.single.type, LaunchOptionType.choice);
  });

  test('configurationsChanged includes isAction and scope', () async {
    final client = createClient();
    addTearDown(client.dispose);

    final entriesFuture = client.configurationsChanged
        .timeout(const Duration(seconds: 5))
        .first;

    await client.initialize(
      type: 'flutter',
      targetId: 'local',
      adapterCommand: r'${extensionPath}/bin/fake',
      extensionId: 'ext.fake',
    );

    final event = await entriesFuture;
    expect(event.type, 'flutter');
    expect(event.targetId, 'local');
    expect(event.configurations.any((e) => e.isAction == true), isTrue);
  });

  test('initialize timeout kills hung adapter and removes from pool', () async {
    var killCount = 0;
    var spawnCount = 0;
    final client = createClient(
      initializeTimeout: const Duration(milliseconds: 80),
      startProcess: ({required command, required args}) async {
        spawnCount++;
        final exitCompleter = Completer<int>();
        // Keep stdout/stderr open so onDone does not race the initialize timeout.
        final stdout = StreamController<List<int>>();
        final stderr = StreamController<List<int>>();
        addTearDown(() async {
          await stdout.close();
          await stderr.close();
        });
        return LaunchAdapterProcess(
          stdin: _NullSink(),
          stdout: stdout.stream,
          stderr: stderr.stream,
          exitCode: exitCompleter.future,
          kill: ([ProcessSignal signal = ProcessSignal.sigterm]) {
            killCount++;
            if (!exitCompleter.isCompleted) {
              exitCompleter.complete(-1);
            }
          },
        );
      },
    );
    addTearDown(client.dispose);

    await expectLater(
      client.initialize(
        type: 'flutter',
        targetId: 'local',
        adapterCommand: 'hung',
      ),
      throwsA(isA<TimeoutException>()),
    );
    expect(killCount, greaterThanOrEqualTo(1));

    // Pool cleared: a second initialize must spawn again (not reuse hung child).
    await expectLater(
      client.initialize(
        type: 'flutter',
        targetId: 'local',
        adapterCommand: 'hung-again',
      ),
      throwsA(isA<TimeoutException>()),
    );
    expect(spawnCount, 2);
    expect(killCount, greaterThanOrEqualTo(2));
  });

  test('oneshot concurrent launches do not kill each other', () async {
    final client = createClient();
    addTearDown(client.dispose);

    Future<int> runSession(String sessionId) async {
      await client.launch(
        sessionId: sessionId,
        configuration: {
          'id': 'main',
          'name': 'Main',
          'type': 'flutter',
          'request': 'launch',
        },
        type: 'flutter',
        targetId: 'local',
        adapterCommand: r'${extensionPath}/bin/fake',
        extensionId: 'ext.fake',
        lifecycle: LaunchAdapterLifecycle.oneshot,
      );
      final exited = await client.waitExited(sessionId).timeout(
        const Duration(seconds: 8),
      );
      return exited.exitCode;
    }

    final results = await Future.wait([
      runSession('oneshot-a'),
      runSession('oneshot-b'),
    ]);
    expect(results, [0, 0]);
  });

  test('error stream surfaces adapter error notifications', () async {
    final stdinLines = StreamController<String>();
    final stdoutController = StreamController<List<int>>();
    final exitCompleter = Completer<int>();

    stdinLines.stream.listen((line) {
      final msg = jsonDecode(line) as Map<String, Object?>;
      final method = msg['method'];
      final id = msg['id'];
      void reply(Map<String, Object?> result) {
        stdoutController.add(
          utf8.encode('${jsonEncode({
            'jsonrpc': '2.0',
            'id': id,
            'result': result,
          })}\n'),
        );
      }

      void notify(String methodName, Map<String, Object?> params) {
        stdoutController.add(
          utf8.encode('${jsonEncode({
            'jsonrpc': '2.0',
            'method': methodName,
            'params': params,
          })}\n'),
        );
      }

      if (method == 'initialize') {
        reply({'protocolVersion': 1});
      } else if (method == 'launch') {
        final sessionId =
            (msg['params'] as Map)['sessionId']?.toString() ?? '';
        reply({'accepted': true});
        notify('error', {'sessionId': sessionId, 'message': 'boom'});
      }
    });

    final client = createClient(
      startProcess: ({required command, required args}) async {
        return LaunchAdapterProcess(
          stdin: _CapturingSink(stdinLines),
          stdout: stdoutController.stream,
          stderr: const Stream.empty(),
          exitCode: exitCompleter.future,
          kill: ([ProcessSignal signal = ProcessSignal.sigterm]) {
            if (!exitCompleter.isCompleted) {
              exitCompleter.complete(-1);
            }
          },
        );
      },
    );
    addTearDown(() async {
      await client.dispose();
      await stdinLines.close();
      await stdoutController.close();
    });

    final errorFuture = client.errorStream
        .timeout(const Duration(seconds: 5))
        .first;
    // Error notification fails the session waiter; listen so it is not unhandled.
    final failedExit = client.waitExited('err-s1');

    await client.initialize(
      type: 'flutter',
      targetId: 'local',
      adapterCommand: 'err',
    );
    await client.launch(
      sessionId: 'err-s1',
      configuration: {'type': 'flutter'},
      type: 'flutter',
      targetId: 'local',
    );

    final error = await errorFuture;
    expect(error.sessionId, 'err-s1');
    expect(error.message, 'boom');
    expect(error.type, 'flutter');
    expect(error.targetId, 'local');
    await expectLater(failedExit, throwsA(isA<StateError>()));
  });

  test('sticky stop does not break later launches', () async {
    final client = createClient();
    addTearDown(client.dispose);

    await client.initialize(
      type: 'flutter',
      targetId: 'local',
      adapterCommand: r'${extensionPath}/bin/fake',
      extensionId: 'ext.fake',
    );

    await client.launch(
      sessionId: 'stop-s1',
      configuration: {'type': 'flutter', 'id': 'main', 'name': 'Main'},
    );
    await client.stop('stop-s1');
    try {
      await client.waitExited('stop-s1').timeout(const Duration(seconds: 3));
    } on TimeoutException {
      // Natural exit before stop is fine.
    }

    await client.launch(
      sessionId: 'stop-s2',
      configuration: {'type': 'flutter', 'id': 'main', 'name': 'Main'},
    );
    final exited = await client.waitExited('stop-s2').timeout(
      const Duration(seconds: 5),
    );
    expect(exited.exitCode, 0);
  });
}

class _CapturingSink implements IOSink {
  _CapturingSink(this._lines);

  final StreamController<String> _lines;

  @override
  Encoding encoding = utf8;

  @override
  void add(List<int> data) {
    _lines.add(utf8.decode(data));
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future addStream(Stream<List<int>> stream) async {
    await for (final chunk in stream) {
      add(chunk);
    }
  }

  @override
  Future close() async {}

  @override
  Future get done => Future.value();

  @override
  Future flush() async {}

  @override
  void write(Object? object) {
    writeln(object);
  }

  @override
  void writeAll(Iterable objects, [String separator = '']) {
    write(objects.join(separator));
  }

  @override
  void writeCharCode(int charCode) {
    write(String.fromCharCode(charCode));
  }

  @override
  void writeln([Object? object = '']) {
    final text = object?.toString() ?? '';
    _lines.add(text.endsWith('\n') ? text.substring(0, text.length - 1) : text);
  }
}

class _NullSink implements IOSink {
  @override
  Encoding encoding = utf8;

  @override
  void add(List<int> data) {}

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future addStream(Stream<List<int>> stream) async {}

  @override
  Future close() async {}

  @override
  Future get done => Future.value();

  @override
  Future flush() async {}

  @override
  void write(Object? object) {}

  @override
  void writeAll(Iterable objects, [String separator = '']) {}

  @override
  void writeCharCode(int charCode) {}

  @override
  void writeln([Object? object = '']) {}
}
