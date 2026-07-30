import 'package:flutter_test/flutter_test.dart';
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
  });
}
