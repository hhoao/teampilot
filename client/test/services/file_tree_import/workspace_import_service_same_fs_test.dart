import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/file_tree_import/import_models.dart';
import 'package:teampilot/services/file_tree_import/workspace_import_service.dart';
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
  InMemoryFilesystem fs, {
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

void main() {
  late InMemoryFilesystem fs;
  late WorkspaceImportService service;

  setUp(() {
    fs = InMemoryFilesystem();
    service = WorkspaceImportService();
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

    test('cross-FS plan throws UnimplementedError', () async {
      final otherFs = InMemoryFilesystem();
      await otherFs.ensureDir('/dest');

      final plan = ImportPlan(
        sources: [const ImportSource(path: '/src/x.txt', isDirectory: false)],
        destDir: '/dest',
        mode: ImportMode.copy,
        sourceFs: fs,
        destFs: otherFs,
        flattenedFileCount: 1,
        maxFileBytes: 0,
        destIsLocal: true,
      );

      await expectLater(
        service.run(
          plan,
          onConflict: _skipConflict,
          isCancelled: () => false,
        ),
        throwsA(isA<UnimplementedError>()),
      );
    });
  });
}
