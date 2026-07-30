import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/services/file_tree_import/import_models.dart';
import 'package:teampilot/services/file_tree_import/workspace_import_service.dart';
import 'package:teampilot/services/io/filesystem.dart';
import '../../support/in_memory_filesystem.dart';

Future<ConflictChoice> _skipConflict({
  required String destPath,
  required bool sourceIsDirectory,
  required bool destIsDirectory,
  required bool typeMismatch,
  required int remainingConflicts,
}) async =>
    ConflictChoice.skip;

Future<ImportPlan> _buildCrossFsPlan(
  WorkspaceImportService service,
  Filesystem sourceFs,
  Filesystem destFs, {
  required List<ImportSource> sources,
  required String destDir,
  required ImportMode mode,
}) async {
  final planned = await service.planSources(sourceFs, sources);
  return ImportPlan(
    sources: sources,
    destDir: destDir,
    mode: mode,
    sourceFs: sourceFs,
    destFs: destFs,
    flattenedFileCount: planned.files.length,
    maxFileBytes: planned.maxBytes,
    destIsLocal: true,
  );
}

/// Throws on [appendBytes] when [destPath] matches [failDestPath].
class AppendFailingDestFilesystem implements Filesystem {
  AppendFailingDestFilesystem(this.delegate, {required this.failDestPath});

  final InMemoryFilesystem delegate;
  final String failDestPath;

  @override
  p.Context get pathContext => delegate.pathContext;

  @override
  Future<void> appendBytes(String path, List<int> bytes) async {
    if (path == failDestPath || path == '$failDestPath.partial') {
      throw Exception('simulated append failure');
    }
    return delegate.appendBytes(path, bytes);
  }

  @override
  Future<FsStat> stat(String path) => delegate.stat(path);

  @override
  Future<void> ensureDir(String path) => delegate.ensureDir(path);

  @override
  Future<void> removeRecursive(String path) => delegate.removeRecursive(path);

  @override
  Future<void> rename(String from, String to) => delegate.rename(from, to);

  @override
  Future<String?> readString(String path) => delegate.readString(path);

  @override
  Future<List<int>?> readBytes(String path) => delegate.readBytes(path);

  @override
  Future<void> writeString(String path, String content) =>
      delegate.writeString(path, content);

  @override
  Future<void> writeBytes(String path, List<int> bytes) =>
      delegate.writeBytes(path, bytes);

  @override
  Future<List<int>?> readBytesRange(String path, int offset, int length) =>
      delegate.readBytesRange(path, offset, length);

  @override
  Future<void> atomicWrite(String path, String content) =>
      delegate.atomicWrite(path, content);

  @override
  Future<List<FsDirEntry>> listDir(String path) => delegate.listDir(path);

  @override
  Future<bool> createSymlink({
    required String target,
    required String linkPath,
  }) =>
      delegate.createSymlink(target: target, linkPath: linkPath);

  @override
  Future<String?> readSymlinkTarget(String linkPath) =>
      delegate.readSymlinkTarget(linkPath);

  @override
  Future<String?> resolveSymlink(String path) => delegate.resolveSymlink(path);

  @override
  Future<void> copyTree({
    required String source,
    required String destination,
  }) =>
      delegate.copyTree(source: source, destination: destination);

  @override
  Future<void> copyFile(String source, String destination) =>
      delegate.copyFile(source, destination);

  @override
  Future<List<FsDirEntry>> listDirRecursive(String path) =>
      delegate.listDirRecursive(path);

  @override
  Future<String> createTempDir({String? prefix, String? parent}) =>
      delegate.createTempDir(prefix: prefix, parent: parent);

  @override
  Future<void> appendString(String path, String content) =>
      delegate.appendString(path, content);
}

