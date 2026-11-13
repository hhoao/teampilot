import 'dart:async';
import 'dart:io';

import 'package:acp_proxy/acp_proxy.dart';
import 'package:acpd/acpd.dart';
import 'package:acpd_test/acpd_test.dart';
import 'package:test/test.dart';

void main() {
  test('disconnect leaves the upstream running', () async {
    final env = await _startEnv();
    final phone = env.connect();
    final sessionId = await env.openSession(phone);

    await phone.pair.left.close();
    await _tick();

    expect(env.fake.closeCount, 0);
    expect(env.fake.alive, isTrue);

    // pair.left.close() does not complete the agent read side.
    await phone.pair.right.close();
    await _tick();
    expect(env.fake.closeCount, 0);
    expect(env.fake.alive, isTrue);
    expect(env.book.connectionFor(sessionId), isNull);
    expect(env.agent.disconnectedSince[sessionId], isNotNull);
  });

  test('load of a live upstream replays spooled updates', () async {
    final env = await _startEnv();
    final phone = env.connect();
    final sessionId = await env.openSession(phone);
    await phone.pair.left.close();
    await phone.pair.right.close();
    await _tick();

    env.fake.updateEvents.add({
      'sessionUpdate': 'agent_message_chunk',
      'content': {'type': 'text', 'text': 'while-away'},
    });
    await _tick();

    final again = env.connect();
    await again.client.client.loadSession(
      LoadSessionRequest(sessionId: sessionId, cwd: '/work', meta: _meta()),
    );

    expect(env.fake.openLoadCount, 0);
    expect(again.updates, hasLength(1));
    final update = again.updates.single.update;
    expect(update, isA<AgentMessageChunk>());
    final chunk = update as AgentMessageChunk;
    expect((chunk.chunk.content as TextContentBlock).text, 'while-away');
    expect(env.agent.disconnectedSince.containsKey(sessionId), isFalse);
  });

  test('openLoad throwing does not call openNew', () async {
    final fake = FakeUpstream()..openLoadError = StateError('load failed');
    final env = await _startEnv(fake: fake);
    final phone = env.connect();

    await expectLater(
      phone.client.client.loadSession(
        LoadSessionRequest(sessionId: 'missing', cwd: '/work', meta: _meta()),
      ),
      throwsA(isA<RpcError>()),
    );
    expect(fake.openLoadCount, 1);
    expect(fake.openNewCount, 0);
    expect(env.agent.upstreams, isEmpty);
  });

  test('one open turn absorbs a repeated prompt until stop', () async {
    final env = await _startEnv();
    final phone = env.connect();
    final sessionId = await env.openSession(phone);

    final first = phone.client.client.prompt(
      PromptRequest.text(sessionId, 'hello'),
    );
    final second = phone.client.client.prompt(
      PromptRequest.text(sessionId, 'hello'),
    );
    await _tick();
    expect(env.fake.promptCount, 1);
    expect(env.book.turnInProgress(sessionId), isTrue);

    await expectLater(
      phone.client.client.prompt(PromptRequest.text(sessionId, 'other')),
      throwsA(
        isA<RpcError>().having(
          (error) => error.code,
          'code',
          ErrorCode.invalidParams.code,
        ),
      ),
    );
    expect(env.fake.promptCount, 1);

    env.fake.updateEvents.add({
      'sessionUpdate': 'stop',
      'stopReason': 'end_turn',
    });
    final responses = await Future.wait([first, second]);
    expect(responses.map((response) => response.stopReason), [
      StopReason.endTurn,
      StopReason.endTurn,
    ]);
    expect(env.book.turnInProgress(sessionId), isFalse);

    final third = phone.client.client.prompt(
      PromptRequest.text(sessionId, 'hello'),
    );
    await _tick();
    expect(env.fake.promptCount, 2);
    env.fake.updateEvents.add({
      'sessionUpdate': 'stop',
      'stopReason': 'end_turn',
    });
    expect((await third).stopReason, StopReason.endTurn);
  });

  test('a second load closes the first phone leg', () async {
    final env = await _startEnv();
    final first = env.connect();
    final sessionId = await env.openSession(first);
    final second = env.connect();

    await second.client.client.loadSession(
      LoadSessionRequest(sessionId: sessionId, cwd: '/work', meta: _meta()),
    );

    expect(first.served.connection.isClosed, isTrue);
    expect(
      () => first.pair.right.send(
        const TransportFrame.single(RpcNotification(method: 'x')),
      ),
      throwsStateError,
    );
    expect(env.fake.closeCount, 0);
    expect(env.fake.alive, isTrue);
    expect(env.fake.openLoadCount, 0);
    expect(env.book.connectionFor(sessionId), isNotNull);
  });

  test('fullAccess allows a permission while the phone is gone', () async {
    final env = await _startEnv();
    final phone = env.connect();
    final sessionId = await env.openSession(phone);
    await _dropPhone(phone);

    env.fake.clientRequestEvents.add(
      AcpClientRequest(
        id: 'perm-1',
        method: 'session/request_permission',
        params: _permissionParams(sessionId),
      ),
    );
    await _tick();

    expect(env.fake.completions['perm-1'], {
      'outcome': 'selected',
      'optionId': 'allow-always',
    });
    expect(env.fake.promptCount, 0);
    expect(env.fake.closeCount, 0);
  });

  test('ask permissions cancel when the phone stays away', () async {
    final env = await _startEnv(permissionTimeout: Duration.zero);
    final phone = env.connect();
    final sessionId = await env.openSession(phone, permissionPolicy: 'ask');
    await _dropPhone(phone);

    env.fake.clientRequestEvents.add(
      AcpClientRequest(
        id: 'perm-ask',
        method: 'session/request_permission',
        params: _permissionParams(sessionId),
      ),
    );
    await _tick();

    expect(env.fake.completions['perm-ask'], {'outcome': 'cancelled'});
    expect(env.fake.closeCount, 0);
    expect(env.fake.alive, isTrue);
    expect(env.agent.permissionPending(sessionId), isFalse);
  });

  test('a cursor question is not invented while the phone is gone', () async {
    const timeout = Duration(milliseconds: 40);
    final env = await _startEnv(permissionTimeout: timeout);
    final phone = env.connect();
    final sessionId = await env.openSession(phone);
    await _dropPhone(phone);

    env.fake.clientRequestEvents.add(
      AcpClientRequest(
        id: 'q1',
        method: 'cursor/ask_question',
        params: {
          'sessionId': sessionId,
          'questions': [
            {
              'prompt': 'Pick one',
              'options': [
                {'id': 'a', 'label': 'A'},
              ],
            },
          ],
        },
      ),
    );

    expect(env.fake.completions.containsKey('q1'), isFalse);
    expect(env.agent.permissionPending(sessionId), isTrue);
    expect(env.agent.idleClockRunning(sessionId), isFalse);

    await Future<void>.delayed(timeout + const Duration(milliseconds: 30));
    expect(env.fake.completions['q1'], {'outcome': 'cancelled'});
    expect(env.fake.completions['q1']!.containsKey('answers'), isFalse);
    expect(env.agent.permissionPending(sessionId), isFalse);
    expect(env.fake.closeCount, 0);
  });

  test('invalid launch meta is invalid params and starts nothing', () async {
    final env = await _startEnv();
    final phone = env.connect();
    var connects = 0;
    env.agent.connectNew =
        ({
          required AcpProxyLaunchMeta meta,
          required String cwd,
          required List<Map<String, Object?>> mcpServers,
        }) async {
          connects++;
          return env.fake;
        };

    await expectLater(
      phone.client.client.newSession(
        NewSessionRequest(
          cwd: '/work',
          meta: {
            'teampilot': {'cli': 'codex'},
          },
        ),
      ),
      throwsA(
        isA<RpcError>().having(
          (error) => error.code,
          'code',
          ErrorCode.invalidParams.code,
        ),
      ),
    );
    expect(connects, 0);
    expect(env.fake.openNewCount, 0);
    expect(env.agent.upstreams, isEmpty);
    expect(
      Directory('${env.root.path}/acp-proxy/sessions').existsSync(),
      isFalse,
    );
  });

  test('openNew failure closes the upstream and keeps no session', () async {
    final fake = FakeUpstream()..openNewError = StateError('cli failed');
    final env = await _startEnv(fake: fake);
    final phone = env.connect();

    await expectLater(env.openSession(phone), throwsA(isA<RpcError>()));
    expect(fake.openNewCount, 1);
    expect(fake.closeCount, 1);
    expect(env.agent.upstreams, isEmpty);
    expect(
      Directory('${env.root.path}/acp-proxy/sessions').existsSync(),
      isFalse,
    );
  });

  test(
    'cancel waits for the upstream stop and close deletes the spool',
    () async {
      final env = await _startEnv();
      final phone = env.connect();
      final sessionId = await env.openSession(phone);
      final pending = phone.client.client.prompt(
        PromptRequest.text(sessionId, 'hello'),
      );
      await _tick();

      phone.client.client.cancel(sessionId);
      await _tick();
      expect(env.fake.cancelCount, 1);
      expect(env.book.turnInProgress(sessionId), isTrue);
      expect(env.fake.closeCount, 0);

      env.fake.updateEvents.add({
        'sessionUpdate': 'stop',
        'stopReason': 'cancelled',
      });
      expect((await pending).stopReason, StopReason.cancelled);
      expect(env.book.turnInProgress(sessionId), isFalse);

      env.fake.updateEvents.add({
        'sessionUpdate': 'agent_message_chunk',
        'content': {'type': 'text', 'text': 'kept'},
      });
      await phone.client.client.closeSession(
        CloseSessionRequest(sessionId: sessionId),
      );
      expect(env.fake.closeCount, 1);
      expect(env.fake.alive, isFalse);
      expect(await env.spool.readAll(sessionId), isEmpty);
      expect(env.book.turnInProgress(sessionId), isFalse);
    },
  );
}

