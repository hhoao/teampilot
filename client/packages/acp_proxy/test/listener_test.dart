import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:acp_proxy/acp_proxy.dart';
import 'package:test/test.dart';

void main() {
  test('listens on loopback and publishes the pid', () async {
    final root = await Directory.systemTemp.createTemp('acp-proxy-listen');
    addTearDown(() => root.delete(recursive: true));
    final upstream = _FakeUpstream();
    addTearDown(upstream.dispose);
    final agent = _agent(root, upstream);
    final listener = AcpProxyListener(
      root: root,
      cliIds: const ['claude'],
      agentForCli: (_) => agent,
      pid: 4242,
    );
    addTearDown(listener.close);

    await listener.start();

    final json =
        jsonDecode(acpProxyAdvertisementFile(root).readAsStringSync())
            as Map<String, Object?>;
    expect(json['bind'], '127.0.0.1');
    expect(json['version'], '0.1.0');
    expect(json['pid'], 4242);
    final clis = json['clis']! as Map<String, Object?>;
    final claude = clis['claude']! as Map<String, Object?>;
    final port = claude['port']! as int;
    expect(port, greaterThan(0));

    await expectLater(
      ServerSocket.bind(InternetAddress.loopbackIPv4, port),
      throwsA(isA<SocketException>()),
    );

    await listener.close();

    final rebound = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(rebound.close);
    expect(rebound.port, greaterThan(0));
    expect(
      File('${root.path}/acp-proxy/acp-proxy.pid').readAsStringSync().trim(),
      '4242',
    );
  });

  test('start rejects a null pid before it binds', () async {
    final root = await Directory.systemTemp.createTemp('acp-proxy-listen-pid');
    addTearDown(() => root.delete(recursive: true));
    final listener = AcpProxyListener(
      root: root,
      cliIds: const ['claude'],
      agentForCli: (_) => throw StateError('unused'),
      pid: null,
    );

    await expectLater(listener.start(), throwsArgumentError);
    expect(acpProxyAdvertisementFile(root).existsSync(), isFalse);
    expect(File('${root.path}/acp-proxy/acp-proxy.pid').existsSync(), isFalse);
  });

  test('one loopback port per cli id', () async {
    final root = await Directory.systemTemp.createTemp('acp-proxy-listen-clis');
    addTearDown(() => root.delete(recursive: true));
    final upstream = _FakeUpstream();
    addTearDown(upstream.dispose);
    final agent = _agent(root, upstream);
    final listener = AcpProxyListener(
      root: root,
      cliIds: const ['claude', 'codex'],
      agentForCli: (_) => agent,
      pid: 7,
    );
    addTearDown(listener.close);

    final ad = await listener.start();

    expect(ad.ports.keys, ['claude', 'codex']);
    expect(ad.ports['claude'], greaterThan(0));
    expect(ad.ports['codex'], greaterThan(0));
    expect(ad.ports['claude'], isNot(ad.ports['codex']));
    await expectLater(
      ServerSocket.bind(InternetAddress.loopbackIPv4, ad.ports['claude']!),
      throwsA(isA<SocketException>()),
    );
    await expectLater(
      ServerSocket.bind(InternetAddress.loopbackIPv4, ad.ports['codex']!),
      throwsA(isA<SocketException>()),
    );
  });

  test('an accepted socket is newline-delimited JSON-RPC', () async {
    final root = await Directory.systemTemp.createTemp('acp-proxy-listen-wire');
    addTearDown(() => root.delete(recursive: true));
    final upstream = _FakeUpstream();
    addTearDown(upstream.dispose);
    final agent = _agent(root, upstream);
    final listener = AcpProxyListener(
      root: root,
      cliIds: const ['claude'],
      agentForCli: (_) => agent,
      pid: 4242,
    );
    addTearDown(listener.close);

    final ad = await listener.start();
    final socket = await Socket.connect(
      InternetAddress.loopbackIPv4,
      ad.ports['claude']!,
    );
    addTearDown(socket.close);
    final lines = StreamIterator(
      socket
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .map((line) => Map<String, Object?>.from(jsonDecode(line) as Map)),
    );
    addTearDown(lines.cancel);

    socket.write(
      '{"jsonrpc":"2.0","id":1,"method":"initialize","params":'
      '{"protocolVersion":1}}\n'
      '{"jsonrpc":"2.0","id":2,"method":"initialize","params":'
      '{"protocolVersion":1}}\n',
    );

    expect(await lines.moveNext().timeout(const Duration(seconds: 5)), isTrue);
    expect(lines.current['id'], 1);
    expect(lines.current.containsKey('error'), isFalse);
    final first = Map<String, Object?>.from(lines.current['result']! as Map);
    expect(first['protocolVersion'], 1);
    final capabilities = Map<String, Object?>.from(
      first['agentCapabilities']! as Map,
    );
    expect(capabilities['loadSession'], isTrue);

    expect(await lines.moveNext().timeout(const Duration(seconds: 5)), isTrue);
    expect(lines.current['id'], 2);
  });
}

AcpProxyAgent _agent(Directory root, _FakeUpstream upstream) {
  final agent = AcpProxyAgent(
    endpointCli: 'claude',
    book: AcpProxySessionBook(),
    spool: AcpProxySpool(root: root),
    upstreams: {},
  );
  agent.connectNew =
      ({
        required AcpProxyLaunchMeta meta,
        required String cwd,
        required List<Map<String, Object?>> mcpServers,
      }) async {
        return upstream;
      };
  return agent;
}

class _FakeUpstream implements AcpUpstream {
  final _updates = StreamController<Map<String, Object?>>.broadcast();
  final _requests = StreamController<AcpClientRequest>.broadcast();

  Future<void> dispose() async {
    await _updates.close();
    await _requests.close();
  }

  @override
  bool get alive => true;

  @override
  Future<String> openNew({
    required AcpProxyLaunchMeta meta,
    required String cwd,
    required List<Map<String, Object?>> mcpServers,
  }) async {
    return 'sess-1';
  }

  @override
  Future<void> openLoad({required String sessionId, required String cwd}) {
    return Future<void>.value();
  }

  @override
  Future<void> prompt(String text) => Future<void>.value();

  @override
  Future<void> cancel() => Future<void>.value();

  @override
  Future<void> close() async {}

  @override
  Stream<Map<String, Object?>> get updates => _updates.stream;

  @override
  Stream<AcpClientRequest> get clientRequests => _requests.stream;

  @override
  void completeClientRequest(Object id, Map<String, Object?> result) {}
}
