import 'dart:async';

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

Future<ConflictChoice> _overwriteConflict({
  required String destPath,
  required bool sourceIsDirectory,
  required bool destIsDirectory,
  required bool typeMismatch,
  required int remainingConflicts,
}) async =>
    ConflictChoice.overwrite;

Future<ImportPlan> _buildPlan(
  WorkspaceImportService service,
  Filesystem fs, {
  required List<ImportSource> sources,
  required String destDir,
  required ImportMode mode,
}) async {
  final planned = await service.planSources(fs, sources);
  return ImportPlan(
    sources: sources,
    destDir: destDir,
    mode: mode,
    sourceFs: fs,
    destFs: fs,
    flattenedFileCount: planned.files.length,
    maxFileBytes: planned.maxBytes,
    destIsLocal: true,
  );
}

/// Delegates to [delegate] but throws on [rename] when [failRename] is true.
class RenameFailingFilesystem implements Filesystem {
  RenameFailingFilesystem(this.delegate, {this.failRename = true});

  final InMemoryFilesystem delegate;
  bool failRename;
  int renameCalls = 0;

  @override
  p.Context get pathContext => delegate.pathContext;

  @override
  Future<void> rename(String from, String to) async {
    renameCalls++;
    if (failRename) {
      throw Exception('simulated rename failure');
    }
    return delegate.rename(from, to);
  }

  @override
  Future<FsStat> stat(String path) => delegate.stat(path);

  @override
  Future<void> ensureDir(String path) => delegate.ensureDir(path);

  @override
  Future<void> removeRecursive(String path) => delegate.removeRecursive(path);

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
  Future<void> appendBytes(String path, List<int> bytes) =>
      delegate.appendBytes(path, bytes);

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

/// Delegates to [delegate] but throws on [copyFile].
class CopyFailingFilesystem implements Filesystem {
  CopyFailingFilesystem(this.delegate);

  final InMemoryFilesystem delegate;

  @override
  p.Context get pathContext => delegate.pathContext;