Map<String, Object?> _meta({String permissionPolicy = 'fullAccess'}) => {
  'teampilot': {
    'cli': 'claude',
    'executable': '/usr/local/bin/claude',
    'args': ['--acp'],
    'env': {'HOME': '/home/runner'},
    'permissionPolicy': permissionPolicy,
  },
};

Map<String, Object?> _permissionParams(String sessionId) => {
  'sessionId': sessionId,
  'toolCall': {'toolCallId': 'call-1'},
  'options': [
    {
      'optionId': 'allow-always',
      'name': 'Always allow',
      'kind': 'allow_always',
    },
    {'optionId': 'reject-once', 'name': 'Reject', 'kind': 'reject_once'},
  ],
};

Future<void> _tick() => Future<void>.delayed(Duration.zero);

Future<void> _dropPhone(_Phone phone) async {
  await phone.pair.left.close();
  await phone.pair.right.close();
  await _tick();
}

class _Env {
  _Env({
    required this.root,
    required this.agent,
    required this.book,
    required this.spool,
    required this.fake,
  });

  final Directory root;
  final AcpProxyAgent agent;
  final AcpProxySessionBook book;
  final AcpProxySpool spool;
  final FakeUpstream fake;

  _Phone connect() {
    final pair = MemoryTransportPair();
    final updates = <SessionUpdateNotification>[];
    final client = ClientRole()
        .onSessionUpdate((_, notification) => updates.add(notification))
        .connect(pair.left);
    final served = agent.serve(pair.right);
    addTearDown(() async {
      if (!client.connection.isClosed) await client.close();
      if (!served.connection.isClosed) await served.close();
      await pair.close();
    });
    return _Phone(pair: pair, client: client, served: served, updates: updates);
  }

