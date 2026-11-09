import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/services/storage/app_paths.dart';
import 'package:teampilot/services/storage/home_storage.dart';
import 'package:teampilot/services/storage/runtime_context.dart';

import '../support/in_memory_filesystem.dart';

RuntimeContext _context(
  InMemoryFilesystem fs, {
  required String appDataRoot,
  RuntimeTarget? target,
}) => RuntimeContext(
  target: target ?? RuntimeTarget.local(),
  filesystem: fs,
  home: '/home/test',
  cwd: '/home/test',
  appDataRoot: appDataRoot,
  paths: AppPaths(appDataRoot),
);

void main() {
  test(
    'same root string on another plane does not leak the workspace index',
    () async {
      final fsA = InMemoryFilesystem();
      final fsB = InMemoryFilesystem();
      // Two remote hosts with the same user name resolve the same root string.
      const root = '/home/ubuntu/.teampilot';

      final repoA = SessionRepository(
        rootDir: root,
        storage: fakeHomeStorage(filesystem: fsA, appDataRoot: root),
      );
      final repoB = SessionRepository(
        rootDir: root,
        storage: fakeHomeStorage(filesystem: fsB, appDataRoot: root),
      );

      final workspace = await repoA.createWorkspace([
        const WorkspaceFolder(path: '/srv/app-a'),
      ]);
      final indexA = await repoA.loadWorkspacesIndex();
      expect(indexA.map((w) => w.workspaceId), [workspace.workspaceId]);

      final indexB = await repoB.loadWorkspacesIndex();
      expect(indexB, isEmpty);
    },
  );

  group('home swap', () {
    test('the previous plane index is not served after a swap', () async {
      final fsA = InMemoryFilesystem();
      final fsB = InMemoryFilesystem();
      final contextA = _context(fsA, appDataRoot: '/plane-a');
      final storage = HomeStorage(contextA);
      final repo = SessionRepository(storage: storage);

      final workspaceA = await repo.createWorkspace([
        const WorkspaceFolder(path: '/srv/app-a'),
      ]);
      final indexA = await repo.loadWorkspacesIndex();
      expect(indexA.map((w) => w.workspaceId), [workspaceA.workspaceId]);

      await storage.swap(_context(fsB, appDataRoot: '/plane-b'));

      expect(await repo.loadWorkspacesIndex(), isEmpty);
    });

    test('swapping back reloads the original plane instead of its old '
        'snapshot', () async {
      final fsA = InMemoryFilesystem();
      final fsB = InMemoryFilesystem();
      final contextA = _context(fsA, appDataRoot: '/plane-a');
      final storage = HomeStorage(contextA);
      final repo = SessionRepository(storage: storage);

      final workspaceA = await repo.createWorkspace([
        const WorkspaceFolder(path: '/srv/app-a'),
      ]);
      await repo.loadWorkspacesIndex();

      await storage.swap(_context(fsB, appDataRoot: '/plane-b'));
      expect(await repo.loadWorkspacesIndex(), isEmpty);
      final workspaceB = await repo.createWorkspace([
        const WorkspaceFolder(path: '/srv/app-b'),
      ]);
      final indexB = await repo.loadWorkspacesIndex();
      expect(indexB.map((w) => w.workspaceId), [workspaceB.workspaceId]);

      await storage.swap(contextA);

      final indexA = await repo.loadWorkspacesIndex();
      expect(indexA.map((w) => w.workspaceId), [workspaceA.workspaceId]);
    });

    test(
      'the same app-data root on another target is a different plane',
      () async {
        final fsA = InMemoryFilesystem();
        final fsB = InMemoryFilesystem();
        // Two hosts whose user resolves the identical root string.
        const root = '/home/ubuntu/.teampilot';
        final storage = HomeStorage(_context(fsA, appDataRoot: root));
        final repo = SessionRepository(storage: storage);

        final workspaceA = await repo.createWorkspace([
          const WorkspaceFolder(path: '/srv/app-a'),
        ]);
        final indexA = await repo.loadWorkspacesIndex();
        expect(indexA.map((w) => w.workspaceId), [workspaceA.workspaceId]);

        await storage.swap(
          _context(
            fsB,
            appDataRoot: root,
            target: RuntimeTarget.ssh('studio', label: 'Studio'),
          ),
        );

        expect(await repo.loadWorkspacesIndex(), isEmpty);
      },
    );
  });
}
