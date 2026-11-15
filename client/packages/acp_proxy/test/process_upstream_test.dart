import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:acp_proxy/acp_proxy.dart';
import 'package:acpd/acpd.dart';
import 'package:test/test.dart';

void main() {
  test(
    'spawn drops an empty env value and uses the session directory',
    () async {
      final harness = await _Harness.create();
      final upstream = await harness.start(
        mode: 'exit',
        env: const {'KEEP': 'yes', 'DROP': ''},
        parent: const {'KEEP': 'old', 'DROP': 'secret', 'OTHER': '1'},
      );
      addTearDown(() => upstream.close());

      final report = await harness.readReport();
      expect(report['KEEP'], 'yes');
      expect(report['OTHER'], '1');
      expect(report['DROP'], isNull);
      expect(report['cwd'], harness.work.path);
      expect(harness.traceText(), isNot(contains('secret')));
      expect(harness.reportText(), isNot(contains('secret')));
      expect(_methods(harness), ['initialize']);
    },
  );

  test('initialize advertises the proxy and does not open a session', () async {
    final harness = await _Harness.create();
    final upstream = await harness.start(mode: 'sleep');
    addTearDown(() => upstream.close());

    expect(upstream.alive, isTrue);
    expect(_methods(harness), ['initialize']);
    final params = _params(harness, 'initialize');
    expect(params['protocolVersion'], 1);
    expect(params['clientInfo'], {
      'name': 'teampilot-acp-proxy',
      'version': acpProxyVersion,
    });
    final capabilities = params['clientCapabilities'] as Map;
    expect(capabilities['terminal'], isFalse);
    final fs = capabilities['fs'] as Map;
    expect(fs['readTextFile'], isFalse);
    expect(fs['writeTextFile'], isFalse);
  });

  test('authenticate runs only when the launch meta names a method', () async {
    final skipped = await _Harness.create();
    final plain = await skipped.start(mode: 'sleep');
    addTearDown(() => plain.close());
    expect(_methods(skipped), isNot(contains('authenticate')));

    final named = await _Harness.create();
    final authed = await named.start(
      mode: 'sleep',
      authenticateMethodId: 'oauth',
    );
    addTearDown(() => authed.close());
    expect(_methods(named), ['initialize', 'authenticate']);
    expect(_params(named, 'authenticate')['methodId'], 'oauth');
  });

  test(
    'openNew returns the cli session and sends cwd plus mcp servers',
    () async {
      final harness = await _Harness.create();
      final upstream = await harness.start(mode: 'sleep');
      addTearDown(() => upstream.close());
      const mcp = {
        'name': 'docs',
        'command': 'echo',
        'args': ['hi'],
        'env': <Object?>[],
      };

      final sessionId = await upstream.openNew(
        meta: harness.meta(),
        cwd: '/work',
        mcpServers: const [mcp],
      );

      expect(sessionId, 'cli-sess');
      expect(_methods(harness), ['initialize', 'session/new']);
      final params = _params(harness, 'session/new');
      expect(params['cwd'], '/work');
      expect(params['mcpServers'], [mcp]);

      await upstream.cancel();
      await _until(() => _methods(harness).contains('session/cancel'));
      expect(_methods(harness), contains('session/cancel'));
    },
  );

  test('openLoad failure does not send session/new', () async {
    final harness = await _Harness.create();
    final upstream = await harness.start(
      mode: 'load-fail',
      mcpServers: const [
        {
          'name': 'docs',
          'command': 'echo',
          'args': <Object?>[],
          'env': <Object?>[],
        },
      ],
    );
    addTearDown(() => upstream.close());

    await expectLater(
      upstream.openLoad(sessionId: 'kept', cwd: '/work'),
      throwsA(isA<RpcError>()),
    );
    expect(_methods(harness), ['initialize', 'session/load']);
    final params = _params(harness, 'session/load');
    expect(params['sessionId'], 'kept');
    expect(params['cwd'], '/work');
    expect((params['mcpServers'] as List).single, containsPair('name', 'docs'));
  });

  test(
    'prompt emits the inner update and a stop from the prompt result',
    () async {
      final harness = await _Harness.create();
      final upstream = await harness.start(mode: 'sleep');
      addTearDown(() => upstream.close());
      await upstream.openNew(
        meta: harness.meta(),
        cwd: harness.work.path,
        mcpServers: const [],
      );
      final updates = <Map<String, Object?>>[];
      final subscription = upstream.updates.listen(updates.add);
      addTearDown(subscription.cancel);

      await upstream.prompt('hello there');
      await _until(() => updates.length >= 2);

      expect(_params(harness, 'session/prompt')['prompt'], [
        {'type': 'text', 'text': 'hello there'},
      ]);
      expect(updates, [
        {
          'sessionUpdate': 'agent_message_chunk',
          'content': {'type': 'text', 'text': 'hi'},
        },
        {'sessionUpdate': 'stop', 'stopReason': 'end_turn'},
      ]);
    },
  );

  test('a permission request is answered back to the cli', () async {
    final harness = await _Harness.create();
    final upstream = await harness.start(mode: 'permission');
    addTearDown(() => upstream.close());
    await upstream.openNew(
      meta: harness.meta(),
      cwd: harness.work.path,
      mcpServers: const [],
    );
    final requests = upstream.clientRequests.listen((request) {
      upstream.completeClientRequest(request.id, {
        'outcome': 'selected',
        'optionId': 'allow-always',
      });
    });
    addTearDown(requests.cancel);

    await upstream.prompt('ship it');

    final answered = jsonDecode(
      File('${harness.report.path}.permission').readAsStringSync(),
    );
    expect(answered, {'outcome': 'selected', 'optionId': 'allow-always'});
  });

  test('cli exit marks the upstream dead and closes updates', () async {
    final harness = await _Harness.create();
    final upstream = await harness.start(mode: 'exit');
    addTearDown(() => upstream.close());
    final done = upstream.updates.toList();

    await _until(() => !upstream.alive);

    expect(upstream.alive, isFalse);
    expect(await done, isEmpty);
  });

  test('close kills a cli that stays up, including its child', () async {
    final harness = await _Harness.create();
    final upstream = await harness.start(
      mode: 'orphan',
      parent: Platform.environment,
      killGrace: const Duration(milliseconds: 200),
    );
    final report = await harness.readReport();
    final grandFile = File('${harness.report.path}.grand');
    await _until(grandFile.existsSync);
    final grandPid = int.parse(grandFile.readAsStringSync().trim());

    await upstream.close();

    expect(upstream.alive, isFalse);
    await _until(
      () => !_alivePid(report['pid']! as int) && !_alivePid(grandPid),
    );
    expect(_alivePid(report['pid']! as int), isFalse);
    expect(_alivePid(grandPid), isFalse);
  });

  test('a cli that never answers initialize is killed', () async {
    final harness = await _Harness.create();

    await expectLater(
      harness.start(
        mode: 'silent',
        handshakeTimeout: const Duration(milliseconds: 300),
      ),
      throwsA(isA<TimeoutException>()),
    );

    final report = await harness.readReport();
    await _until(() => !_alivePid(report['pid']! as int));
    expect(_alivePid(report['pid']! as int), isFalse);
  });

  test('stderr from the cli does not block the handshake', () async {
    final harness = await _Harness.create();
    final upstream = await harness.start(
      mode: 'stderr-flood',
      handshakeTimeout: const Duration(seconds: 5),
    );
    addTearDown(() => upstream.close());

    expect(upstream.alive, isTrue);
    expect(_methods(harness), ['initialize']);
  });
}

