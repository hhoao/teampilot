import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/repositories/index_snapshot_isolate.dart';
import 'package:teampilot/repositories/session_repository_fs.dart';
import 'package:teampilot/repositories/workspace_index_store.dart';
import 'package:teampilot/services/io/local_filesystem.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('workspace_index_store_');
  });

  tearDown(() {
    IndexSnapshotIsolate.debugWorkspacesReaderOverride = null;
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Workspace _workspace(String id) => Workspace(
    workspaceId: id,
    folders: [WorkspaceFolder(path: '/tmp/$id')],
    display: id,
    createdAt: 1,
    updatedAt: 1,
  );

  test(
    'boot tryRead completes even when isolate index reader never returns',
    () async {
      IndexSnapshotIsolate.debugWorkspacesReaderOverride = (_) =>
          Completer<List<Map<String, Object?>>?>().future;

      final store = WorkspaceIndexStore(
        SessionRepositoryFs(
          teampilotRoot: tmp.path,
          fs: LocalFilesystem(),
        ),
      );
      await store.upsert(_workspace('ws-1'));

      final loaded = await store
          .tryRead()
          .timeout(const Duration(seconds: 2));
      expect(loaded, isNotNull);
      expect(loaded!.single.workspaceId, 'ws-1');
    },
  );

  test(
    'upsert completes even when isolate index reader never returns',
    () async {
      IndexSnapshotIsolate.debugWorkspacesReaderOverride = (_) =>
          Completer<List<Map<String, Object?>>?>().future;

      final store = WorkspaceIndexStore(
        SessionRepositoryFs(
          teampilotRoot: tmp.path,
          fs: LocalFilesystem(),
        ),
      );
      final workspace = _workspace('ws-1');

      await store
          .upsert(workspace)
          .timeout(const Duration(seconds: 2));

      final loaded = await store.tryRead(preferIsolate: false);
      expect(loaded, isNotNull);
      expect(loaded!.single.workspaceId, 'ws-1');
    },
  );

  test('concurrent upserts keep every workspace', () async {
    final store = WorkspaceIndexStore(
      SessionRepositoryFs(
        teampilotRoot: tmp.path,
        fs: LocalFilesystem(),
      ),
    );

    await Future.wait([
      store.upsert(_workspace('a')),
      store.upsert(_workspace('b')),
      store.upsert(_workspace('c')),
    ]);

    final loaded = await store.tryRead(preferIsolate: false);
    expect(
      loaded!.map((w) => w.workspaceId).toSet(),
      {'a', 'b', 'c'},
    );
  });

  test('tryRead upgrades legacy primaryPath into a local folder', () async {
    final store = WorkspaceIndexStore(
      SessionRepositoryFs(
        teampilotRoot: tmp.path,
        fs: LocalFilesystem(),
      ),
    );
    // Pre-June-2026 manifest shape: empty folders + bare primaryPath.
    // Without the upgrade every session in this workspace resolves an empty
    // cwd, which fails Windows PTY process creation.
    final workspaceDir = Directory(
      '${tmp.path}${Platform.pathSeparator}workspace',
    )..createSync();
    File(
      '${workspaceDir.path}${Platform.pathSeparator}workspaces-index.json',
    ).writeAsStringSync('''
{
  "version": 1,
  "updatedAt": 1,
  "workspaces": [
    {
      "workspaceId": "legacy",
      "folders": [],
      "primaryPath": "C:\\\\Users\\\\dev\\\\Documents\\\\TeamPilot",
      "createdAt": 1
    }
  ]
}
''');

    final loaded = await store.tryRead(preferIsolate: false);
    expect(loaded, isNotNull);
    final legacy = loaded!.single;
    expect(legacy.workspaceId, 'legacy');
    expect(legacy.folders, hasLength(1));
    expect(
      legacy.folders.first.path,
      r'C:\Users\dev\Documents\TeamPilot',
    );
    expect(
      legacy.folders.first.targetId,
      WorkspaceFolder.localTargetId,
    );
    expect(
      legacy.firstFolderPath,
      r'C:\Users\dev\Documents\TeamPilot',
    );
  });

  test('upgradeLegacyPrimaryPath keeps non-empty folders untouched', () {
    final map = <String, Object?>{
      'workspaceId': 'modern',
      'folders': [
        {'path': '/main', 'targetId': 'local'},
      ],
      'primaryPath': '/elsewhere',
    };
    final upgraded = WorkspaceIndexStore.upgradeLegacyPrimaryPath(map);
    expect(upgraded, same(map));
  });

  test('upgradeLegacyPrimaryPath leaves empty workspaces alone', () {
    final map = <String, Object?>{'workspaceId': 'empty', 'folders': []};
    final upgraded = WorkspaceIndexStore.upgradeLegacyPrimaryPath(map);
    expect(upgraded, same(map));
  });
}
