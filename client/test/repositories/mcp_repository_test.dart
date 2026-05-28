import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/mcp_server.dart';
import 'package:teampilot/repositories/mcp_repository.dart';
import 'package:teampilot/services/mcp/mcp_catalog_service.dart';

void main() {
  late Directory tmp;
  late McpCatalogService catalog;
  late McpRepository repository;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('mcp_repo_test_');
    final path = p.join(tmp.path, 'mcp', 'mcp_servers.json');
    catalog = McpCatalogService(catalogPath: path);
    repository = McpRepository(catalog: catalog);
  });

  tearDown(() async {
    if (await tmp.exists()) {
      await tmp.delete(recursive: true);
    }
  });

  test('loadAll uses in-memory cache until forceReload', () async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await catalog.saveAll([
      McpServer(
        id: 'a',
        name: 'A',
        server: const {'type': 'stdio', 'command': 'echo'},
        createdAt: now,
        updatedAt: now,
      ),
    ]);

    final first = await repository.loadAll();
    expect(first, hasLength(1));

    await catalog.saveAll([
      McpServer(
        id: 'b',
        name: 'B',
        server: const {'type': 'stdio', 'command': 'echo'},
        createdAt: now,
        updatedAt: now,
      ),
    ]);

    final cached = await repository.loadAll();
    expect(cached, hasLength(1));
    expect(cached.first.id, 'a');

    final reloaded = await repository.loadAll(forceReload: true);
    expect(reloaded, hasLength(1));
    expect(reloaded.first.id, 'b');
  });

  test('upsert updates cache without extra loadAll', () async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await repository.loadAll();

    final saved = await repository.upsert(
      McpServer(
        id: 'new',
        name: 'New',
        server: const {'type': 'stdio', 'command': 'uvx'},
        createdAt: now,
        updatedAt: now,
      ),
    );

    final list = await repository.loadAll();
    expect(list.any((s) => s.id == saved.id), isTrue);
  });
}
