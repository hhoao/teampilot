import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/mcp_server.dart';
import 'package:teampilot/repositories/mcp_repository.dart';
import 'package:teampilot/repositories/workspace_project_config_repository.dart';
import 'package:teampilot/services/catalog/catalog_kind.dart';
import 'package:teampilot/services/catalog/catalog_mutation_bus.dart';
import 'package:teampilot/services/catalog/catalog_workspace_binder.dart';
import 'package:teampilot/services/catalog/modules/mcp_catalog_module.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/storage/app_storage.dart';

void main() {
  late Directory tmp;
  late Directory workRoot;
  late LocalFilesystem workFs;
  late McpRepository repository;
  late WorkspaceProjectConfigRepository configRepo;
  late CatalogWorkspaceBinder binder;
  late CatalogMutationBus bus;
  late McpCatalogModule module;

  const workspaceId = 'ws1';

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('mcp_catalog_');
    workRoot = Directory.systemTemp.createTempSync('mcp_catalog_work_');
    final paths = AppPaths(tmp.path);
    AppStorage.installForTesting(
      filesystem: LocalFilesystem(
        pathContext: AppPaths.pathContextForDataRoot(paths.basePath),
      ),
      paths: paths,
      home: tmp.path,
      cwd: tmp.path,
    );
    workFs = LocalFilesystem();
    repository = McpRepository();
    configRepo = WorkspaceProjectConfigRepository();
    binder = CatalogWorkspaceBinder(repo: configRepo);
    bus = CatalogMutationBus();
    module = McpCatalogModule(repository: repository, binder: binder, bus: bus);
  });

  tearDown(() {
    AppStorage.resetForTesting();
    AppPathsBootstrapper.resetForTesting();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    if (workRoot.existsSync()) workRoot.deleteSync(recursive: true);
  });

  CatalogRequest req({
    Map<String, Object?> arguments = const {},
    List<String>? allowedRoots,
  }) => CatalogRequest(
    sessionId: 's',
    workspaceId: workspaceId,
    arguments: arguments,
    workFs: workFs,
    allowedRoots: allowedRoots ?? [workRoot.path],
  );

  test(
    'create_mcp upserts a stdio spec {name, command, args} and binds mcpServerIds',
    () async {
      CatalogMutationEvent? event;
      final sub = bus.listen().listen((e) => event = e);

      final result = await module.handle(
        CatalogOp.create,
        req(
          arguments: {
            'name': 'echo',
            'command': 'npx',
            'args': ['-y', 'foo'],
          },
        ),
      );

      expect(result.ok, isTrue);
      expect(result.kind, 'mcp');
      expect(result.ids, ['echo']);

      final saved = (await repository.loadAll()).single;
      expect(saved.id, 'echo');
      expect(saved.name, 'echo');
      expect(saved.server['type'], 'stdio');
      expect(saved.server['command'], 'npx');
      expect(saved.server['args'], ['-y', 'foo']);

      expect((await configRepo.load(workspaceId)).bundle.mcpServerIds, [
        'echo',
      ]);
      expect(event?.kind, 'mcp');
      expect(event?.op, CatalogOp.create);
      expect(event?.ids, ['echo']);
      expect(event?.workspaceId, workspaceId);
      await sub.cancel();
    },
  );

  test(
    'read_mcp returns spec with env values replaced by *** (keys remain)',
    () async {
      await repository.upsert(
        const McpServer(
          id: 'secret-mcp',
          name: 'secret-mcp',
          server: {
            'type': 'stdio',
            'command': 'npx',
            'env': {'API_KEY': 'super-secret', 'REGION': 'us-east'},
            'headers': {'Authorization': 'Bearer abc'},
          },
        ),
      );

      final result = await module.handle(
        CatalogOp.read,
        req(arguments: {'id': 'secret-mcp'}),
      );

      expect(result.ok, isTrue);
      expect(result.ids, ['secret-mcp']);
      final server = result.data?['server'] as Map<Object?, Object?>?;
      expect(server?['command'], 'npx');
      expect(server?['env'], {'API_KEY': '***', 'REGION': '***'});
      expect(server?['headers'], {'Authorization': '***'});
    },
  );

  test(
    'import_mcp reads a .mcp.json under allowedRoots with mcpServers.docs and upserts',
    () async {
      final src = File(p.join(workRoot.path, '.mcp.json'))
        ..writeAsStringSync(
          '{"mcpServers":{"docs":{"type":"http","url":"https://example.com/mcp"}}}',
        );

      CatalogMutationEvent? event;
      final sub = bus.listen().listen((e) => event = e);

      final result = await module.handle(
        CatalogOp.importPath,
        req(arguments: {'path': src.path}),
      );

      expect(result.ok, isTrue);
      expect(result.ids, ['docs']);

      final saved = (await repository.loadAll()).single;
      expect(saved.id, 'docs');
      expect(saved.name, 'docs');
      expect(saved.server['type'], 'http');
      expect(saved.server['url'], 'https://example.com/mcp');
      expect((await configRepo.load(workspaceId)).bundle.mcpServerIds, [
        'docs',
      ]);
      expect(event?.op, CatalogOp.importPath);
      expect(event?.ids, ['docs']);
      await sub.cancel();
    },
  );

  test(
    'install_mcp with injected listing draft function returns that id and binds',
    () async {
      const draftId = 'from-listing';
      module = McpCatalogModule(
        repository: repository,
        binder: binder,
        bus: bus,
        draftFromListing: (listingId) async => McpServer(
          id: draftId,
          name: draftId,
          server: const {'type': 'stdio', 'command': 'npx'},
        ),
      );

      CatalogMutationEvent? event;
      final sub = bus.listen().listen((e) => event = e);

      final result = await module.handle(
        CatalogOp.install,
        req(arguments: {'id': 'listing-1'}),
      );

      expect(result.ok, isTrue);
      expect(result.ids, [draftId]);
      expect((await repository.findById(draftId)), isNotNull);
      expect((await configRepo.load(workspaceId)).bundle.mcpServerIds, [
        draftId,
      ]);
      expect(event?.op, CatalogOp.install);
      expect(event?.ids, [draftId]);
      await sub.cancel();
    },
  );
}
