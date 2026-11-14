import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:acp_proxy/acp_proxy.dart';
import 'package:acpd/acpd.dart';
import 'package:acpd_test/acpd_test.dart';
import 'package:test/test.dart';

void main() {
  test('initialize advertises loadSession and does not spawn a CLI', () async {
    final env = await _startEnv();
    final phone = env.connect();

    final initialized = await phone.client.client.initialize(
      const InitializeRequest(protocolVersion: ProtocolVersion.v1),
    );

    expect(initialized.protocolVersion, ProtocolVersion.v1);
    expect(initialized.agentCapabilities?.loadSession, isTrue);
    expect(initialized.agentCapabilities?.sessionCapabilities?.resume, isNull);
    expect(env.fake.openNewCount, 0);
  });

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

  test('reconnect delivers the spooled backlog before the live tail', () async {
    final env = await _startEnv();
    final first = env.connect();
    final sessionId = await env.openSession(first);
    env.fake.updateEvents.add(_chunk('backlog'));
    await _tick();

    final second = env.connect();
    final closed = first.served.connection.onClose.first;
    final load = second.client.client.loadSession(
      LoadSessionRequest(sessionId: sessionId, cwd: '/work', meta: _meta()),
    );
    await closed;
    env.fake.updateEvents.add(_chunk('live'));
    await load;

    expect(_texts(second), ['backlog', 'live']);
  });

  test('a torn spool line does not drop the previous phone leg', () async {
    final env = await _startEnv();
    final first = env.connect();
    final sessionId = await env.openSession(first);
    final connectionId = env.book.connectionFor(sessionId);
    File(
      '${env.root.path}/acp-proxy/sessions/$sessionId/updates.jsonl',
    ).writeAsStringSync('not-json\n', mode: FileMode.append, flush: true);

    final second = env.connect();
    await expectLater(
      second.client.client.loadSession(
        LoadSessionRequest(sessionId: sessionId, cwd: '/work', meta: _meta()),
      ),
      throwsA(isA<RpcError>()),
    );

    expect(first.served.connection.isClosed, isFalse);
    expect(env.book.connectionFor(sessionId), connectionId);
    expect(
      () => first.pair.right.send(
        const TransportFrame.single(RpcNotification(method: 'x')),
      ),
      returnsNormally,
    );
  });

  test('updates emitted inside openLoad play before the spool tail', () async {
    final env = await _startEnv();
    final phone = env.connect();
    final sessionId = await env.openSession(phone);
    env.fake.updateEvents.add(_chunk('from-spool'));
    await _tick();
    await _dropPhone(phone);

    final revived = FakeUpstream(sessionId: sessionId);
    addTearDown(() async {
      await revived.updateEvents.close();
      await revived.clientRequestEvents.close();
    });
    revived.onOpenLoad = () {
      revived.updateEvents.add(_chunk('from-cli'));
    };
    env.fake.alive = false;
    env.agent.connectNew =
        ({
          required AcpProxyLaunchMeta meta,
          required String cwd,
          required List<Map<String, Object?>> mcpServers,
        }) async {
          return revived;
        };

    final again = env.connect();
    await again.client.client.loadSession(
      LoadSessionRequest(sessionId: sessionId, cwd: '/work', meta: _meta()),
    );

    expect(revived.openLoadCount, 1);
    expect(env.fake.openLoadCount, 0);
    expect(_texts(again), ['from-cli', 'from-spool']);
  });

  test('later live load keeps CLI history ahead of the spool', () async {
    final env = await _startEnv();
    final phone = env.connect();
    final sessionId = await env.openSession(phone);
    env.fake.updateEvents.add(_chunk('from-spool'));
    await _tick();
    await _dropPhone(phone);

    final revived = FakeUpstream(sessionId: sessionId);
    addTearDown(() async {
      await revived.updateEvents.close();
      await revived.clientRequestEvents.close();
    });
    revived.onOpenLoad = () {
      revived.updateEvents.add(_chunk('from-cli'));
    };
    env.fake.alive = false;
    env.agent.connectNew =
        ({
          required AcpProxyLaunchMeta meta,
          required String cwd,
          required List<Map<String, Object?>> mcpServers,
        }) async {
          return revived;
        };

    final again = env.connect();
    await again.client.client.loadSession(
      LoadSessionRequest(sessionId: sessionId, cwd: '/work', meta: _meta()),
    );
    expect(_texts(again), ['from-cli', 'from-spool']);
    await _dropPhone(again);

    final later = env.connect();
    await later.client.client.loadSession(
      LoadSessionRequest(sessionId: sessionId, cwd: '/work', meta: _meta()),
    );

    expect(revived.openLoadCount, 1);
    expect(_texts(later), ['from-cli', 'from-spool']);
  });

  test('a torn read keeps CLI history for the next load', () async {
    final env = await _startEnv();
    final first = env.connect();
    final sessionId = await env.openSession(first);
    final connectionId = env.book.connectionFor(sessionId);
    env.fake.updateEvents.add(_chunk('from-spool'));
    await _tick();
    File(
      '${env.root.path}/acp-proxy/sessions/$sessionId/updates.jsonl',
    ).writeAsStringSync('not-json\n', mode: FileMode.append, flush: true);

    final revived = FakeUpstream(sessionId: sessionId);
    addTearDown(() async {
      await revived.updateEvents.close();
      await revived.clientRequestEvents.close();
    });
    var emitted = false;
    revived.onOpenLoad = () {
      if (emitted) return;
      emitted = true;
      revived.updateEvents.add(_chunk('from-cli'));
    };
    env.fake.alive = false;
    env.agent.connectNew =
        ({
          required AcpProxyLaunchMeta meta,
          required String cwd,
          required List<Map<String, Object?>> mcpServers,
        }) async {
          return revived;
        };

    final second = env.connect();
    await expectLater(
      second.client.client.loadSession(
        LoadSessionRequest(sessionId: sessionId, cwd: '/work', meta: _meta()),
      ),
      throwsA(isA<RpcError>()),
    );
    expect(first.served.connection.isClosed, isFalse);
    expect(env.book.connectionFor(sessionId), connectionId);

    final third = env.connect();
    await third.client.client.loadSession(
      LoadSessionRequest(sessionId: sessionId, cwd: '/work', meta: _meta()),
    );

    expect(_texts(third), ['from-cli', 'from-spool']);
  });

  test('a failed spool replace keeps the transcript and CLI history', () async {
    final env = await _startEnv();
    final first = env.connect();
    final sessionId = await env.openSession(first);
    final connectionId = env.book.connectionFor(sessionId);
    env.fake.updateEvents.add(_chunk('from-spool'));
    await _tick();
    final transcript = File(
      '${env.root.path}/acp-proxy/sessions/$sessionId/updates.jsonl',
    );

    final revived = FakeUpstream(sessionId: sessionId);
    addTearDown(() async {
      await revived.updateEvents.close();
      await revived.clientRequestEvents.close();
    });
    var emitted = false;
    revived.onOpenLoad = () {
      if (emitted) return;
      emitted = true;
      revived.updateEvents.add(_chunk('from-cli'));
    };
    env.fake.alive = false;
    env.agent.connectNew =
        ({
          required AcpProxyLaunchMeta meta,
          required String cwd,
          required List<Map<String, Object?>> mcpServers,
        }) async {
          return revived;
        };

    final limits = _FileGrowthLimit();
    addTearDown(limits.restore);
    final second = env.connect();
    limits.block();
    try {
      await expectLater(
        second.client.client.loadSession(
          LoadSessionRequest(sessionId: sessionId, cwd: '/work', meta: _meta()),
        ),
        throwsA(isA<RpcError>()),
      );
    } finally {
      limits.restore();
    }

    expect(first.served.connection.isClosed, isFalse);
    expect(env.book.connectionFor(sessionId), connectionId);
    expect(transcript.readAsStringSync(), contains('from-spool'));

    final third = env.connect();
    await third.client.client.loadSession(
      LoadSessionRequest(sessionId: sessionId, cwd: '/work', meta: _meta()),
    );
    expect(_texts(third), ['from-cli', 'from-spool']);
  });

  test('session new keeps an update emitted inside openNew', () async {
    final fake = FakeUpstream();
    fake.onOpenNew = () {
      fake.updateEvents.add(_chunk('during-new'));
    };
    final env = await _startEnv(fake: fake);
    final phone = env.connect();

    await env.openSession(phone);

    expect(_texts(phone), ['during-new']);
    final stored = await env.spool.readAll(fake.sessionId);
    expect(
      stored.map((update) => update['sessionUpdate']),
      contains('agent_message_chunk'),
    );
  });
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

Map<String, Object?> _chunk(String text) => {
  'sessionUpdate': 'agent_message_chunk',
  'content': {'type': 'text', 'text': text},
};

List<String> _texts(_Phone phone) => [
  for (final notification in phone.updates)
    if (notification.update is AgentMessageChunk)
      ((notification.update as AgentMessageChunk).chunk.content
              as TextContentBlock)
          .text,
];

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
  void Function()? onOpenNew;
  void Function()? onOpenLoad;

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
    onOpenNew?.call();
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
    onOpenLoad?.call();
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

final class _RLimit extends Struct {
  @Uint64()
  external int cur;

  @Uint64()
  external int max;
}

typedef _SignalNative =
    Pointer<NativeFunction<Void Function(Int32)>> Function(
      Int32,
      Pointer<NativeFunction<Void Function(Int32)>>,
    );
typedef _SignalDart =
    Pointer<NativeFunction<Void Function(Int32)>> Function(
      int,
      Pointer<NativeFunction<Void Function(Int32)>>,
    );

/// Stops file growth so a truncate-then-write leaves an empty transcript.
class _FileGrowthLimit {
  _FileGrowthLimit() {
    final libc = DynamicLibrary.open('libc.so.6');
    _setrlimit = libc
        .lookupFunction<
          Int32 Function(Int32, Pointer<_RLimit>),
          int Function(int, Pointer<_RLimit>)
        >('setrlimit');
    _getrlimit = libc
        .lookupFunction<
          Int32 Function(Int32, Pointer<_RLimit>),
          int Function(int, Pointer<_RLimit>)
        >('getrlimit');
    _malloc = libc
        .lookupFunction<
          Pointer<Void> Function(IntPtr),
          Pointer<Void> Function(int)
        >('malloc');
    _free = libc
        .lookupFunction<
          Void Function(Pointer<Void>),
          void Function(Pointer<Void>)
        >('free');
    _signal = libc.lookupFunction<_SignalNative, _SignalDart>('signal');
    _limit = _malloc(sizeOf<_RLimit>()).cast<_RLimit>();
    _getrlimit(_rlimitFsize, _limit);
    _savedCur = _limit.ref.cur;
    _savedMax = _limit.ref.max;
  }

  static const _rlimitFsize = 1;
  static const _sigxfsz = 25;

  late final int Function(int, Pointer<_RLimit>) _setrlimit;
  late final int Function(int, Pointer<_RLimit>) _getrlimit;
  late final Pointer<Void> Function(int) _malloc;
  late final void Function(Pointer<Void>) _free;
  late final _SignalDart _signal;
  late final Pointer<_RLimit> _limit;
  late final int _savedCur;
  late final int _savedMax;
  Pointer<NativeFunction<Void Function(Int32)>>? _previousSignal;
  var _blocked = false;
  var _restored = false;

  void block() {
    // SIGXFSZ would kill the process when a write passes the limit.
    _previousSignal = _signal(_sigxfsz, Pointer.fromAddress(1));
    _limit.ref.cur = 0;
    _limit.ref.max = _savedMax;
    if (_setrlimit(_rlimitFsize, _limit) != 0) {
      throw StateError('setrlimit failed');
    }
    _blocked = true;
  }

  void restore() {
    if (_restored) return;
    _restored = true;
    if (_blocked) {
      _limit.ref.cur = _savedCur;
      _limit.ref.max = _savedMax;
      _setrlimit(_rlimitFsize, _limit);
      final previous = _previousSignal;
      if (previous != null) _signal(_sigxfsz, previous);
    }
    _free(_limit.cast());
  }
}
