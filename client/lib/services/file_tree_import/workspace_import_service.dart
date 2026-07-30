import 'dart:async';

import 'package:teampilot/services/file_tree_import/import_models.dart';
import 'package:teampilot/services/io/filesystem.dart';

typedef ConflictResolver = Future<ConflictChoice> Function({
  required String destPath,
  required bool sourceIsDirectory,
  required bool destIsDirectory,
  required bool typeMismatch,
  required int remainingConflicts,
});

class WorkspaceImportService {
  WorkspaceImportService({this.chunkSize = 256 * 1024});

  final int chunkSize;

  final StreamController<ImportProgress> _progressController =
      StreamController<ImportProgress>.broadcast();

  Stream<ImportProgress> get progress => _progressController.stream;

  void dispose() {
    if (!_progressController.isClosed) {
      _progressController.close();
    }
  }

  /// Walk sources on [sourceFs], return flattened file paths + max size.
  Future<({List<String> files, int maxBytes, List<ImportSource> topLevel})>
  planSources(Filesystem sourceFs, List<ImportSource> sources) async {
    final pathContext = sourceFs.pathContext;
    final files = <String>[];
    var maxBytes = 0;

    for (final source in sources) {
      if (!source.isDirectory) {
        final stat = await sourceFs.stat(source.path);
        if (stat.isFile) {
          files.add(source.path);
          final size = stat.size ?? 0;
          if (size > maxBytes) maxBytes = size;
        }
        continue;
      }

      final entries = await sourceFs.listDirRecursive(source.path);
      for (final entry in entries) {
        if (entry.isDirectory) continue;
        final filePath = pathContext.join(source.path, entry.name);
        final stat = await sourceFs.stat(filePath);
        if (!stat.isFile) continue;
        files.add(filePath);
        final size = stat.size ?? 0;
        if (size > maxBytes) maxBytes = size;
      }
    }

    return (files: files, maxBytes: maxBytes, topLevel: sources);
  }

  Future<ImportSummary> run(
    ImportPlan plan, {
    required ConflictResolver onConflict,
    required bool Function() isCancelled,
  }) async {
    if (!identical(plan.sourceFs, plan.destFs)) {
      throw UnimplementedError('cross-FS import');
    }

    final fs = plan.sourceFs;
    final pathContext = fs.pathContext;
    var succeeded = 0;
    var skipped = 0;
    var failed = 0;
    var cancelled = false;
    final failedPaths = <String>[];

    final totalItems = plan.sources.length;
    var completedItems = 0;
    var remainingConflicts = await _countConflicts(plan);

    void emitProgress({
      String currentName = '',
      int bytesDone = 0,
      int bytesTotal = 0,
    }) {
      if (_progressController.isClosed) return;
      _progressController.add(
        ImportProgress(
          completedItems: completedItems,
          totalItems: totalItems,
          bytesDone: bytesDone,
          bytesTotal: bytesTotal,
          currentName: currentName,
        ),
      );
    }

    emitProgress();

    for (final source in plan.sources) {
      if (isCancelled()) {
        cancelled = true;
        break;
      }

      final destPath = pathContext.join(
        plan.destDir,
        pathContext.basename(source.path),
      );
      final destStat = await fs.stat(destPath);

      if (destStat.exists) {
        final destIsDirectory = destStat.isDirectory;
        final typeMismatch = source.isDirectory != destIsDirectory;

        final choice = await onConflict(
          destPath: destPath,
          sourceIsDirectory: source.isDirectory,
          destIsDirectory: destIsDirectory,
          typeMismatch: typeMismatch,
          remainingConflicts: remainingConflicts,
        );
        remainingConflicts--;

        final effectiveChoice =
            typeMismatch && choice == ConflictChoice.overwrite
            ? ConflictChoice.skip
            : choice;

        if (effectiveChoice == ConflictChoice.cancelAll) {
          cancelled = true;
          break;
        }
        if (effectiveChoice == ConflictChoice.skip) {
          skipped++;
          completedItems++;
          emitProgress(currentName: pathContext.basename(source.path));
          continue;
        }

        await fs.removeRecursive(destPath);
      }

      try {
        if (plan.mode == ImportMode.move) {
          await _moveSameFs(
            fs,
            sourcePath: source.path,
            destPath: destPath,
            isDirectory: source.isDirectory,
          );
        } else {
          await _copySameFs(
            fs,
            sourcePath: source.path,
            destPath: destPath,
            isDirectory: source.isDirectory,
          );
        }
        succeeded++;
      } on Error {
        rethrow;
      } catch (_) {
        failedPaths.add(destPath);
        failed++;
      }

      completedItems++;
      emitProgress(currentName: pathContext.basename(source.path));
    }

    return ImportSummary(
      succeeded: succeeded,
      skipped: skipped,
      failed: failed,
      cancelled: cancelled,
      failedPaths: List.unmodifiable(failedPaths),
    );
  }

  Future<int> _countConflicts(ImportPlan plan) async {
    final pathContext = plan.destFs.pathContext;
    var count = 0;
    for (final source in plan.sources) {
      final destPath = pathContext.join(
        plan.destDir,
        pathContext.basename(source.path),
      );
      final destStat = await plan.destFs.stat(destPath);
      if (destStat.exists) count++;
    }
    return count;
  }

  Future<void> _copySameFs(
    Filesystem fs, {
    required String sourcePath,
    required String destPath,
    required bool isDirectory,
  }) async {
    if (isDirectory) {
      await fs.copyTree(source: sourcePath, destination: destPath);
      return;
    }
    await fs.copyFile(sourcePath, destPath);
  }

  Future<void> _moveSameFs(
    Filesystem fs, {
    required String sourcePath,
    required String destPath,
    required bool isDirectory,
  }) async {
    try {
      await fs.rename(sourcePath, destPath);
    } on Error {
      rethrow;
    } catch (_) {
      await _copySameFs(
        fs,
        sourcePath: sourcePath,
        destPath: destPath,
        isDirectory: isDirectory,
      );
      await fs.removeRecursive(sourcePath);
    }
  }
}