  @override
  Future<void> copyFile(String source, String destination) async {
    throw Exception('simulated copy failure');
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
  Future<void> appendBytes(String path, List<int> bytes) =>
      delegate.appendBytes(path, bytes);

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
  late InMemoryFilesystem fs;
  late WorkspaceImportService service;

  setUp(() {
    fs = InMemoryFilesystem();
    service = WorkspaceImportService();
  });

  tearDown(() {
    service.dispose();
  });

  group('planSources', () {
    test('flattens nested directories and tracks max file size', () async {
      await fs.ensureDir('/src/tree/sub');
      await fs.writeString('/src/tree/a.txt', 'aa');
      await fs.writeString('/src/tree/sub/b.txt', 'bbbb');

      final result = await service.planSources(fs, [
        const ImportSource(path: '/src/tree', isDirectory: true),
      ]);

      expect(result.files, containsAll(['/src/tree/a.txt', '/src/tree/sub/b.txt']));
      expect(result.maxBytes, 4);
      expect(result.topLevel.length, 1);
    });
  });

  group('run same-FS', () {
    test('copies a file into dest directory', () async {
      await fs.writeString('/src/note.txt', 'hello');
      await fs.ensureDir('/dest');

      final plan = await _buildPlan(
        service,
        fs,
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
      expect(await fs.readString('/dest/note.txt'), 'hello');
      expect(await fs.readString('/src/note.txt'), 'hello');
    });

    test('copies a directory tree', () async {
      await fs.ensureDir('/src/tree/sub');
      await fs.writeString('/src/tree/a.txt', 'a');
      await fs.writeString('/src/tree/sub/b.txt', 'b');

      final plan = await _buildPlan(
        service,
        fs,
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
      expect(await fs.readString('/dest/tree/a.txt'), 'a');
      expect(await fs.readString('/dest/tree/sub/b.txt'), 'b');
    });

    test('progress stream updates during multi-item copy', () async {
      await fs.writeString('/src/a.txt', 'a');
      await fs.writeString('/src/b.txt', 'b');
      await fs.ensureDir('/dest');

      final plan = await _buildPlan(
        service,
        fs,
        sources: [
          const ImportSource(path: '/src/a.txt', isDirectory: false),
          const ImportSource(path: '/src/b.txt', isDirectory: false),
        ],
        destDir: '/dest',
        mode: ImportMode.copy,
      );

      final progressEvents = <ImportProgress>[];
      final allItemsDone = Completer<void>();
      final subscription = service.progress.listen((event) {
        progressEvents.add(event);
        if (event.completedItems == event.totalItems && event.totalItems > 0) {
          if (!allItemsDone.isCompleted) {
            allItemsDone.complete();
          }
        }
      });

      final summary = await service.run(
        plan,
        onConflict: _skipConflict,
        isCancelled: () => false,
      );
      await allItemsDone.future;

      await subscription.cancel();

      expect(summary.succeeded, 2);
      expect(progressEvents, isNotEmpty);
      expect(progressEvents.first.completedItems, 0);
      expect(progressEvents.first.totalItems, 2);
      expect(progressEvents.last.completedItems, 2);
      expect(progressEvents.last.totalItems, 2);
    });

    test('move falls back to copy and remove when rename fails', () async {
      await fs.writeString('/src/fallback.txt', 'payload');
      await fs.ensureDir('/dest');
      final failingFs = RenameFailingFilesystem(fs);

      final plan = await _buildPlan(
        service,
        failingFs,
        sources: [
          const ImportSource(path: '/src/fallback.txt', isDirectory: false),
        ],
        destDir: '/dest',
        mode: ImportMode.move,
      );

      final summary = await service.run(
        plan,
        onConflict: _skipConflict,
        isCancelled: () => false,
      );

      expect(failingFs.renameCalls, 1);
      expect(summary.succeeded, 1);
      expect(await failingFs.readString('/dest/fallback.txt'), 'payload');
      expect(
        await failingFs.stat('/src/fallback.txt').then((s) => s.exists),
        isFalse,
      );
    });

    test('moves a file via rename', () async {
      await fs.writeString('/src/move.txt', 'payload');
      await fs.ensureDir('/dest');

      final plan = await _buildPlan(
        service,
        fs,
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
      expect(await fs.readString('/dest/move.txt'), 'payload');
      expect(await fs.stat('/src/move.txt').then((s) => s.exists), isFalse);
    });

    test('overwrites an existing file after conflict choice', () async {
      await fs.writeString('/src/note.txt', 'new');
      await fs.writeString('/dest/note.txt', 'old');

      final plan = await _buildPlan(
        service,
        fs,
        sources: [const ImportSource(path: '/src/note.txt', isDirectory: false)],
        destDir: '/dest',
        mode: ImportMode.copy,
      );

      final summary = await service.run(
        plan,
        onConflict: _overwriteConflict,
        isCancelled: () => false,
      );

      expect(summary.succeeded, 1);
      expect(await fs.readString('/dest/note.txt'), 'new');
    });

    test('skips when conflict resolver returns skip', () async {
      await fs.writeString('/src/a.txt', 'src-a');
      await fs.writeString('/src/b.txt', 'src-b');
      await fs.writeString('/dest/a.txt', 'dest-a');
      await fs.ensureDir('/dest');

      final plan = await _buildPlan(
        service,
        fs,
        sources: [
          const ImportSource(path: '/src/a.txt', isDirectory: false),
          const ImportSource(path: '/src/b.txt', isDirectory: false),
        ],
        destDir: '/dest',
        mode: ImportMode.copy,
      );

      final summary = await service.run(
        plan,
        onConflict: _skipConflict,
        isCancelled: () => false,
      );

      expect(summary.succeeded, 1);
      expect(summary.skipped, 1);
      expect(await fs.readString('/dest/a.txt'), 'dest-a');
      expect(await fs.readString('/dest/b.txt'), 'src-b');
    });

    test('cancel mid-batch keeps prior writes', () async {
      await fs.writeString('/src/first.txt', 'one');
      await fs.writeString('/src/second.txt', 'two');
      await fs.ensureDir('/dest');

      final plan = await _buildPlan(
        service,
        fs,
        sources: [
          const ImportSource(path: '/src/first.txt', isDirectory: false),
          const ImportSource(path: '/src/second.txt', isDirectory: false),
        ],
        destDir: '/dest',
        mode: ImportMode.copy,
      );

      var processed = 0;
      final summary = await service.run(
        plan,
        onConflict: _skipConflict,
        isCancelled: () {
          processed++;
          return processed > 1;
        },
      );

      expect(summary.cancelled, isTrue);
      expect(summary.succeeded, 1);
      expect(await fs.readString('/dest/first.txt'), 'one');
      expect(await fs.stat('/dest/second.txt').then((s) => s.exists), isFalse);
    });

    test('type mismatch skip does not delete destination', () async {
      await fs.ensureDir('/src/folder');
      await fs.writeString('/src/folder/inner.txt', 'inside');
      await fs.writeString('/dest/folder', 'existing-file');

      final plan = await _buildPlan(
        service,
        fs,
        sources: [const ImportSource(path: '/src/folder', isDirectory: true)],
        destDir: '/dest',
        mode: ImportMode.copy,
      );

      final summary = await service.run(
        plan,
        onConflict: ({
          required typeMismatch,
          required destIsDirectory,
          required sourceIsDirectory,
          required destPath,
          required remainingConflicts,
        }) async {
          expect(typeMismatch, isTrue);
          expect(sourceIsDirectory, isTrue);
          expect(destIsDirectory, isFalse);
          return ConflictChoice.skip;
        },
        isCancelled: () => false,
      );

      expect(summary.skipped, 1);
      expect(await fs.readString('/dest/folder'), 'existing-file');
    });

    test('type mismatch overwrite choice is coerced to skip', () async {
      await fs.writeString('/src/item', 'src');
      await fs.ensureDir('/dest/item');

      final plan = await _buildPlan(
        service,
        fs,
        sources: [const ImportSource(path: '/src/item', isDirectory: false)],
        destDir: '/dest',
        mode: ImportMode.copy,
      );

      final summary = await service.run(
        plan,
        onConflict: _overwriteConflict,
        isCancelled: () => false,
      );

      expect(summary.skipped, 1);
      expect((await fs.stat('/dest/item')).isDirectory, isTrue);
    });

    test('records failedPaths when copy throws', () async {
      await fs.writeString('/src/broken.txt', 'data');
      await fs.ensureDir('/dest');
      final failingFs = CopyFailingFilesystem(fs);

      final plan = await _buildPlan(
        service,
        failingFs,
        sources: [
          const ImportSource(path: '/src/broken.txt', isDirectory: false),
        ],
        destDir: '/dest',
        mode: ImportMode.copy,
      );

      final summary = await service.run(
        plan,
        onConflict: _skipConflict,
        isCancelled: () => false,
      );

      expect(summary.failed, 1);
      expect(summary.failedPaths, ['/dest/broken.txt']);
    });

  });
}
