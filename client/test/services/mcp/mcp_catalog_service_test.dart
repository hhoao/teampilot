import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/mcp_server.dart';
import 'package:teampilot/services/mcp/mcp_catalog_service.dart';

void main() {
  late Directory tmp;
  late McpCatalogService catalog;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('mcp_catalog_test_');
    catalog = McpCatalogService(
      catalogPath: p.join(tmp.path, 'mcp', 'mcp_servers.json'),
    );
  });

  tearDown(() async {
    if (await tmp.exists()) {
      await tmp.delete(recursive: true);
    }
  });

  test('loadAll returns empty when file missing', () async {
    expect(await catalog.loadAll(), isEmpty);
  });

  test('saveAll round-trips servers', () async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final server = McpServer(
      id: 'fetch',
      name: 'fetch',
      server: const {'type': 'stdio', 'command': 'npx'},
      createdAt: now,
      updatedAt: now,
    );
    await catalog.saveAll([server]);
    final loaded = await catalog.loadAll();
    expect(loaded, hasLength(1));
    expect(loaded.single.id, 'fetch');
    expect(loaded.single.server['command'], 'npx');
  });

  test('upsert replaces by id', () async {
    final a = McpServer(
      id: 'a',
      name: 'a',
      server: const {'type': 'stdio', 'command': 'one'},
      createdAt: 1,
      updatedAt: 1,
    );
    await catalog.upsert(a);
    await catalog.upsert(
      a.copyWith(server: const {'type': 'stdio', 'command': 'two'}, updatedAt: 2),
    );
    final loaded = await catalog.loadAll();
    expect(loaded.single.server['command'], 'two');
  });
}