List<String> _methods(_Harness harness) => [
  for (final entry in _trace(harness.trace)) entry['method'] as String,
];

Map<String, Object?> _params(_Harness harness, String method) {
  final entry = _trace(
    harness.trace,
  ).firstWhere((item) => item['method'] == method);
  return Map<String, Object?>.from(entry['params']! as Map);
}

List<Map<String, Object?>> _trace(File file) {
  if (!file.existsSync()) return const [];
  return [
    for (final line in file.readAsLinesSync())
      if (line.isNotEmpty) Map<String, Object?>.from(jsonDecode(line) as Map),
  ];
}

bool _alivePid(int pid) => Directory('/proc/$pid').existsSync();

Future<void> _until(bool Function() done) async {
  for (var i = 0; i < 100; i++) {
    if (done()) return;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

class _Harness {
  _Harness(this.work, this.trace, this.report);

  final Directory work;
  final File trace;
  final File report;

  static Future<_Harness> create() async {
    final work = await Directory.systemTemp.createTemp('acp-proxy-cli');
    addTearDown(() async {
      if (work.existsSync()) await work.delete(recursive: true);
    });
    return _Harness(
      work,
      File('${work.path}/trace.jsonl'),
      File('${work.path}/report.json'),
    );
  }

  AcpProxyLaunchMeta meta({String? authenticateMethodId}) {
    return AcpProxyLaunchMeta(
      cli: 'claude',
      executable: Platform.resolvedExecutable,
      args: [_scriptPath(), 'sleep', trace.path, report.path],
      env: const {},
      permissionPolicy: AcpProxyPermissionPolicy.fullAccess,
      authenticateMethodId: authenticateMethodId,
    );
  }

  Future<AcpProcessUpstream> start({
    required String mode,
    Map<String, String> env = const {},
    Map<String, String>? parent,
    List<Map<String, Object?>> mcpServers = const [],
    String? authenticateMethodId,
    Duration handshakeTimeout = const Duration(seconds: 5),
    Duration killGrace = const Duration(seconds: 5),
  }) {
    return AcpProcessUpstream.start(
      meta: AcpProxyLaunchMeta(
        cli: 'claude',
        executable: Platform.resolvedExecutable,
        args: [_scriptPath(), mode, trace.path, report.path],
        env: env,
        permissionPolicy: AcpProxyPermissionPolicy.fullAccess,
        authenticateMethodId: authenticateMethodId,
      ),
      cwd: work.path,
      mcpServers: mcpServers,
      parentEnvironment: parent,
      handshakeTimeout: handshakeTimeout,
      killGrace: killGrace,
    );
  }

  Future<Map<String, Object?>> readReport() async {
    await _until(
      () => this.report.existsSync() && this.report.lengthSync() > 0,
    );
    return Map<String, Object?>.from(jsonDecode(reportText()) as Map);
  }

  String traceText() => trace.existsSync() ? trace.readAsStringSync() : '';

  String reportText() => report.existsSync() ? report.readAsStringSync() : '';
}

String _scriptPath() {
  final file = File('test/support/mini_acp_cli.dart');
  if (!file.existsSync()) {
    throw StateError('mini cli missing from ${Directory.current.path}');
  }
  return file.absolute.path;
}
