import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/repositories/plugin_repository.dart';
import 'package:teampilot/repositories/workspace_project_config_repository.dart';
import 'package:teampilot/services/catalog/catalog_kind.dart';
import 'package:teampilot/services/catalog/catalog_mutation_bus.dart';
import 'package:teampilot/services/catalog/catalog_workspace_binder.dart';
import 'package:teampilot/services/catalog/modules/plugin_catalog_module.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/plugin/plugin_install_service.dart';
import 'package:teampilot/services/plugin/plugin_manifest_service.dart';
import 'package:teampilot/services/storage/app_storage.dart';

void main() {
  late Directory tmp;
  late Directory workRoot;
  late LocalFilesystem workFs;
  late PluginManifestService manifest;
  late PluginInstallService install;
  late PluginRepository repository;
  late WorkspaceProjectConfigRepository configRepo;
  late CatalogWorkspaceBinder binder;
  late CatalogMutationBus bus;
  late PluginCatalogModule module;

  const workspaceId = 'ws1';

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('plugin_catalog_');
    workRoot = Directory.systemTemp.createTempSync('plugin_catalog_work_');
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
    manifest = PluginManifestService();
    install = PluginInstallService(manifestService: manifest);
    repository = PluginRepository(manifest: manifest, install: install);
    configRepo = WorkspaceProjectConfigRepository();
    binder = CatalogWorkspaceBinder(repo: configRepo);
    bus = CatalogMutationBus();
    module = PluginCatalogModule(
      repository: repository,
      install: install,
      binder: binder,
      bus: bus,
      workspaceConfig: configRepo,
    );
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

  test('advertise() contains install_plugin, import_plugin, delete_plugin; '
      'does not contain create_plugin', () {
    final names = module.advertise().map((t) => t.name).toList();
    expect(names, contains('install_plugin'));
    expect(names, contains('import_plugin'));
    expect(names, contains('delete_plugin'));
    expect(names, isNot(contains('create_plugin')));
    expect(module.kind, 'plugin');
    expect(module.supportsCreate, isFalse);
  });

  test(
    'import_plugin of a dir with plugin.json installs and binds pluginIds',
    () async {
      final src = Directory(p.join(workRoot.path, 'demo'))..createSync();
      File(
        p.join(src.path, 'plugin.json'),
      ).writeAsStringSync('{ "name": "demo" }');

      CatalogMutationEvent? event;
      final sub = bus.listen().listen((e) => event = e);

      final result = await module.handle(
        CatalogOp.importPath,
        req(arguments: {'path': src.path}),
      );

      expect(result.ok, isTrue);
      expect(result.kind, 'plugin');
      expect(result.ids, ['local/demo']);
      expect((await repository.loadAll()).single.id, 'local/demo');
      expect((await repository.loadAll()).single.name, 'demo');
      expect((await configRepo.load(workspaceId)).bundle.pluginIds, [
        'local/demo',
      ]);
      expect(event?.op, CatalogOp.importPath);
      expect(event?.ids, ['local/demo']);
      expect(event?.kind, 'plugin');
      expect(event?.workspaceId, workspaceId);
      await sub.cancel();
    },
  );

  test('import_plugin of a skill-only dir throws wrong_kind', () async {
    final src = Directory(p.join(workRoot.path, 'my-skill'))..createSync();
    File(
      p.join(src.path, 'SKILL.md'),
    ).writeAsStringSync('---\nname: Imported\ndescription: d\n---\nbody');

    await expectLater(
      module.handle(CatalogOp.importPath, req(arguments: {'path': src.path})),
      throwsA(
        isA<CatalogException>().having((e) => e.code, 'code', 'wrong_kind'),
      ),
    );
  });

  test('handle(CatalogOp.create) throws unsupported_op', () async {
    await expectLater(
      module.handle(CatalogOp.create, req(arguments: {'name': 'demo'})),
      throwsA(
        isA<CatalogException>().having((e) => e.code, 'code', 'unsupported_op'),
      ),
    );
  });

  test(
    'install_plugin with a discovery stub actually installs and binds',
    () async {
      final src = Directory(p.join(workRoot.path, 'demo'))..createSync();
      File(
        p.join(src.path, 'plugin.json'),
      ).writeAsStringSync('{ "name": "demo" }');

      module = PluginCatalogModule(
        repository: repository,
        install: install,
        binder: binder,
        bus: bus,
        workspaceConfig: configRepo,
        installFromDiscovery: (args) async {
          expect(args['id'], 'market/demo');
          return install.installFromDirectory(src);
        },
      );

      final result = await module.handle(
        CatalogOp.install,
        req(arguments: {'id': 'market/demo'}),
      );

      expect(result.ok, isTrue);
      expect(result.ids, ['local/demo']);
      expect((await repository.loadAll()).single.id, 'local/demo');
      expect((await configRepo.load(workspaceId)).bundle.pluginIds, [
        'local/demo',
      ]);
    },
  );
}
