import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/services/io/filesystem.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/storage/app_paths.dart';
import 'package:teampilot/services/storage/home_storage.dart';
import 'package:teampilot/services/storage/workspace_layout.dart';
import 'package:teampilot/utils/logging/logger.dart';

class _CountingFs implements Filesystem {
  _CountingFs(this._inner);
  final Filesystem _inner;
  int sessionJsonReads = 0;
  Object? failIndexWritesWith;

  bool _isSessionJson(String path) {
    final n = path.replaceAll('\\', '/');
    return n.endsWith('/session.json');
  }

  bool _isSessionsIndex(String path) {
    final n = path.replaceAll('\\', '/');
    return n.endsWith('/sessions-index.json');
  }

  void _throwIfIndexWrite(String path) {
    final error = failIndexWritesWith;
    if (error != null && _isSessionsIndex(path)) {
      Error.throwWithStackTrace(error, StackTrace.current);
    }
  }

  @override
  p.Context get pathContext => _inner.pathContext;

  @override
  Future<String?> readString(String path) async {
    if (_isSessionJson(path)) sessionJsonReads++;
    return _inner.readString(path);
  }

  @override
  Future<FsStat> stat(String path) => _inner.stat(path);

  @override
  Future<void> ensureDir(String path) => _inner.ensureDir(path);

  @override
  Future<void> removeRecursive(String path) => _inner.removeRecursive(path);

  @override
  Future<void> rename(String from, String to) => _inner.rename(from, to);

  @override
  Future<List<int>?> readBytes(String path) => _inner.readBytes(path);

  @override
  Future<void> writeString(String path, String content) {
    _throwIfIndexWrite(path);
    return _inner.writeString(path, content);
  }

  @override
  Future<void> writeBytes(String path, List<int> bytes) =>
      _inner.writeBytes(path, bytes);

  @override
  Future<List<int>?> readBytesRange(String path, int offset, int length) =>
      _inner.readBytesRange(path, offset, length);

  @override
  Future<void> appendBytes(String path, List<int> bytes) =>
      _inner.appendBytes(path, bytes);

  @override
  Future<void> atomicWrite(String path, String content) {
    _throwIfIndexWrite(path);
    return _inner.atomicWrite(path, content);
  }

  @override
  Future<List<FsDirEntry>> listDir(String path) => _inner.listDir(path);

  @override
  Future<bool> createSymlink({
    required String target,
    required String linkPath,
  }) => _inner.createSymlink(target: target, linkPath: linkPath);

  @override
  Future<String?> readSymlinkTarget(String linkPath) =>
      _inner.readSymlinkTarget(linkPath);

  @override
  Future<String?> resolveSymlink(String path) => _inner.resolveSymlink(path);

  @override
  Future<void> copyTree({
    required String source,
    required String destination,
  }) => _inner.copyTree(source: source, destination: destination);

  @override
  Future<void> copyFile(String source, String destination) =>
      _inner.copyFile(source, destination);

  @override
  Future<List<FsDirEntry>> listDirRecursive(String path) =>
      _inner.listDirRecursive(path);

  @override
  Future<String> createTempDir({String? prefix, String? parent}) =>
      _inner.createTempDir(prefix: prefix, parent: parent);

  @override
  Future<void> appendString(String path, String content) =>
      _inner.appendString(path, content);
}

HomeStorage _storage(Directory tmp, Filesystem fs) => HomeStorage.forTesting(
  filesystem: fs,
  paths: AppPaths(tmp.path),
  home: tmp.path,
  cwd: tmp.path,
);

Future<void> _plantSessions(Directory tmp, String workspaceId, int n) async {
  final root = '${tmp.path}/workspace/workspaces/$workspaceId/sessions';
  for (var i = 0; i < n; i++) {
    final dir = Directory('$root/seed-$i')..createSync(recursive: true);
    File('${dir.path}/session.json').writeAsStringSync(
      jsonEncode({
        'sessionId': 'seed-$i',
        'workspaceId': workspaceId,
        'display': 'Seed $i',
        'createdAt': i,
        'updatedAt': i,
        'folders': [
          {'path': '/tmp/ws', 'targetId': 'local'},
        ],
      }),
    );
  }
}

