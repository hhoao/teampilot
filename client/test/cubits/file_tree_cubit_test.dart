import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/cubits/file_tree_cubit.dart';
import 'package:teampilot/cubits/file_tree_root_mount.dart';
import 'package:teampilot/services/io/filesystem.dart';

class _FakeFilesystem implements Filesystem {
  _FakeFilesystem(this._dirs);

  final Map<String, List<FsDirEntry>> _dirs;

  @override
  final p.Context pathContext = p.Context();

  @override
  Future<FsStat> stat(String path) async {
    if (_dirs.containsKey(path)) {
      return const FsStat(kind: FsEntityKind.directory);
    }
    return const FsStat(kind: FsEntityKind.file, size: 1);
  }

  @override
  Future<void> ensureDir(String path) async {}

  @override
  Future<void> removeRecursive(String path) async {}

  @override
  Future<void> rename(String from, String to) async {}

  @override
  Future<String?> readString(String path) async => '';

  @override
  Future<List<int>?> readBytes(String path) async => [];

  @override
  Future<void> writeString(String path, String content) async {}

  @override
  Future<void> writeBytes(String path, List<int> bytes) async {}

  @override
  Future<void> atomicWrite(String path, String content) async {}

  @override
  Future<List<FsDirEntry>> listDir(String path) async => _dirs[path] ?? [];

  @override
  Future<bool> createSymlink({
    required String target,
    required String linkPath,
  }) async =>
      false;

  @override
  Future<String?> readSymlinkTarget(String linkPath) async => null;

  @override
  Future<String?> resolveSymlink(String path) async => null;

  @override
  Future<void> copyTree({
    required String source,
    required String destination,
  }) async {}

  @override
  Future<void> copyFile(String source, String destination) async {}

  @override
  Future<List<FsDirEntry>> listDirRecursive(String path) async =>
      listDir(path);

  @override
  Future<String> createTempDir({String? prefix, String? parent}) async =>
      '/tmp';

  @override
  Future<void> appendString(String path, String content) async {}
}

void main() {
  test('collapseAllFolders clears expanded paths', () async {
    final root = p.normalize('/proj');
    final src = p.join(root, 'src');
    final cubit = FileTreeCubit(
      fs: _FakeFilesystem({
        root: [const FsDirEntry(name: 'src', isDirectory: true)],
        src: [const FsDirEntry(name: 'main.dart', isDirectory: false)],
      }),
    );

    await cubit.setRoot(root);
    cubit.toggleExpand(src);
    expect(cubit.state.expandedPaths, {src});

    cubit.collapseAllFolders();
    expect(cubit.state.expandedPaths, isEmpty);

    // Let the in-flight directory load finish before closing the cubit.
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await cubit.close();
  });

  test('refreshPaths reloads only relevant directories without flashing',
      () async {
    final root = p.normalize('/proj');
    final src = p.join(root, 'src');
    final fs = _FakeFilesystem({
      root: [const FsDirEntry(name: 'src', isDirectory: true)],
      src: [const FsDirEntry(name: 'main.dart', isDirectory: false)],
    });
    final cubit = FileTreeCubit(fs: fs);

    await cubit.setRoot(root);
    cubit.toggleExpand(src);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(cubit.entriesFor(src).map((e) => e.name), ['main.dart']);

    // A new file lands in src on disk.
    fs._dirs[src] = const [
      FsDirEntry(name: 'main.dart', isDirectory: false),
      FsDirEntry(name: 'extra.dart', isDirectory: false),
    ];

    final states = <FileTreeState>[];
    final sub = cubit.stream.listen(states.add);

    // Targeting an unloaded/irrelevant dir is a no-op (no emit, no reload).
    await cubit.refreshPaths({p.join(root, 'unrelated')});
    await Future<void>.delayed(const Duration(milliseconds: 5));
    expect(states, isEmpty);

    // Targeting the loaded dir reloads it in a single emit, and the cache entry
    // is never cleared to empty in between (no flash).
    await cubit.refreshPaths({src});
    await Future<void>.delayed(const Duration(milliseconds: 5));
    expect(states.length, 1);
    expect(states.every((s) => s.dirCache[src]?.isNotEmpty ?? false), isTrue);
    expect(cubit.entriesFor(src).map((e) => e.name), ['extra.dart', 'main.dart']);

    await sub.cancel();
    await cubit.close();
  });

  test('setRoots mounts multiple workspace folders, each expanded by default',
      () async {
    final a = p.normalize('/projA');
    final b = p.normalize('/projB');
    final cubit = FileTreeCubit(
      fs: _FakeFilesystem({
        a: [const FsDirEntry(name: 'a.dart', isDirectory: false)],
        b: [const FsDirEntry(name: 'b.dart', isDirectory: false)],
      }),
    );

    await cubit.setRoots([a, b]);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(cubit.state.isMultiRoot, isTrue);
    expect(cubit.state.rootPaths, [a, b]);
    // Both existing roots start expanded so their contents are visible.
    expect(cubit.state.expandedPaths, {a, b});
    expect(cubit.entriesFor(a).map((e) => e.name), ['a.dart']);
    expect(cubit.entriesFor(b).map((e) => e.name), ['b.dart']);

    await cubit.close();
  });

  test('setRoots with a single folder stays single-root (no header expansion)',
      () async {
    final root = p.normalize('/solo');
    final cubit = FileTreeCubit(
      fs: _FakeFilesystem({
        root: [const FsDirEntry(name: 'x.dart', isDirectory: false)],
      }),
    );

    await cubit.setRoots([root]);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(cubit.state.isMultiRoot, isFalse);
    expect(cubit.state.rootPath, root);
    // Single root renders children directly; the root is not in expandedPaths.
    expect(cubit.state.expandedPaths, isEmpty);

    await cubit.close();
  });

  test('mountRoots uses each root filesystem for stat and listing', () async {
    final local = p.normalize('/local');
    final remote = p.normalize('/remote');
    final localFs = _FakeFilesystem({
      local: [const FsDirEntry(name: 'local.dart', isDirectory: false)],
    });
    final remoteFs = _FakeFilesystem({
      remote: [const FsDirEntry(name: 'remote.dart', isDirectory: false)],
    });
    final cubit = FileTreeCubit();

    await cubit.mountRoots([
      FileTreeRootMount(path: local, filesystem: localFs),
      FileTreeRootMount(path: remote, filesystem: remoteFs),
    ]);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(cubit.state.roots.every((r) => r.exists), isTrue);
    expect(cubit.entriesFor(local).map((e) => e.name), ['local.dart']);
    expect(cubit.entriesFor(remote).map((e) => e.name), ['remote.dart']);

    await cubit.close();
  });
}
