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
}