  Future<String> openSession(
    _Phone phone, {
    String permissionPolicy = 'fullAccess',
  }) async {
    final initialized = await phone.client.client.initialize(
      const InitializeRequest(protocolVersion: ProtocolVersion.v1),
    );
    expect(initialized.protocolVersion, ProtocolVersion.v1);
    expect(fake.openNewCount, 0);
    final created = await phone.client.client.newSession(
      NewSessionRequest(
        cwd: '/work',
        meta: _meta(permissionPolicy: permissionPolicy),
      ),
    );
    expect(created.sessionId, fake.sessionId);
    expect(book.connectionFor(created.sessionId), isNotNull);
    return created.sessionId;
  }
}

class _Phone {
  _Phone({
    required this.pair,
    required this.client,
    required this.served,
    required this.updates,
  });

  final MemoryTransportPair pair;
  final ClientConnection client;
  final AgentConnection served;
  final List<SessionUpdateNotification> updates;
}

Future<_Env> _startEnv({
  Duration? permissionTimeout,
  FakeUpstream? fake,
}) async {
  final root = await Directory.systemTemp.createTemp('acp-proxy-agent');
  addTearDown(() => root.delete(recursive: true));
  final upstream = fake ?? FakeUpstream();
  final book = AcpProxySessionBook();
  final spool = AcpProxySpool(root: root);
  final agent = AcpProxyAgent(
    endpointCli: 'claude',
    book: book,
    spool: spool,
    upstreams: {},
    permissionTimeout: permissionTimeout ?? acpProxyPermissionTimeout,
  );
  agent.connectNew =
      ({
        required AcpProxyLaunchMeta meta,
        required String cwd,
        required List<Map<String, Object?>> mcpServers,
      }) async {
        return upstream;
      };
  addTearDown(() async {
    await upstream.updateEvents.close();
    await upstream.clientRequestEvents.close();
  });
  return _Env(
    root: root,
    agent: agent,
    book: book,
    spool: spool,
    fake: upstream,
  );
}

class FakeUpstream implements AcpUpstream {
  FakeUpstream({this.sessionId = 'sess-1'});

  final String sessionId;
  var alive = true;
  var openNewCount = 0;
  var openLoadCount = 0;
  var promptCount = 0;
  var closeCount = 0;
  var cancelCount = 0;
  Object? openNewError;
  Object? openLoadError;

  final updateEvents = StreamController<Map<String, Object?>>.broadcast(
    sync: true,
  );
  final clientRequestEvents = StreamController<AcpClientRequest>.broadcast(
    sync: true,
  );
  final completions = <Object, Map<String, Object?>>{};

  @override
  Future<String> openNew({
    required AcpProxyLaunchMeta meta,
    required String cwd,
    required List<Map<String, Object?>> mcpServers,
  }) async {
    openNewCount++;
    final error = openNewError;
    if (error != null) throw error;
    return sessionId;
  }

  @override
  Future<void> openLoad({
    required String sessionId,
    required String cwd,
  }) async {
    openLoadCount++;
    final error = openLoadError;
    if (error != null) throw error;
  }

  @override
  Future<void> prompt(String text) async {
    promptCount++;
  }

  @override
  Future<void> cancel() async {
    cancelCount++;
  }

  @override
  Future<void> close() async {
    closeCount++;
    alive = false;
  }

  @override
  Stream<Map<String, Object?>> get updates => updateEvents.stream;

  @override
  Stream<AcpClientRequest> get clientRequests => clientRequestEvents.stream;

  @override
  void completeClientRequest(Object id, Map<String, Object?> result) {
    completions[id] = result;
  }
}
