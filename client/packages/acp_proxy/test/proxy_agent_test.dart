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
    expect(env.fake.completions['q1'], {
      'outcome': {'outcome': 'cancelled'},
    });
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
    'idle reap matches session close and drops the installed upstream',
    () async {
      final env = await _startEnv();
      final phone = env.connect();
      final sessionId = await env.openSession(phone);
      expect(env.fake.updateEvents.hasListener, isTrue);
      expect(env.fake.clientRequestEvents.hasListener, isTrue);
      await _dropPhone(phone);

      final disconnectedAt = env.agent.disconnectedSince[sessionId];
      expect(disconnectedAt, isNotNull);
      await env.agent.reapIdle(
        now: disconnectedAt!.add(const Duration(minutes: 31)),
        idleTimeout: const Duration(minutes: 30),
      );

      expect(env.fake.closeCount, 1);
      expect(env.fake.alive, isFalse);
      expect(env.agent.upstreams.containsKey(sessionId), isFalse);
      expect(env.agent.disconnectedSince.containsKey(sessionId), isFalse);
      expect(env.book.sessionIds, isNot(contains(sessionId)));
      expect(env.book.turnInProgress(sessionId), isFalse);
      expect(
        Directory(
          '${env.root.path}/acp-proxy/sessions/$sessionId',
        ).existsSync(),
        isFalse,
      );
      expect(env.fake.updateEvents.hasListener, isFalse);
      expect(env.fake.clientRequestEvents.hasListener, isFalse);

      final again = env.connect();
      await expectLater(
        again.client.client.loadSession(
          LoadSessionRequest(sessionId: sessionId, cwd: '/work'),
        ),
        throwsA(isA<RpcError>()),
      );
      expect(env.fake.openLoadCount, 0);
      expect(env.agent.upstreams.containsKey(sessionId), isFalse);

      final replacement = FakeUpstream(sessionId: sessionId);
      addTearDown(() async {
        await replacement.updateEvents.close();
        await replacement.clientRequestEvents.close();
      });
      env.agent.connectNew =
          ({
            required AcpProxyLaunchMeta meta,
            required String cwd,
            required List<Map<String, Object?>> mcpServers,
          }) async {
            return replacement;
          };
      await again.client.client.loadSession(
        LoadSessionRequest(sessionId: sessionId, cwd: '/work', meta: _meta()),
      );
      expect(env.fake.openLoadCount, 0);
      expect(replacement.openLoadCount, 1);
      expect(env.agent.upstreams[sessionId], same(replacement));
    },
  );

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

  test(
    'failed spool delete keeps the session for the next idle tick',
    () async {
      final root = await Directory.systemTemp.createTemp('acp-proxy-agent');
      addTearDown(() => root.delete(recursive: true));
      final spool = _FailingDeleteSpool(root: root);
      final book = AcpProxySessionBook();
      final upstreams = <String, AcpUpstream>{};
      final agent = AcpProxyAgent(
        endpointCli: 'claude',
        book: book,
        spool: spool,
        upstreams: upstreams,
      );
      const meta = AcpProxyLaunchMeta(
        cli: 'claude',
        executable: '/usr/local/bin/claude',
        args: ['--acp'],
        env: {'TOKEN': 'super-secret'},
        permissionPolicy: AcpProxyPermissionPolicy.ask,
      );
      final now = DateTime.utc(2026, 11, 14, 12);
      final fakes = <String, FakeUpstream>{};

      Future<void> track(String sessionId) async {
        await spool.create(sessionId: sessionId, cwd: '/work', meta: meta);
        final upstream = FakeUpstream(sessionId: sessionId);
        fakes[sessionId] = upstream;
        upstreams[sessionId] = upstream;
        book.attach(sessionId: sessionId, connectionId: 'c-$sessionId');
        book.detach('c-$sessionId');
        agent.disconnectedSince[sessionId] = now.subtract(
          const Duration(minutes: 31),
        );
      }

      await track('s-1');
      await track('s-2');
      spool.fail.add('s-1');
      addTearDown(() async {
        for (final upstream in fakes.values) {
          if (!upstream.updateEvents.isClosed) {
            await upstream.updateEvents.close();
          }
          if (!upstream.clientRequestEvents.isClosed) {
            await upstream.clientRequestEvents.close();
          }
        }
      });

      await agent.reapIdle(now: now, idleTimeout: const Duration(minutes: 30));

      expect(book.sessionIds, contains('s-1'));
      expect(agent.disconnectedSince.containsKey('s-1'), isTrue);
      expect(fakes['s-1']!.closeCount, 1);
      final metaFile = File('${root.path}/acp-proxy/sessions/s-1/meta.json');
      expect(metaFile.existsSync(), isTrue);
      expect(metaFile.readAsStringSync(), contains('super-secret'));
      expect(book.sessionIds, isNot(contains('s-2')));
      expect(
        Directory('${root.path}/acp-proxy/sessions/s-2').existsSync(),
        isFalse,
      );
      expect(fakes['s-2']!.closeCount, 1);

      spool.fail.clear();
      await agent.reapIdle(now: now, idleTimeout: const Duration(minutes: 30));
      expect(book.sessionIds, isNot(contains('s-1')));
      expect(
        Directory('${root.path}/acp-proxy/sessions/s-1').existsSync(),
        isFalse,
      );
    },
  );

  test(
    'upstream done cancels the open turn and drops held cursor questions',
    () async {
      final env = await _startEnv();
      final phone = env.connect();
      final sessionId = await env.openSession(phone);
      final pending = phone.client.client.prompt(
        PromptRequest.text(sessionId, 'hello'),
      );
      unawaited(
        pending.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
      );
      await _tick();
      expect(env.book.turnInProgress(sessionId), isTrue);
      await _dropPhone(phone);

      env.fake.clientRequestEvents.add(
        AcpClientRequest(
          id: 'q-dead',
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
      await _tick();
      expect(env.agent.permissionPending(sessionId), isTrue);
      expect(env.agent.idleClockRunning(sessionId), isFalse);

      await env.fake.updateEvents.close();
      await _tick();

      expect(env.book.turnInProgress(sessionId), isFalse);
      expect(env.agent.permissionPending(sessionId), isFalse);
      expect(env.agent.idleClockRunning(sessionId), isTrue);
      expect(env.fake.completions['q-dead'], {
        'outcome': {'outcome': 'cancelled'},
      });

      final again = env.connect();
      await again.client.client.loadSession(
        LoadSessionRequest(sessionId: sessionId, cwd: '/work', meta: _meta()),
      );
      final next = again.client.client.prompt(
        PromptRequest.text(sessionId, 'other'),
      );
      await _tick();
      expect(env.fake.promptCount, 2);
      expect(env.book.turnInProgress(sessionId), isTrue);
      await again.client.client.closeSession(
        CloseSessionRequest(sessionId: sessionId),
      );
      expect((await next).stopReason, StopReason.cancelled);
    },
  );

  test('load closes a dead upstream before starting the next one', () async {
    final env = await _startEnv();
    final phone = env.connect();
    final sessionId = await env.openSession(phone);
    await _dropPhone(phone);
    env.fake.alive = false;

    final revived = FakeUpstream(sessionId: sessionId);
    addTearDown(() async {
      if (!revived.updateEvents.isClosed) await revived.updateEvents.close();
      if (!revived.clientRequestEvents.isClosed) {
        await revived.clientRequestEvents.close();
      }
    });
    var closeCountWhenConnecting = 0;
    env.agent.connectNew =
        ({
          required AcpProxyLaunchMeta meta,
          required String cwd,
          required List<Map<String, Object?>> mcpServers,
        }) async {
          closeCountWhenConnecting = env.fake.closeCount;
          return revived;
        };

    final again = env.connect();
    await again.client.client.loadSession(
      LoadSessionRequest(sessionId: sessionId, cwd: '/work', meta: _meta()),
    );

    expect(closeCountWhenConnecting, 1);
    expect(env.fake.closeCount, 1);
    expect(revived.openLoadCount, 1);
    expect(env.agent.upstreams[sessionId], same(revived));
  });

  test(
    'disconnected cursor notifications are acked and replayed as updates',
    () async {
      final env = await _startEnv();
      final phone = env.connect();
      final sessionId = await env.openSession(phone);
      await _dropPhone(phone);

      env.fake.clientRequestEvents.add(
        AcpClientRequest(
          id: 'todos',
          method: 'cursor/update_todos',
          params: {
            'todos': [
              {'id': '1', 'content': 'A', 'status': 'pending'},
            ],
            'merge': true,
          },
        ),
      );
      env.fake.clientRequestEvents.add(
        AcpClientRequest(
          id: 'task',
          method: 'cursor/task',
          params: {
            'toolCallId': 't1',
            'description': 'Explore',
            'subagentType': 'explore',
            'agentId': 'ag-1',
            'durationMs': 12,
          },
        ),
      );
      env.fake.clientRequestEvents.add(
        AcpClientRequest(
          id: 'image',
          method: 'cursor/generate_image',
          params: {
            'toolCallId': 'img-1',
            'description': 'icon',
            'filePath': '/tmp/icon.png',
          },
        ),
      );
      env.fake.clientRequestEvents.add(
        AcpClientRequest(
          id: 'bad-todos',
          method: 'cursor/update_todos',
          params: const {'todos': 'nope'},
        ),
      );
      env.fake.clientRequestEvents.add(
        AcpClientRequest(
          id: 'other',
          method: 'fs/read_text_file',
          params: const {'path': 'a.txt'},
        ),
      );
      await _tick();

      expect(env.fake.completions['todos'], {
        'outcome': {
          'outcome': 'accepted',
          'todos': [
            {'id': '1', 'content': 'A', 'status': 'pending'},
          ],
        },
      });
      expect(env.fake.completions['task'], {
        'outcome': {
          'outcome': 'completed',
          'agentId': 'ag-1',
          'durationMs': 12,
        },
      });
      expect(env.fake.completions['image'], {
        'outcome': {'outcome': 'generated', 'filePath': '/tmp/icon.png'},
      });
      expect(env.fake.completions['bad-todos'], {
        'outcome': {'outcome': 'cancelled'},
      });
      expect(env.fake.completions['other'], isEmpty);

      final stored = await env.spool.readAll(sessionId);
      expect(stored.any((update) => update.containsKey('method')), isFalse);
      expect(
        stored.where((update) => update['title'] == 'TodoWrite'),
        hasLength(1),
      );
      for (final update in stored) {
        expect(update['sessionUpdate'], 'tool_call');
        expect(() => SessionUpdate.fromJson(update), returnsNormally);
      }

      final again = env.connect();
      await again.client.client.loadSession(
        LoadSessionRequest(sessionId: sessionId, cwd: '/work', meta: _meta()),
      );
      final tools = [
        for (final notification in again.updates)
          if (notification.update is ToolCallUpdateSession)
            notification.update as ToolCallUpdateSession,
      ];
      expect(tools, hasLength(3));
      expect(tools[0].toolCall.title, 'TodoWrite');
      final todos = tools[0].toolCall.rawInput as Map;
      expect(todos['merge'], isTrue);
      expect(todos['todos'], [
        {'id': '1', 'content': 'A', 'status': 'pending'},
      ]);
      expect(tools[1].toolCall.toolCallId, 't1');
      expect(tools[1].toolCall.title, 'explore');
      expect(tools[2].toolCall.title, 'generate_image');
      expect((tools[2].toolCall.rawInput as Map)['filePath'], '/tmp/icon.png');
    },
  );

  test(
    'session close and a failed forward cancel ask and plan nested',
    () async {
      final env = await _startEnv();
      final phone = env.connect();
      final sessionId = await env.openSession(phone);

      env.fake.clientRequestEvents.add(
        AcpClientRequest(
          id: 'ask-live',
          method: 'cursor/ask_question',
          params: {
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
      await _until(() => env.fake.completions.containsKey('ask-live'));
      expect(env.fake.completions['ask-live'], {
        'outcome': {'outcome': 'cancelled'},
      });

      await _dropPhone(phone);
      env.fake.clientRequestEvents.add(
        AcpClientRequest(
          id: 'plan-1',
          method: 'cursor/create_plan',
          params: {'plan': '# Ship', 'toolCallId': 'p1'},
        ),
      );
      await _tick();
      expect(env.agent.permissionPending(sessionId), isTrue);

      final again = env.connect();
      await again.client.client.closeSession(
        CloseSessionRequest(sessionId: sessionId),
      );
      expect(env.fake.completions['plan-1'], {
        'outcome': {'outcome': 'cancelled'},
      });
      expect(env.agent.permissionPending(sessionId), isFalse);
    },
  );

  test('load rejects a session id that is not one path segment', () async {
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
      phone.client.client.loadSession(
        LoadSessionRequest(
          sessionId: '../outside',
          cwd: '/work',
          meta: _meta(),
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
    expect(env.fake.openLoadCount, 0);
    expect(
      Directory('${env.root.path}/acp-proxy/outside').existsSync(),
      isFalse,
    );
  });

  test(
    'a session directory without spool files is not treated as ready',
    () async {
      final env = await _startEnv();
      final dir = Directory('${env.root.path}/acp-proxy/sessions/sess-1');
      await dir.create(recursive: true);
      env.fake.onOpenNew = () {
        env.fake.updateEvents.add(_chunk('kept'));
      };
      final phone = env.connect();

      await env.openSession(phone);

      expect(File('${dir.path}/meta.json').existsSync(), isTrue);
      expect(File('${dir.path}/updates.jsonl').existsSync(), isTrue);
      final stored = await env.spool.readAll('sess-1');
      expect(
        stored.any((update) {
          final content = update['content'];
          return content is Map && content['text'] == 'kept';
        }),
        isTrue,
      );
    },
  );

  test('overlapping loads of one session share one upstream open', () async {
    final env = await _startEnv();
    final first = env.connect();
    final sessionId = await env.openSession(first);
    await _dropPhone(first);
    env.fake.alive = false;

    final gates = <Completer<void>>[];
    final created = <FakeUpstream>[];
    var opens = 0;
    env.agent.connectNew =
        ({
          required AcpProxyLaunchMeta meta,
          required String cwd,
          required List<Map<String, Object?>> mcpServers,
        }) async {
          opens++;
          final gate = Completer<void>();
          gates.add(gate);
          final upstream = FakeUpstream(sessionId: sessionId);
          created.add(upstream);
          await gate.future;
          return upstream;
        };
    addTearDown(() async {
      for (final gate in gates) {
        if (!gate.isCompleted) gate.complete();
      }
      for (final upstream in created) {
        if (!upstream.updateEvents.isClosed) {
          await upstream.updateEvents.close();
        }
        if (!upstream.clientRequestEvents.isClosed) {
          await upstream.clientRequestEvents.close();
        }
      }
    });

    final a = env.connect();
    final b = env.connect();
    final loadA = a.client.client.loadSession(
      LoadSessionRequest(sessionId: sessionId, cwd: '/work', meta: _meta()),
    );
    final loadB = b.client.client.loadSession(
      LoadSessionRequest(sessionId: sessionId, cwd: '/work', meta: _meta()),
    );
    try {
      await _until(() => opens >= 1);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(opens, 1);
      for (final gate in gates) {
        if (!gate.isCompleted) gate.complete();
      }
      await Future.wait([loadA, loadB]);
      expect(
        [a, b].where((phone) => !phone.served.connection.isClosed),
        hasLength(1),
      );
      expect(env.book.connectionFor(sessionId), isNotNull);
    } finally {
      for (final gate in gates) {
        if (!gate.isCompleted) gate.complete();
      }
    }
  });

  test('overlapping session new calls do not enter replay together', () async {
    final root = await Directory.systemTemp.createTemp('acp-proxy-agent');
    final gate = Completer<void>();
    final spool = _BlockingReadSpool(root: root, gate: gate);
    final env = await _startEnv(spool: spool);
    final a = env.connect();
    final b = env.connect();
    await a.client.client.initialize(
      const InitializeRequest(protocolVersion: ProtocolVersion.v1),
    );
    await b.client.client.initialize(
      const InitializeRequest(protocolVersion: ProtocolVersion.v1),
    );
    final newA = a.client.client.newSession(
      NewSessionRequest(cwd: '/work', meta: _meta()),
    );
    final newB = b.client.client.newSession(
      NewSessionRequest(cwd: '/work', meta: _meta()),
    );
    try {
      await _until(() => spool.reads >= 1);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(spool.reads, 1);
      gate.complete();
      await Future.wait([newA, newB]);
      expect(
        [a, b].where((phone) => !phone.served.connection.isClosed),
        hasLength(1),
      );
      expect(env.book.connectionFor(env.fake.sessionId), isNotNull);
    } finally {
      if (!gate.isCompleted) gate.complete();
    }
  });

  test(
    'close waits until the in-flight load of that session finishes',
    () async {
      final env = await _startEnv();
      final phone = env.connect();
      final gate = Completer<void>();
      final revived = FakeUpstream(sessionId: 'sess-load');
      var connectStarted = false;
      addTearDown(() async {
        if (!gate.isCompleted) gate.complete();
        if (!revived.updateEvents.isClosed) await revived.updateEvents.close();
        if (!revived.clientRequestEvents.isClosed) {
          await revived.clientRequestEvents.close();
        }
      });
      env.agent.connectNew =
          ({
            required AcpProxyLaunchMeta meta,
            required String cwd,
            required List<Map<String, Object?>> mcpServers,
          }) async {
            connectStarted = true;
            await gate.future;
            return revived;
          };

      final loading = phone.client.client.loadSession(
        LoadSessionRequest(sessionId: 'sess-load', cwd: '/work', meta: _meta()),
      );
      await _until(() => connectStarted);
      var closeDone = false;
      final closing = phone.client.client.closeSession(
        const CloseSessionRequest(sessionId: 'sess-load'),
      );
      unawaited(
        closing.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
      );
      closing.whenComplete(() => closeDone = true);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      try {
        expect(closeDone, isFalse);
        expect(
          Directory(
            '${env.root.path}/acp-proxy/sessions/sess-load',
          ).existsSync(),
          isFalse,
        );
        gate.complete();
        await loading;
        await closing;
        expect(env.book.sessionIds, isNot(contains('sess-load')));
        expect(
          Directory(
            '${env.root.path}/acp-proxy/sessions/sess-load',
          ).existsSync(),
          isFalse,
        );
        expect(revived.closeCount, 1);
      } finally {
        if (!gate.isCompleted) gate.complete();
      }
    },
  );

  test(
    'idle reap does not close a session an in-flight load just attached',
    () async {
      final env = await _startEnv();
      final phone = env.connect();
      final sessionId = await env.openSession(phone);
      await _dropPhone(phone);
      final disconnectedAt = env.agent.disconnectedSince[sessionId];
      expect(disconnectedAt, isNotNull);

      env.fake.alive = false;
      final gate = Completer<void>();
      final revived = FakeUpstream(sessionId: sessionId)
        ..holdOpenLoad = gate.future;
      addTearDown(() async {
        if (!gate.isCompleted) gate.complete();
        if (!revived.updateEvents.isClosed) await revived.updateEvents.close();
        if (!revived.clientRequestEvents.isClosed) {
          await revived.clientRequestEvents.close();
        }
      });
      env.agent.connectNew =
          ({
            required AcpProxyLaunchMeta meta,
            required String cwd,
            required List<Map<String, Object?>> mcpServers,
          }) async {
            return revived;
          };

      final again = env.connect();
      await again.client.client.initialize(
        const InitializeRequest(protocolVersion: ProtocolVersion.v1),
      );
      final loading = again.client.client.loadSession(
        LoadSessionRequest(sessionId: sessionId, cwd: '/work', meta: _meta()),
      );
      await _until(() => revived.openLoadCount == 1);

      final reaping = env.agent.reapIdle(
        now: disconnectedAt!.add(const Duration(minutes: 31)),
        idleTimeout: const Duration(minutes: 30),
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));
      gate.complete();
      await loading;
      await reaping;

      expect(env.book.connectionFor(sessionId), isNotNull);
      expect(env.agent.upstreams[sessionId], same(revived));
      expect(revived.closeCount, 0);
      expect(
        Directory(
          '${env.root.path}/acp-proxy/sessions/$sessionId',
        ).existsSync(),
        isTrue,
      );
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

Future<void> _until(bool Function() done) async {
  for (var i = 0; i < 50; i++) {
    if (done()) return;
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
}

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
  AcpProxySpool? spool,
}) async {
  final root =
      spool?.root ?? await Directory.systemTemp.createTemp('acp-proxy-agent');
  addTearDown(() async {
    if (root.existsSync()) await root.delete(recursive: true);
  });
  final upstream = fake ?? FakeUpstream();
  final book = AcpProxySessionBook();
  final sessionSpool = spool ?? AcpProxySpool(root: root);
  final agent = AcpProxyAgent(
    endpointCli: 'claude',
    book: book,
    spool: sessionSpool,
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
    if (!upstream.updateEvents.isClosed) await upstream.updateEvents.close();
    if (!upstream.clientRequestEvents.isClosed) {
      await upstream.clientRequestEvents.close();
    }
  });
  return _Env(
    root: root,
    agent: agent,
    book: book,
    spool: sessionSpool,
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
  Future<void>? holdOpenLoad;

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
    final hold = holdOpenLoad;
    if (hold != null) await hold;
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

class _FailingDeleteSpool extends AcpProxySpool {
  _FailingDeleteSpool({required super.root});

  final fail = <String>{};

  @override
  Future<void> delete(String sessionId) async {
    if (fail.contains(sessionId)) throw StateError('delete failed');
    await super.delete(sessionId);
  }
}

class _BlockingReadSpool extends AcpProxySpool {
  _BlockingReadSpool({required super.root, required this.gate});

  final Completer<void> gate;
  var reads = 0;

  @override
  Future<List<Map<String, Object?>>> readAll(String sessionId) async {
    reads++;
    if (reads == 1) await gate.future;
    return super.readAll(sessionId);
  }
}
