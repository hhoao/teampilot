import 'dart:async';

import 'package:meta/meta.dart';

import '../../../models/install_job/install_job_cancelled_exception.dart';
import '../../../models/install_job/install_job_context.dart';
import '../../../models/install_job/install_job_key.dart';
import '../../../models/install_job/install_job_spec.dart';
import '../../file_tree_import/import_models.dart';
import '../../file_tree_import/import_progress_gate.dart';
import '../../file_tree_import/workspace_import_service.dart';
import '../install_job_runner.dart';

typedef FileTreeImportExecutor =
    Future<ImportSummary> Function({
      required bool Function() isCancelled,
    });

final class FileTreeImportInstallJobRunner implements InstallJobRunner {
  FileTreeImportInstallJobRunner({
    required WorkspaceImportService importService,
    @visibleForTesting WorkspaceImportService? importServiceOverride,
  }) : _importService = importServiceOverride ?? importService;

  final WorkspaceImportService _importService;

  @override
  InstallJobKind get kind => InstallJobKind.fileTreeImport;

  @override
  bool supports(InstallJobKey key) => key.kind == kind;

  @override
  Future<T> run<T>(InstallJobSpec<T> spec, InstallJobContext ctx) async {
    if (!supports(spec.key)) {
      throw StateError('Unsupported file tree import key: ${spec.key.target}');
    }
    final result = await spec.run(ctx);
    if (result is ImportSummary) {
      _throwIfSummaryTerminal(spec.key, result);
    }
    return result;
  }

  Future<ImportSummary> execute({
    required ImportPlan plan,
    required InstallJobContext ctx,
    required FileTreeImportExecutor runImport,
    @visibleForTesting Stream<ImportProgress>? progressStreamOverride,
  }) async {
    if (!shouldShowImportProgress(
      flattenedFileCount: plan.flattenedFileCount,
      maxFileBytes: plan.maxFileBytes,
      destIsLocal: plan.destIsLocal,
    )) {
      return runImport(isCancelled: () => ctx.isCancelled);
    }

    StreamSubscription<ImportProgress>? subscription;
    try {
      subscription = (progressStreamOverride ?? _importService.progress).listen(
        (event) => _applyImportProgress(ctx, event),
      );
      final summary = await runImport(isCancelled: () => ctx.isCancelled);
      return summary;
    } finally {
      await subscription?.cancel();
    }
  }

  void _applyImportProgress(InstallJobContext ctx, ImportProgress event) {
    if (event.currentName.isNotEmpty) {
      ctx.reportPhase(event.currentName);
    }
    if (event.totalItems > 0) {
      ctx.reportItems(
        completed: event.completedItems,
        total: event.totalItems,
      );
    }
    if (event.bytesTotal > 0) {
      ctx.reportPhase(
        'Transferring',
        detail: '${event.bytesDone} / ${event.bytesTotal} bytes',
      );
    }
  }

  void _throwIfSummaryTerminal(InstallJobKey key, ImportSummary summary) {
    if (summary.cancelled) {
      throw InstallJobCancelledException(key);
    }
    if (summary.failed > 0) {
      throw StateError(
        'Import failed: ${summary.succeeded} succeeded, '
        '${summary.skipped} skipped, ${summary.failed} failed',
      );
    }
  }
}
