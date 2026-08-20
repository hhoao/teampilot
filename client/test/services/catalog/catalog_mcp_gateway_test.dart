import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/catalog/catalog_kind_registry.dart';
import 'package:teampilot/services/catalog/catalog_mcp_constants.dart';
import 'package:teampilot/services/catalog/catalog_mcp_handler.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/team_bus/mcp/teammate_bus_mcp_config.dart';
import 'package:teampilot/services/team_bus/mcp/teammate_bus_mcp_gateway.dart';

import 'support/fake_catalog_module.dart';

void main() {
  setUpAll(() {
    HttpOverrides.global = null;
  });

  late TeammateBusMcpGateway gateway;
  late HttpClient client;

  setUp(() async {
    gateway = TeammateBusMcpGateway();
    await gateway.ensureStarted();
    client = HttpClient();
  });

  tearDown(() async {
    client.close(force: true);
    await gateway.dispose();
  });

  CatalogMcpHandler catalogHandler() => CatalogMcpHandler(
    registry: CatalogKindRegistry()..register(FakeCatalogModule(kind: 'skill')),
  );

  CatalogMcpSession catalogSession() => CatalogMcpSession(
    sessionId: 'sess-1',
    workspaceId: 'ws-1',
    workFs: LocalFilesystem(),
    allowedRoots: const ['/work'],
  );

  Future<HttpClientResponse> postCatalog({
    String? sessionId,
    required Map<String, Object?> body,
  }) async {
    final req = await client.postUrl(gateway.catalogMcpEndpoint);
    req.headers.set('content-type', 'application/json');
    if (sessionId != null) {
      req.headers.set(teammateBusMcpSessionHeader, sessionId);
    }
    req.add(utf8.encode(jsonEncode(body)));
    return req.close();
  }

  test(
    'tools/list on /catalog/mcp without TeamBus register returns 200',
    () async {
      gateway.attachCatalogHandler(
        catalogHandler(),
        resolveSession: (id) async => id == 'sess-1' ? catalogSession() : null,
      );
      expect(gateway.isSessionRegistered('sess-1'), isFalse);
      expect(gateway.catalogMcpEndpoint.path, catalogMcpPath);

      final resp = await postCatalog(
        sessionId: 'sess-1',
        body: {'jsonrpc': '2.0', 'id': 1, 'method': 'tools/list'},
      );
      expect(resp.statusCode, HttpStatus.ok);
      final json =
          jsonDecode(await resp.transform(utf8.decoder).join())
              as Map<String, Object?>;
      final tools = json['result'] is Map
          ? (json['result'] as Map)['tools'] as List
          : const [];
      final names = [for (final t in tools) (t as Map)['name']];
      expect(names, contains('list_installed'));
      expect(names, contains('search_skills'));
    },
  );

  test(
    'missing X-Session on /catalog/mcp returns HTTP 200 with JSON-RPC error',
    () async {
      gateway.attachCatalogHandler(
        catalogHandler(),
        resolveSession: (_) async => catalogSession(),
      );

      final resp = await postCatalog(
        body: {'jsonrpc': '2.0', 'id': 1, 'method': 'tools/list'},
      );
      expect(resp.statusCode, HttpStatus.ok);
      expect(resp.statusCode, isNot(HttpStatus.badRequest));
      final json =
          jsonDecode(await resp.transform(utf8.decoder).join())
              as Map<String, Object?>;
      final result = json['result'];
      final isToolError =
          result is Map && result['isError'] == true;
      expect(json['error'] != null || isToolError, isTrue);
    },
  );

  test('POST /mcp without TeamBus register still returns 400', () async {
    gateway.attachCatalogHandler(
      catalogHandler(),
      resolveSession: (_) async => catalogSession(),
    );

    final req = await client.postUrl(gateway.mcpEndpoint);
    req.headers.set('content-type', 'application/json');
    req.headers.set(teammateBusMcpSessionHeader, 'sess-1');
    req.add(
      utf8.encode(
        jsonEncode({
          'jsonrpc': '2.0',
          'id': 1,
          'method': 'tools/list',
        }),
      ),
    );
    final resp = await req.close();
    expect(resp.statusCode, HttpStatus.badRequest);
    await resp.drain<void>();
  });
}
