import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/cubits/file_tree_cubit.dart';
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
}
