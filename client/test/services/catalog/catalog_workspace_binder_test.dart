import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/config_bundle.dart';
import 'package:teampilot/repositories/workspace_project_config_repository.dart';
import 'package:teampilot/services/catalog/catalog_kind.dart';
import 'package:teampilot/services/catalog/catalog_workspace_binder.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/storage/app_storage.dart';

void main() {
  late Directory tmp;
  late CatalogWorkspaceBinder binder;
  late WorkspaceProjectConfigRepository repo;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('catalog_binder_');
    final paths = AppPaths(tmp.path);
    AppStorage.installForTesting(
      filesystem: LocalFilesystem(
        pathContext: AppPaths.pathContextForDataRoot(paths.basePath),
      ),
      paths: paths,
      home: tmp.path,
      cwd: tmp.path,
    );
    repo = WorkspaceProjectConfigRepository();
    binder = CatalogWorkspaceBinder(repo: repo);
  });

  tearDown(() {
    AppStorage.resetForTesting();
    AppPathsBootstrapper.resetForTesting();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  const workspaceId = 'ws1';

  test('bind skillIds is persisted and idempotent', () async {
    await binder.bindIds(
      workspaceId: workspaceId,
      bindTo: CatalogBindTo.workspace,
      apply: (ConfigBundle current) => current.skillIds.add('a'),
    );
    expect((await repo.load(workspaceId)).bundle.skillIds, ['a']);

    await binder.bindIds(
      workspaceId: workspaceId,
      bindTo: CatalogBindTo.workspace,
      apply: (ConfigBundle current) => current.skillIds.add('a'),
    );
    expect((await repo.load(workspaceId)).bundle.skillIds, ['a']);
  });

  test('non-workspace bindTo throws bind_scope_unsupported', () async {
    await expectLater(
      binder.bindIds(
        workspaceId: workspaceId,
        bindTo: CatalogBindTo.team,
        apply: (ConfigBundle current) => current.skillIds.add('a'),
      ),
      throwsA(
        isA<CatalogException>().having(
          (e) => e.code,
          'code',
          'bind_scope_unsupported',
        ),
      ),
    );
  });

  test('unbind removes the id', () async {
    await binder.bindIds(
      workspaceId: workspaceId,
      bindTo: CatalogBindTo.workspace,
      apply: (ConfigBundle current) => current.skillIds.add('a'),
    );
    await binder.unbindIds(
      workspaceId: workspaceId,
      bindTo: CatalogBindTo.workspace,
      apply: (ConfigBundle current) => current.skillIds.remove('a'),
    );
    expect((await repo.load(workspaceId)).bundle.skillIds, isEmpty);
  });
}
