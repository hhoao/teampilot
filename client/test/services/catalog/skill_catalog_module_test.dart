import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/config_bundle.dart';
import 'package:teampilot/repositories/skill_repository.dart';
import 'package:teampilot/repositories/workspace_project_config_repository.dart';
import 'package:teampilot/services/catalog/catalog_kind.dart';
import 'package:teampilot/services/catalog/catalog_mutation_bus.dart';
import 'package:teampilot/services/catalog/catalog_workspace_binder.dart';
import 'package:teampilot/services/catalog/modules/skill_catalog_module.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/skill/skill_install_service.dart';
import 'package:teampilot/services/skill/skill_manifest_service.dart';
import 'package:teampilot/services/storage/app_storage.dart';

void main() {
  late Directory tmp;
  late Directory workRoot;
  late LocalFilesystem workFs;
  late SkillManifestService manifest;
  late SkillInstallService install;
  late SkillRepository repository;
  late WorkspaceProjectConfigRepository configRepo;
  late CatalogWorkspaceBinder binder;
  late CatalogMutationBus bus;
  late SkillCatalogModule module;

  const workspaceId = 'ws1';

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('skill_catalog_');
    workRoot = Directory.systemTemp.createTempSync('skill_catalog_work_');
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
    manifest = SkillManifestService(rootDir: tmp.path);
    install = SkillInstallService(manifest: manifest);
    repository = SkillRepository(manifest: manifest, install: install);
    configRepo = WorkspaceProjectConfigRepository();
    binder = CatalogWorkspaceBinder(repo: configRepo);
    bus = CatalogMutationBus();
    module = SkillCatalogModule(
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

  Map<String, Uint8List> fooPayload() => {
    'SKILL.md': Uint8List.fromList(
      '---\nname: foo\ndescription: d\n---\nbody'.codeUnits,
    ),
  };

  String installedSkillMd(String dir) =>
      p.join(tmp.path, 'skills/installed', dir, 'SKILL.md');

  test(
    'create_skill writes SKILL.md, binds workspace, and emits bus event',
    () async {
      CatalogMutationEvent? event;
      final sub = bus.listen().listen((e) => event = e);

      final result = await module.handle(
        CatalogOp.create,
        req(
          arguments: {
            'name': 'Hello Skill',
            'directory': 'hello-skill',
            'body': 'Do the thing.',
          },
        ),
      );

      expect(result.ok, isTrue);
      expect(result.kind, 'skill');
      expect(result.ids, ['local:hello-skill']);
      expect(result.restartRequired, isTrue);

      final skillMd = File(installedSkillMd('hello-skill'));
      expect(skillMd.existsSync(), isTrue);
      expect(skillMd.readAsStringSync(), contains('Hello Skill'));
      expect(skillMd.readAsStringSync(), contains('Do the thing.'));

      expect((await repository.loadInstalled()).single.id, 'local:hello-skill');
      expect((await configRepo.load(workspaceId)).bundle.skillIds, [
        'local:hello-skill',
      ]);

      expect(event, isNotNull);
      expect(event!.kind, 'skill');
      expect(event!.op, CatalogOp.create);
      expect(event!.ids, ['local:hello-skill']);
      expect(event!.workspaceId, workspaceId);
      await sub.cancel();
    },
  );

  test('import_skill copies a SKILL.md directory and binds', () async {
    final src = Directory(p.join(workRoot.path, 'my-skill'))..createSync();
    File(p.join(src.path, 'SKILL.md')).writeAsStringSync(
      '---\nname: Imported\ndescription: d\n---\nimported body',
    );
    File(p.join(src.path, 'notes.txt')).writeAsStringSync('extra');

    CatalogMutationEvent? event;
    final sub = bus.listen().listen((e) => event = e);

    final result = await module.handle(
      CatalogOp.importPath,
      req(arguments: {'path': src.path}),
    );

    expect(result.ok, isTrue);
    expect(result.ids, ['local:my-skill']);
    expect(File(installedSkillMd('my-skill')).existsSync(), isTrue);
    expect(
      File(
        p.join(tmp.path, 'skills/installed/my-skill/notes.txt'),
      ).existsSync(),
      isTrue,
    );
    expect((await repository.loadInstalled()).single.id, 'local:my-skill');
    expect((await configRepo.load(workspaceId)).bundle.skillIds, [
      'local:my-skill',
    ]);
    expect(event?.op, CatalogOp.importPath);
    expect(event?.ids, ['local:my-skill']);
    await sub.cancel();
  });

  test('import_skill path outside allowedRoots throws unsafe_path', () async {
    await expectLater(
      module.handle(
        CatalogOp.importPath,
        req(arguments: {'path': '/etc/passwd'}),
      ),
      throwsA(
        isA<CatalogException>().having((e) => e.code, 'code', 'unsafe_path'),
      ),
    );
  });

  test('import_skill with no SKILL.md throws no_skill_md', () async {
    final empty = Directory(p.join(workRoot.path, 'empty'))..createSync();
    File(p.join(empty.path, 'readme.txt')).writeAsStringSync('no skill');

    await expectLater(
      module.handle(CatalogOp.importPath, req(arguments: {'path': empty.path})),
      throwsA(
        isA<CatalogException>().having((e) => e.code, 'code', 'no_skill_md'),
      ),
    );
  });

  test('delete_skill removes manifest row and unbinds', () async {
    await install.installLocal(
      basename: 'foo',
      files: fooPayload(),
      repoOwner: null,
      repoName: null,
      repoBranch: null,
      readmeUrl: null,
      name: 'foo',
      description: 'd',
    );
    await binder.bindIds(
      workspaceId: workspaceId,
      bindTo: CatalogBindTo.workspace,
      apply: (ConfigBundle current) => current.skillIds.add('local:foo'),
    );

    final result = await module.handle(
      CatalogOp.delete,
      req(arguments: {'id': 'local:foo'}),
    );

    expect(result.ok, isTrue);
    expect(await repository.loadInstalled(), isEmpty);
    expect((await configRepo.load(workspaceId)).bundle.skillIds, isEmpty);
    expect(
      Directory(p.join(tmp.path, 'skills/installed/foo')).existsSync(),
      isFalse,
    );
  });

  test('install_skill when id already installed only binds', () async {
    await install.installLocal(
      basename: 'foo',
      files: fooPayload(),
      repoOwner: null,
      repoName: null,
      repoBranch: null,
      readmeUrl: null,
      name: 'foo',
      description: 'd',
    );
    final before = File(installedSkillMd('foo')).readAsStringSync();

    CatalogMutationEvent? event;
    final sub = bus.listen().listen((e) => event = e);

    final result = await module.handle(
      CatalogOp.install,
      req(arguments: {'id': 'local:foo'}),
    );

    expect(result.ok, isTrue);
    expect(result.ids, ['local:foo']);
    expect(File(installedSkillMd('foo')).readAsStringSync(), before);
    expect((await repository.loadInstalled()), hasLength(1));
    expect((await configRepo.load(workspaceId)).bundle.skillIds, ['local:foo']);
    expect(event?.op, CatalogOp.install);
    expect(event?.ids, ['local:foo']);
    await sub.cancel();
  });

  test('advertise() has no unexpected names', () {
    expect(
      module.advertise().map((t) => t.name),
      unorderedEquals([
        'search_skills',
        'read_skill',
        'install_skill',
        'import_skill',
        'create_skill',
        'update_skill',
        'unbind_skill',
        'delete_skill',
      ]),
    );
    expect(module.kind, 'skill');
    expect(module.supportsCreate, isTrue);
  });

  test('list boundIds includes id after create_skill', () async {
    await module.handle(CatalogOp.list, req());
    await module.handle(
      CatalogOp.create,
      req(
        arguments: {
          'name': 'Hello Skill',
          'directory': 'hello-skill',
          'body': 'Do the thing.',
        },
      ),
    );

    final listed = await module.handle(CatalogOp.list, req());
    final skill = listed.data?['skill'] as Map<Object?, Object?>?;
    expect(skill?['boundIds'], contains('local:hello-skill'));
  });

  test(
    'create_skill rejects directory that escapes skills/installed',
    () async {
      await expectLater(
        module.handle(
          CatalogOp.create,
          req(
            arguments: {
              'name': 'Escape',
              'directory': '../escape',
              'body': 'nope',
            },
          ),
        ),
        throwsA(
          isA<CatalogException>().having((e) => e.code, 'code', 'unsafe_path'),
        ),
      );
      expect(
        File(p.join(tmp.path, 'skills/escape/SKILL.md')).existsSync(),
        isFalse,
      );
      expect(
        File(
          p.join(tmp.path, 'skills/installed/../escape/SKILL.md'),
        ).existsSync(),
        isFalse,
      );
    },
  );

  test(
    'create_skill rejects files keys that escape the install directory',
    () async {
      await expectLater(
        module.handle(
          CatalogOp.create,
          req(
            arguments: {
              'name': 'Bad Files',
              'directory': 'safe-skill',
              'body': 'body',
              'files': {'../x': 'escaped'},
            },
          ),
        ),
        throwsA(
          isA<CatalogException>().having((e) => e.code, 'code', 'unsafe_path'),
        ),
      );
      expect(
        File(p.join(tmp.path, 'skills/installed/x')).existsSync(),
        isFalse,
      );
    },
  );

  test(
    'update_skill rejects files keys with parent or separator paths',
    () async {
      await install.installLocal(
        basename: 'foo',
        files: fooPayload(),
        repoOwner: null,
        repoName: null,
        repoBranch: null,
        readmeUrl: null,
        name: 'foo',
        description: 'd',
      );

      await expectLater(
        module.handle(
          CatalogOp.update,
          req(
            arguments: {
              'id': 'local:foo',
              'files': {'foo/../x': 'escaped'},
            },
          ),
        ),
        throwsA(
          isA<CatalogException>().having((e) => e.code, 'code', 'unsafe_path'),
        ),
      );
    },
  );
}
