import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/services/catalog/catalog_kind.dart';
import 'package:teampilot/services/catalog/catalog_kind_registry.dart';
import 'package:teampilot/services/catalog/catalog_mcp_constants.dart';
import 'package:teampilot/services/catalog/catalog_mcp_handler.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/team_bus/mcp/jsonrpc.dart';

import 'support/fake_catalog_module.dart';

class _RecordingGenerationMutationHandler
    implements CatalogGenerationMutationHandler {
  CatalogRequest? request;

  @override
  Future<CatalogResult> handleMcpMutation({
    required String kind,
    required CatalogOp op,
    required CatalogRequest request,
  }) async {
    this.request = request;
    return CatalogResult.ok(
      kind: kind,
      ids: const ['x'],
      workspaceId: request.workspaceId,
      boundTo: CatalogBindTo.generation,
    );
  }
}

void main() {
  final fs = LocalFilesystem();

  CatalogKindRegistry registry() =>
      CatalogKindRegistry()..register(FakeCatalogModule(kind: 'skill'));

  CatalogMcpHandler handler() => CatalogMcpHandler(registry: registry());

  CatalogMcpSession session() => CatalogMcpSession(
    sessionId: 's',
    workspaceId: 'w',
    memberId: 'm',
    workFs: fs,
    allowedRoots: const ['/work'],
  );

  CatalogMcpSession builderSession() => CatalogMcpSession(
    sessionId: 'builder',
    workspaceId: 'w',
    memberId: 'builder',
    workFs: fs,
    allowedRoots: const ['/work'],
    purpose: SessionPurpose.teamGeneration,
    workflowId: 'workflow',
  );

  test(
    'initialize returns protocol 2025-06-18 and serverInfo.name teampilot',
    () async {
      final res = await handler().handle(
        const JsonRpcRequest(id: 0, method: 'initialize'),
        session(),
      );
      expect(res!.result!['protocolVersion'], '2025-06-18');
      expect((res.result!['serverInfo'] as Map)['name'], 'teampilot');
      expect(CatalogMcpHandler.serverName, catalogMcpServerName);
      expect(CatalogMcpHandler.serverName, 'teampilot');
    },
  );

  test('tools/list includes list_installed and advertised tools', () async {
    final res = await handler().handle(
      const JsonRpcRequest(id: 1, method: 'tools/list'),
      session(),
    );
    final names = [
      for (final t in res!.result!['tools'] as List) (t as Map)['name'],
    ];
    expect(names, contains('list_installed'));
    expect(names, contains('search_skills'));
    expect(names, contains('create_skill'));
  });

  test(
    'tools/call create_skill returns JSON text with restart_required',
    () async {
      final res = await handler().handle(
        const JsonRpcRequest(
          id: 2,
          method: 'tools/call',
          params: {
            'name': 'create_skill',
            'arguments': {'name': 'demo', 'body': 'Do X'},
          },
        ),
        session(),
      );
      expect(res!.result!['isError'], isFalse);
      final text = (res.result!['content'] as List).first['text'] as String;
      expect(text, contains('restart_required'));
      final json = jsonDecode(text) as Map<String, Object?>;
      expect(json['ok'], isTrue);
      expect(json['ids'], ['x']);
      expect(json['restart_required'], isTrue);
    },
  );

  test('CatalogException becomes toolError with code=unsupported_op', () async {
    final res = await handler().handle(
      const JsonRpcRequest(
        id: 3,
        method: 'tools/call',
        params: {'name': 'not_a_tool', 'arguments': <String, Object?>{}},
      ),
      session(),
    );
    expect(res!.result!['isError'], isTrue);
    final text = (res.result!['content'] as List).first['text'] as String;
    expect(text, contains('code=unsupported_op'));
  });

  test('unknown method returns JSON-RPC error', () async {
    final res = await handler().handle(
      const JsonRpcRequest(id: 4, method: 'not/a/method'),
      session(),
    );
    expect(res!.error, isNotNull);
    expect(res.result, isNull);
    expect(res.code, -32601);
    expect(res.error, contains('not/a/method'));
  });

  test('notifications return null', () async {
    final res = await handler().handle(
      const JsonRpcRequest(method: 'notifications/initialized'),
      session(),
    );
    expect(res, isNull);
  });

  test('invalid bind_to becomes toolError bind_scope_unsupported', () async {
    final res = await handler().handle(
      const JsonRpcRequest(
        id: 5,
        method: 'tools/call',
        params: {
          'name': 'create_skill',
          'arguments': {'bind_to': 'galaxy'},
        },
      ),
      session(),
    );
    expect(res!.result!['isError'], isTrue);
    final text = (res.result!['content'] as List).first['text'] as String;
    expect(text, contains('code=bind_scope_unsupported'));
  });

  test('bind_to team is rejected before dispatch', () async {
    final module = FakeCatalogModule(kind: 'skill');
    final h = CatalogMcpHandler(
      registry: CatalogKindRegistry()..register(module),
    );
    final res = await h.handle(
      const JsonRpcRequest(
        id: 6,
        method: 'tools/call',
        params: {
          'name': 'create_skill',
          'arguments': {'name': 'demo', 'body': 'Do X', 'bind_to': 'team'},
        },
      ),
      session(),
    );
    expect(res!.result!['isError'], isTrue);
    final text = (res.result!['content'] as List).first['text'] as String;
    expect(text, contains('code=bind_scope_unsupported'));
    expect(module.lastOp, isNull);
  });

  test('generation scope is rejected for a normal session', () async {
    final module = FakeCatalogModule(kind: 'skill');
    final h = CatalogMcpHandler(
      registry: CatalogKindRegistry()..register(module),
    );

    final res = await h.handle(
      const JsonRpcRequest(
        id: 7,
        method: 'tools/call',
        params: {
          'name': 'create_skill',
          'arguments': {
            'name': 'demo',
            'body': 'Do X',
            'bind_to': 'generation',
          },
        },
      ),
      session(),
    );

    expect(res!.result!['isError'], isTrue);
    final text = (res.result!['content'] as List).first['text'] as String;
    expect(text, contains('code=bind_scope_unsupported'));
    expect(module.lastOp, isNull);
  });

  test(
    'generation request carries persisted builder purpose and workflow',
    () async {
      final generation = _RecordingGenerationMutationHandler();
      final h = CatalogMcpHandler(
        registry: CatalogKindRegistry()
          ..register(FakeCatalogModule(kind: 'skill')),
        generationMutationHandler: generation,
      );

      await h.handle(
        const JsonRpcRequest(
          id: 8,
          method: 'tools/call',
          params: {
            'name': 'create_skill',
            'arguments': {
              'name': 'demo',
              'body': 'Do X',
              'bind_to': 'generation',
            },
          },
        ),
        builderSession(),
      );

      expect(generation.request!.purpose, SessionPurpose.teamGeneration);
      expect(generation.request!.workflowId, 'workflow');
    },
  );
}
