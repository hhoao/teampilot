import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/cubits/file_tree_cubit.dart';
import 'package:teampilot/services/file_tree/file_tree_visible_rows.dart';
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
  test('visibleRowIndexForPath finds nested file index', () {
    final root = p.normalize('/proj');
    final cubit = FileTreeCubit(
      fs: _FakeFilesystem({
        root: [
          const FsDirEntry(name: 'src', isDirectory: true),
          const FsDirEntry(name: 'readme.md', isDirectory: false),
        ],
        p.join(root, 'src'): [
          const FsDirEntry(name: 'main.dart', isDirectory: false),
        ],
      }),
    );

    final state = FileTreeState.single(
      rootPath: root,
      rootExists: true,
      expandedPaths: {p.join(root, 'src')},
      dirCache: {
        root: [
          const FsDirEntry(name: 'src', isDirectory: true),
          const FsDirEntry(name: 'readme.md', isDirectory: false),
        ],
        p.join(root, 'src'): [
          const FsDirEntry(name: 'main.dart', isDirectory: false),
        ],
      },
    );

    final rows = visibleFileTreeRows(
      state: state,
      pathContext: cubit.fs.pathContext,
    );
    final target = p.join(root, 'src', 'main.dart');
    final index = visibleRowIndexForPath(rows, target, cubit.fs.pathContext);
    expect(index, 1);
  });

  test('multi-root tree emits a header row per folder, contents nested', () {
    final a = p.normalize('/projA');
    final b = p.normalize('/projB');
    final ctx = p.Context();

    final state = FileTreeState(
      roots: [
        FileTreeRoot(path: a, exists: true),
        FileTreeRoot(path: b, exists: true),
      ],
      expandedPaths: {a, b},
      dirCache: {
        a: [const FsDirEntry(name: 'a.dart', isDirectory: false)],
        b: [const FsDirEntry(name: 'b.dart', isDirectory: false)],
      },
    );

    final rows = visibleFileTreeRows(state: state, pathContext: ctx);

    // Header A (depth 0), a.dart (depth 1), Header B (depth 0), b.dart (depth 1).
    expect(rows.length, 4);
    expect(rows[0].isRoot, isTrue);
    expect(rows[0].path, a);
    expect(rows[0].depth, 0);
    expect(rows[1].isRoot, isFalse);
    expect(rows[1].entry.name, 'a.dart');
    expect(rows[1].depth, 1);
    expect(rows[2].isRoot, isTrue);
    expect(rows[2].path, b);
    expect(rows[3].entry.name, 'b.dart');
  });

  test('collapsed multi-root folder hides its contents', () {
    final a = p.normalize('/projA');
    final b = p.normalize('/projB');
    final ctx = p.Context();

    final state = FileTreeState(
      roots: [
        FileTreeRoot(path: a, exists: true),
        FileTreeRoot(path: b, exists: true),
      ],
      // Only A is expanded.
      expandedPaths: {a},
      dirCache: {
        a: [const FsDirEntry(name: 'a.dart', isDirectory: false)],
        b: [const FsDirEntry(name: 'b.dart', isDirectory: false)],
      },
    );

    final rows = visibleFileTreeRows(state: state, pathContext: ctx);

    // Header A, a.dart, Header B (collapsed → no child rows).
    expect(rows.length, 3);
    expect(rows[2].path, b);
    expect(rows.where((r) => r.entry.name == 'b.dart'), isEmpty);
  });

  test('fileTreeMinContentWidth accounts for depth and label length', () {
    const style = TextStyle(fontSize: 14, fontWeight: FontWeight.w500);
    const emptyStyle = TextStyle(fontSize: 12);
    final rows = [
      const FileTreeVisibleRow(
        path: '/a/short.txt',
        entry: FsDirEntry(name: 'short.txt', isDirectory: false),
        depth: 0,
      ),
      const FileTreeVisibleRow(
        path: '/a/deep/very-long-name.txt',
        entry: FsDirEntry(name: 'very-long-name.txt', isDirectory: false),
        depth: 4,
      ),
    ];

    final width = fileTreeMinContentWidth(
      rows: rows,
      labelStyle: style,
      emptyLabelStyle: emptyStyle,
    );
    expect(width, greaterThan(200));
  });
}
