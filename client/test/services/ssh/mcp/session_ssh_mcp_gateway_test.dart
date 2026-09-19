import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/services/ssh/mcp/session_ssh_mcp_constants.dart';
import 'package:teampilot/services/ssh/mcp/session_ssh_mcp_http.dart';
import 'package:teampilot/services/ssh/mcp/session_ssh_mcp_operations.dart';
import 'package:teampilot/services/ssh/mcp/session_ssh_mcp_targets.dart';
import 'package:teampilot/services/chat/team_bus/mcp/teammate_bus_mcp_config.dart';
import 'package:teampilot/services/chat/team_bus/mcp/teammate_bus_mcp_gateway.dart';

import '../../../support/in_memory_filesystem.dart';

void main() {
  setUpAll(() {
    HttpOverrides.global = null;
  });

  late TeammateBusMcpGateway gateway;
  late HttpClient client;
  late _FakeExecutor executor;

  setUp(() async {
    gateway = TeammateBusMcpGateway();
    await gateway.ensureStarted();
    client = HttpClient();
    executor = _FakeExecutor();
  });

  tearDown(() async {
    client.close(force: true);
    await gateway.dispose();
  });

  SessionSshMcpContext context() => SessionSshMcpContext(
    enabled: true,
    targets: [
      SessionSshMcpTarget(
        profile: const SshProfile(
          id: 'home',
          name: 'Home',
          host: '192.168.1.8',
          username: 'alice',
        ),
        folderPaths: const ['/home/alice/proj'],
      ),
    ],
    localAllowedRoots: const ['/workspace'],
    localUsesPosixPaths: true,
    localFs: InMemoryFilesystem(),
  );

  SessionSshMcpHttpAdapter adapter({
    Future<SessionSshMcpContext?> Function(String sessionId, String? memberId)?
    resolveContext,
  }) => SessionSshMcpHttpAdapter(
    operations: SessionSshMcpOperations(executor: executor),
    resolveContext:
        resolveContext ?? (id, _) async => id == 'sess-1' ? context() : null,
  );

  Future<HttpClientResponse> postSsh({
    String? sessionId,
    String? memberId,
    String? mcpSessionId,
    String? host,
    required Map<String, Object?> body,
  }) async {
    final req = await client.postUrl(gateway.sessionSshMcpEndpoint);
    req.headers.set('content-type', 'application/json');
    req.headers.set('accept', 'application/json, text/event-stream');
    if (sessionId != null) {
      req.headers.set(teammateBusMcpSessionHeader, sessionId);
    }
    if (memberId != null) {
      req.headers.set(teammateBusMcpMemberHeader, memberId);
    }
    if (mcpSessionId != null) {
      req.headers.set('mcp-session-id', mcpSessionId);
    }
    if (host != null) {
      req.headers.set(HttpHeaders.hostHeader, host);
    }
    req.add(utf8.encode(jsonEncode(body)));
    return req.close();
  }

  Map<String, Object?> parseRpc(HttpClientResponse resp, String text) {
    if (resp.headers.contentType?.mimeType == 'text/event-stream') {
      final line = text
          .split('\n')
          .firstWhere((l) => l.startsWith('data:'), orElse: () => '');
      if (line.isEmpty) return {'raw': text};
      return jsonDecode(line.substring(5).trim()) as Map<String, Object?>;
    }
    if (text.trim().isEmpty) return const {};
    return jsonDecode(text) as Map<String, Object?>;
  }

  const initializeBody = <String, Object?>{
    'jsonrpc': '2.0',
    'id': 1,
    'method': 'initialize',
    'params': {
      'protocolVersion': '2025-11-25',
      'capabilities': <String, Object?>{},
      'clientInfo': {'name': 'teampilot-test', 'version': '1.0.0'},
    },
  };

  Future<String> handshake({String sessionId = 'sess-1'}) async {
    final initResp = await postSsh(sessionId: sessionId, body: initializeBody);
    expect(initResp.statusCode, HttpStatus.ok);
    final mcpSessionId = initResp.headers.value('mcp-session-id');
    await initResp.drain<void>();
    expect(mcpSessionId, isNotNull);
    final initialized = await postSsh(
      sessionId: sessionId,
      mcpSessionId: mcpSessionId,
      body: {'jsonrpc': '2.0', 'method': 'notifications/initialized'},
    );
    await initialized.drain<void>();
    return mcpSessionId!;
  }

  Future<({int statusCode, Map<String, Object?> json})> rpcSsh({
    String? sessionId,
    required String mcpSessionId,
    required Map<String, Object?> body,
  }) async {
    final resp = await postSsh(
      sessionId: sessionId,
      mcpSessionId: mcpSessionId,
      body: body,
    );
    final json = parseRpc(resp, await resp.transform(utf8.decoder).join());
    return (statusCode: resp.statusCode, json: json);
  }

  bool isToolError(Map<String, Object?> json) {
    final result = json['result'];
    return result is Map && result['isError'] == true;
  }

  test('initialize then tools/list on /ssh/mcp returns list-servers', () async {
    gateway.attachSessionSshMcp(adapter());
    expect(gateway.isSessionRegistered('sess-1'), isFalse);
    expect(gateway.sessionSshMcpEndpoint.path, sessionSshMcpPath);

    final mcpSessionId = await handshake();
    final listed = await rpcSsh(
      sessionId: 'sess-1',
      mcpSessionId: mcpSessionId,
      body: {'jsonrpc': '2.0', 'id': 2, 'method': 'tools/list'},
    );
    expect(listed.statusCode, HttpStatus.ok);
    final tools = listed.json['result'] is Map
        ? (listed.json['result'] as Map)['tools'] as List
        : const [];
    final names = [for (final t in tools) (t as Map)['name']];
    expect(
      names,
      containsAll([
        sessionSshMcpToolListServers,
        sessionSshMcpToolExecuteCommand,
        sessionSshMcpToolUpload,
        sessionSshMcpToolDownload,
      ]),
    );

    final callResp = await rpcSsh(
      sessionId: 'sess-1',
      mcpSessionId: mcpSessionId,
      body: {
        'jsonrpc': '2.0',
        'id': 3,
        'method': 'tools/call',
        'params': {
          'name': sessionSshMcpToolListServers,
          'arguments': <String, Object?>{},
        },
      },
    );
    expect(callResp.statusCode, HttpStatus.ok);
    final callText = jsonEncode(callResp.json);
    expect(callText, contains('home'));
    expect(callText, isNot(contains('Missing X-Session')));
  });

  test(
    'tools/call list-servers without X-Session returns HTTP 200 isError',
    () async {
      gateway.attachSessionSshMcp(adapter());
      final mcpSessionId = await handshake();

      final called = await rpcSsh(
        mcpSessionId: mcpSessionId,
        body: {
          'jsonrpc': '2.0',
          'id': 3,
          'method': 'tools/call',
          'params': {
            'name': sessionSshMcpToolListServers,
            'arguments': <String, Object?>{},
          },
        },
      );
      expect(called.statusCode, HttpStatus.ok);
      expect(called.statusCode, isNot(HttpStatus.badRequest));
      expect(called.json['error'] != null || isToolError(called.json), isTrue);
      expect(jsonEncode(called.json), contains('Missing X-Session'));
    },
  );

  test('tools/call with unknown X-Session returns HTTP 200 isError', () async {
    gateway.attachSessionSshMcp(adapter());
    final mcpSessionId = await handshake();

    final called = await rpcSsh(
      sessionId: 'unknown-sess',
      mcpSessionId: mcpSessionId,
      body: {
        'jsonrpc': '2.0',
        'id': 4,
        'method': 'tools/call',
        'params': {
          'name': sessionSshMcpToolListServers,
          'arguments': <String, Object?>{},
        },
      },
    );
    expect(called.statusCode, HttpStatus.ok);
    expect(called.json['error'] != null || isToolError(called.json), isTrue);
    expect(jsonEncode(called.json), contains('Unknown session'));
  });

  test('missing X-Session on /ssh/mcp returns HTTP 200 not 400', () async {
    gateway.attachSessionSshMcp(adapter());

    final resp = await postSsh(body: initializeBody);
    expect(resp.statusCode, HttpStatus.ok);
    expect(resp.statusCode, isNot(HttpStatus.badRequest));
    await resp.drain<void>();
  });

  test('POST /mcp without TeamBus register still returns 400', () async {
    gateway.attachSessionSshMcp(adapter());

    final req = await client.postUrl(gateway.mcpEndpoint);
    req.headers.set('content-type', 'application/json');
    req.headers.set(teammateBusMcpSessionHeader, 'sess-1');
    req.add(
      utf8.encode(
        jsonEncode({'jsonrpc': '2.0', 'id': 1, 'method': 'tools/list'}),
      ),
    );
    final resp = await req.close();
    expect(resp.statusCode, HttpStatus.badRequest);
    await resp.drain<void>();
  });

  test('tools/call passes X-Member into resolveContext', () async {
    String? capturedMemberId;
    gateway.attachSessionSshMcp(
      adapter(
        resolveContext: (id, memberId) async {
          capturedMemberId = memberId;
          return id == 'sess-1' ? context() : null;
        },
      ),
    );
    final mcpSessionId = await handshake();

    final called = await rpcSsh(
      sessionId: 'sess-1',
      mcpSessionId: mcpSessionId,
      body: {
        'jsonrpc': '2.0',
        'id': 5,
        'method': 'tools/call',
        'params': {
          'name': sessionSshMcpToolListServers,
          'arguments': <String, Object?>{},
        },
      },
    );
    expect(called.statusCode, HttpStatus.ok);
    expect(capturedMemberId, isNull);

    await postSsh(
      sessionId: 'sess-1',
      memberId: 'member-42',
      mcpSessionId: mcpSessionId,
      body: {
        'jsonrpc': '2.0',
        'id': 6,
        'method': 'tools/call',
        'params': {
          'name': sessionSshMcpToolListServers,
          'arguments': <String, Object?>{},
        },
      },
    ).then((r) => r.drain<void>());
    expect(capturedMemberId, 'member-42');
  });

  test('illegal Host on /ssh/mcp is rejected without running tools', () async {
    gateway.attachSessionSshMcp(adapter());

    final resp = await postSsh(
      sessionId: 'sess-1',
      host: 'evil.example.com',
      body: initializeBody,
    );
    expect(resp.statusCode, anyOf(HttpStatus.forbidden, HttpStatus.badRequest));
    expect(resp.statusCode, isNot(HttpStatus.ok));
    await resp.drain<void>();
    expect(executor.runCount, 0);
  });
}

class _FakeExecutor implements SessionSshMcpExecutor {
  var runCount = 0;

  @override
  Future<({int? exitCode, String stdout, String stderr})> runCommand({
    required SshProfile profile,
    required String command,
    required Duration timeout,
  }) async {
    runCount++;
    return (exitCode: 0, stdout: '', stderr: '');
  }

  @override
  Future<void> upload({
    required SshProfile profile,
    required List<int> bytes,
    required String remotePath,
  }) async {}

  @override
  Future<List<int>> download({
    required SshProfile profile,
    required String remotePath,
  }) async => const [];
}