void main() {
  test('loadWorkspacesIndex rebuild does not read session.json', () async {
    final tmp = await Directory.systemTemp.createTemp('list_index_rebuild_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final inner = LocalFilesystem();
    final counting = _CountingFs(inner);
    final repo = SessionRepository(
      rootDir: tmp.path,
      storage: _storage(tmp, counting),
    );
    final ws = await repo.createWorkspace([WorkspaceFolder(path: '/tmp/ws')]);
    await _plantSessions(tmp, ws.workspaceId, 40);
    File(
      WorkspaceLayout(teampilotRoot: tmp.path, fs: inner).workspacesIndexFile,
    ).deleteSync();
    SessionRepository.debugResetWorkspacesIndexCache();
    counting.sessionJsonReads = 0;
    final fresh = SessionRepository(
      rootDir: tmp.path,
      storage: _storage(tmp, counting),
    );
    final indexed = await fresh.loadWorkspacesIndex();
    expect(indexed, isNotEmpty);
    expect(counting.sessionJsonReads, 0);
  });

  test(
    'loadSessionListForWorkspace hits sessions-index without reading session.json',
    () async {
      final tmp = await Directory.systemTemp.createTemp('list_index_hit_');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final inner = LocalFilesystem();
      final counting = _CountingFs(inner);
      final repo = SessionRepository(
        rootDir: tmp.path,
        storage: _storage(tmp, counting),
      );
      final ws = await repo.createWorkspace([WorkspaceFolder(path: '/tmp/ws')]);
      final created = (await repo.createSession(ws.workspaceId)).session;
      await _plantSessions(tmp, ws.workspaceId, 40);
      // 目录比索引多 → 第一次 list 会重建；再清计数测命中
      await repo.loadSessionListForWorkspace(ws.workspaceId);
      counting.sessionJsonReads = 0;
      final listed = await repo.loadSessionListForWorkspace(ws.workspaceId);
      expect(counting.sessionJsonReads, 0);
      expect(listed.map((s) => s.sessionId), contains(created.sessionId));
      expect(
        listed.firstWhere((s) => s.sessionId == created.sessionId).folders,
        isEmpty,
      );
      final full = await repo.loadSession(ws.workspaceId, created.sessionId);
      expect(full!.folders, isNotEmpty);
    },
  );

  test('createSession and deleteSession keep sessions-index in lockstep', () async {
    final tmp = await Directory.systemTemp.createTemp('list_index_mutate_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final inner = LocalFilesystem();
    final counting = _CountingFs(inner);
    final repo = SessionRepository(
      rootDir: tmp.path,
      storage: _storage(tmp, counting),
    );
    final ws = await repo.createWorkspace([WorkspaceFolder(path: '/tmp/ws')]);
    final created = (await repo.createSession(ws.workspaceId)).session;
    counting.sessionJsonReads = 0;
    final listed = await repo.loadSessionListForWorkspace(ws.workspaceId);
    expect(listed.single.sessionId, created.sessionId);
    expect(counting.sessionJsonReads, 0);
    await repo.deleteSession(created.sessionId);
    expect(await repo.loadSessionListForWorkspace(ws.workspaceId), isEmpty);
    counting.sessionJsonReads = 0;
    expect(await repo.loadSessionListForWorkspace(ws.workspaceId), isEmpty);
    expect(counting.sessionJsonReads, 0);
  });

  test(
    'createSession and deleteSession succeed when derived index write fails',
    () async {
      final tmp = await Directory.systemTemp.createTemp('list_index_fail_');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final inner = LocalFilesystem();
      final counting = _CountingFs(inner);
      final repo = SessionRepository(
        rootDir: tmp.path,
        storage: _storage(tmp, counting),
      );
      final ws = await repo.createWorkspace([WorkspaceFolder(path: '/tmp/ws')]);
      counting.failIndexWritesWith = StateError('SFTP channel closed');

      final created = (await repo.createSession(ws.workspaceId)).session;
      expect(created.sessionId, isNotEmpty);
      final onDisk = await repo.loadSession(ws.workspaceId, created.sessionId);
      expect(onDisk, isNotNull);

      await repo.deleteSession(created.sessionId);
      expect(await repo.loadSession(ws.workspaceId, created.sessionId), isNull);
    },
  );

  test('rebuild logs once when written ids do not match directory ids', () async {
    final tmp = await Directory.systemTemp.createTemp('list_index_parity_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final inner = LocalFilesystem();
    final counting = _CountingFs(inner);
    final repo = SessionRepository(
      rootDir: tmp.path,
      storage: _storage(tmp, counting),
    );
    final ws = await repo.createWorkspace([WorkspaceFolder(path: '/tmp/ws')]);
    await _plantSessions(tmp, ws.workspaceId, 1);
    final corrupt = Directory(
      '${tmp.path}/workspace/workspaces/${ws.workspaceId}/sessions/corrupt-id',
    )..createSync(recursive: true);
    File('${corrupt.path}/session.json').writeAsStringSync('not-json');
    File(
      WorkspaceLayout(
        teampilotRoot: tmp.path,
        fs: inner,
      ).sessionsIndexFile(ws.workspaceId),
    ).writeAsStringSync('{"version":1,"sessions":[]}');

    final before = await appLogger.getPendingLogLines();
    final listed = await repo.loadSessionListForWorkspace(ws.workspaceId);
    expect(listed.map((s) => s.sessionId), ['seed-0']);
    final lines = await appLogger.getPendingLogLines();
    expect(
      lines.skip(before.length).where((l) => l.contains('rebuild parity')),
      hasLength(1),
    );
  });
}