void main() {
  late InMemoryFilesystem sourceFs;
  late InMemoryFilesystem destFs;
  late WorkspaceImportService service;

  setUp(() {
    sourceFs = InMemoryFilesystem();
    destFs = InMemoryFilesystem();
    service = WorkspaceImportService(chunkSize: 4);
  });

  tearDown(() {
    service.dispose();
  });

  group('run cross-FS', () {
    test('copies a file into dest filesystem', () async {
      await sourceFs.writeString('/src/note.txt', 'hello');
      await destFs.ensureDir('/dest');

      final plan = await _buildCrossFsPlan(
        service,
        sourceFs,
        destFs,
        sources: [const ImportSource(path: '/src/note.txt', isDirectory: false)],
        destDir: '/dest',
        mode: ImportMode.copy,
      );

      final summary = await service.run(
        plan,
        onConflict: _skipConflict,
        isCancelled: () => false,
      );

      expect(summary.succeeded, 1);
      expect(await destFs.readBytes('/dest/note.txt'), 'hello'.codeUnits);
      expect(await sourceFs.readString('/src/note.txt'), 'hello');
    });

    test('copies a nested directory tree', () async {
      await sourceFs.ensureDir('/src/tree/sub');
      await sourceFs.writeString('/src/tree/a.txt', 'a');
      await sourceFs.writeString('/src/tree/sub/b.txt', 'b');
      await destFs.ensureDir('/dest');

      final plan = await _buildCrossFsPlan(
        service,
        sourceFs,
        destFs,
        sources: [const ImportSource(path: '/src/tree', isDirectory: true)],
        destDir: '/dest',
        mode: ImportMode.copy,
      );

      final summary = await service.run(
        plan,
        onConflict: _skipConflict,
        isCancelled: () => false,
      );

      expect(summary.succeeded, 1);
      expect(await destFs.readBytes('/dest/tree/a.txt'), 'a'.codeUnits);
      expect(await destFs.readBytes('/dest/tree/sub/b.txt'), 'b'.codeUnits);
    });

    test('cancel mid-file deletes partial and leaves source intact', () async {
      await sourceFs.writeBytes('/src/large.bin', List<int>.generate(12, (i) => i));
      await destFs.ensureDir('/dest');

      final plan = await _buildCrossFsPlan(
        service,
        sourceFs,
        destFs,
        sources: [const ImportSource(path: '/src/large.bin', isDirectory: false)],
        destDir: '/dest',
        mode: ImportMode.copy,
      );

      var chunkTransfers = 0;
      final summary = await service.run(
        plan,
        onConflict: _skipConflict,
        isCancelled: () {
          chunkTransfers++;
          return chunkTransfers > 1;
        },
      );

      expect(summary.cancelled, isTrue);
      expect(summary.succeeded, 0);
      expect(await destFs.stat('/dest/large.bin').then((s) => s.exists), isFalse);
      expect(await destFs.stat('/dest/large.bin.partial').then((s) => s.exists), isFalse);
      expect(await sourceFs.readBytes('/src/large.bin'), List<int>.generate(12, (i) => i));
    });

    test('move mode on cross-FS copies without deleting source', () async {
      await sourceFs.writeString('/src/move.txt', 'payload');
      await destFs.ensureDir('/dest');

      final plan = await _buildCrossFsPlan(
        service,
        sourceFs,
        destFs,
        sources: [const ImportSource(path: '/src/move.txt', isDirectory: false)],
        destDir: '/dest',
        mode: ImportMode.move,
      );

      final summary = await service.run(
        plan,
        onConflict: _skipConflict,
        isCancelled: () => false,
      );

      expect(summary.succeeded, 1);
      expect(await destFs.readBytes('/dest/move.txt'), 'payload'.codeUnits);
      expect(await sourceFs.readString('/src/move.txt'), 'payload');
    });

    test('stale partial before copy does not corrupt final file', () async {
      await sourceFs.writeString('/src/note.txt', 'fresh');
      await destFs.ensureDir('/dest');
      await destFs.writeBytes('/dest/note.txt.partial', 'stale-garbage'.codeUnits);

      final plan = await _buildCrossFsPlan(
        service,
        sourceFs,
        destFs,
        sources: [const ImportSource(path: '/src/note.txt', isDirectory: false)],
        destDir: '/dest',
        mode: ImportMode.copy,
      );

      final summary = await service.run(
        plan,
        onConflict: _skipConflict,
        isCancelled: () => false,
      );

      expect(summary.succeeded, 1);
      expect(await destFs.readBytes('/dest/note.txt'), 'fresh'.codeUnits);
      expect(await destFs.stat('/dest/note.txt.partial').then((s) => s.exists), isFalse);
    });

    test('directory with one failing child counts as failed not succeeded', () async {
      await sourceFs.ensureDir('/src/tree');
      await sourceFs.writeString('/src/tree/ok.txt', 'ok');
      await sourceFs.writeString('/src/tree/broken.txt', 'bad');
      await destFs.ensureDir('/dest');

      final failingDestFs = AppendFailingDestFilesystem(
        destFs,
        failDestPath: '/dest/tree/broken.txt',
      );

      final plan = await _buildCrossFsPlan(
        service,
        sourceFs,
        failingDestFs,
        sources: [const ImportSource(path: '/src/tree', isDirectory: true)],
        destDir: '/dest',
        mode: ImportMode.copy,
      );

      final summary = await service.run(
        plan,
        onConflict: _skipConflict,
        isCancelled: () => false,
      );

      expect(summary.failed, 1);
      expect(summary.succeeded, 0);
      expect(summary.failedPaths, contains('/dest/tree/broken.txt'));
      expect(summary.failedPaths, contains('/dest/tree'));
      expect(await failingDestFs.readBytes('/dest/tree/ok.txt'), 'ok'.codeUnits);
      expect(await failingDestFs.stat('/dest/tree/broken.txt').then((s) => s.exists), isFalse);
    });
  });
}
