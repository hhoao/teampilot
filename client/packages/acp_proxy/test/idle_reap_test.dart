import 'dart:io';

import 'package:acp_proxy/acp_proxy.dart';
import 'package:test/test.dart';

void main() {
  test(
    'reaps only sessions idle past the timeout with nothing pending',
    () async {
      final root = await Directory.systemTemp.createTemp('acp-proxy-reap');
      addTearDown(() => root.delete(recursive: true));

      final book = AcpProxySessionBook();
      final spool = AcpProxySpool(root: root);
      final upstreams = <String, AcpUpstream>{};
      final fakes = <String, _FakeUpstream>{};
      final disconnectedSince = <String, DateTime>{};
      final now = DateTime.utc(2026, 11, 14, 12);

      Future<void> track(
        String sessionId,
        Duration age, {
        bool turn = false,
        bool connected = false,
      }) async {
        await spool.create(
          sessionId: sessionId,
          cwd: '/work',
          meta: const AcpProxyLaunchMeta(
            cli: 'claude',
            executable: '/usr/local/bin/claude',
            args: ['--acp'],
            env: {},
            permissionPolicy: AcpProxyPermissionPolicy.ask,
          ),
        );
        final upstream = _FakeUpstream();
        fakes[sessionId] = upstream;
        upstreams[sessionId] = upstream;
        book.attach(sessionId: sessionId, connectionId: 'c-$sessionId');
        if (!connected) book.detach('c-$sessionId');
        if (turn) {
          book.onPrompt(sessionId: sessionId, text: 'still running');
        }
        disconnectedSince[sessionId] = now.subtract(age);
      }

      await track('gone', const Duration(minutes: 31));
      await track('busy', const Duration(minutes: 31), turn: true);
      await track('fresh', const Duration(minutes: 1));
      await track('asked', const Duration(minutes: 31));
      await track('live', const Duration(minutes: 31), connected: true);

      expect(book.phoneConnected('gone'), isFalse);
      expect(book.phoneConnected('live'), isTrue);
      expect(book.turnInProgress('gone'), isFalse);
      expect(book.phoneConnected('busy'), isFalse);
      expect(book.turnInProgress('busy'), isTrue);
      expect(
        book.sessionIds,
        containsAll(['gone', 'busy', 'fresh', 'asked', 'live']),
      );

      await reapIdleSessions(
        book: book,
        spool: spool,
        upstreams: upstreams,
        disconnectedSince: disconnectedSince,
        now: now,
        idleTimeout: const Duration(minutes: 30),
        permissionPending: (sessionId) => sessionId == 'asked',
      );

      expect(fakes['gone']!.closed, isTrue);
      expect(_sessionDir(root, 'gone').existsSync(), isFalse);
      expect(disconnectedSince.containsKey('gone'), isFalse);

      expect(fakes['busy']!.closed, isFalse);
      expect(_sessionDir(root, 'busy').existsSync(), isTrue);
      expect(book.turnInProgress('busy'), isTrue);
      expect(disconnectedSince.containsKey('busy'), isTrue);

      expect(fakes['fresh']!.closed, isFalse);
      expect(_sessionDir(root, 'fresh').existsSync(), isTrue);
      expect(disconnectedSince.containsKey('fresh'), isTrue);

      expect(fakes['asked']!.closed, isFalse);
      expect(_sessionDir(root, 'asked').existsSync(), isTrue);
      expect(disconnectedSince.containsKey('asked'), isTrue);

      expect(fakes['live']!.closed, isFalse);
      expect(_sessionDir(root, 'live').existsSync(), isTrue);
      expect(book.phoneConnected('live'), isTrue);
      expect(disconnectedSince.containsKey('live'), isTrue);
    },
  );
}

Directory _sessionDir(Directory root, String sessionId) {
  return Directory('${root.path}/acp-proxy/sessions/$sessionId');
}

class _FakeUpstream implements AcpUpstream {
  var closed = false;
  var alive = true;

  @override
  Future<void> close() async {
    closed = true;
    alive = false;
  }

  @override
  Future<String> openNew({
    required AcpProxyLaunchMeta meta,
    required String cwd,
    required List<Map<String, Object?>> mcpServers,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<void> openLoad({required String sessionId, required String cwd}) {
    throw UnimplementedError();
  }

  @override
  Future<void> prompt(String text) => throw UnimplementedError();

  @override
  Future<void> cancel() => throw UnimplementedError();

  @override
  Stream<Map<String, Object?>> get updates => const Stream.empty();

  @override
  Stream<AcpClientRequest> get clientRequests => const Stream.empty();

  @override
  void completeClientRequest(Object id, Map<String, Object?> result) {}
}
