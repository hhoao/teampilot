import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/config_bundle.dart';
import 'package:teampilot/repositories/workspace_project_config_repository.dart';
import 'package:teampilot/services/catalog/catalog_kind.dart';
import 'package:teampilot/services/catalog/catalog_workspace_binder.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/storage/app_paths.dart';
import '../../support/test_runtime_context.dart';
import 'package:teampilot/services/storage/home_storage.dart';

void main() {
  late Directory tmp;
  late CatalogWorkspaceBinder binder;
  late WorkspaceProjectConfigRepository repo;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('catalog_binder_');
    final paths = AppPaths(tmp.path);
    installTestHomeStorage(
      filesystem: LocalFilesystem(
        pathContext: AppPaths.pathContextForDataRoot(paths.basePath),
      ),
      paths: paths,
      home: tmp.path,
      cwd: tmp.path,
    );
    repo = WorkspaceProjectConfigRepository(
      storage: HomeStorage(testHomeStorage.context),
    );
    binder = CatalogWorkspaceBinder(repo: repo);
  });

  tearDown(() {
    resetTestHomeStorage();
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

  test(
    'unbindMcpFromAllWorkspaces drops the id from every workspace',
    () async {
      await binder.bindIds(
        workspaceId: 'ws-a',
        bindTo: CatalogBindTo.workspace,
        apply: (ConfigBundle current) {
          current.mcpServerIds.add('vscode-mcp');
          current.mcpServerIds.add('keep');
        },
      );
      await binder.bindIds(
        workspaceId: 'ws-b',
        bindTo: CatalogBindTo.workspace,
        apply: (ConfigBundle current) => current.mcpServerIds.add('vscode-mcp'),
      );
      await binder.bindIds(
        workspaceId: 'ws-c',
        bindTo: CatalogBindTo.workspace,
        apply: (ConfigBundle current) => current.mcpServerIds.add('keep'),
      );

      final changed = await binder.unbindMcpFromAllWorkspaces('vscode-mcp');

      expect(changed, unorderedEquals(['ws-a', 'ws-b']));
      expect((await repo.load('ws-a')).bundle.mcpServerIds, ['keep']);
      expect((await repo.load('ws-b')).bundle.mcpServerIds, isEmpty);
      expect((await repo.load('ws-c')).bundle.mcpServerIds, ['keep']);
    },
  );
}
