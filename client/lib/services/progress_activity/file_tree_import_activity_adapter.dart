import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../cubits/progress_activity_cubit.dart';
import '../../models/progress_activity.dart';
import '../file_tree_import/import_models.dart';
import '../file_tree_import/import_progress_gate.dart';
import '../file_tree_import/workspace_import_service.dart';

typedef FileTreeImportHistoryMessageBuilder = String Function(
  ImportSummary summary,
);

/// Maps [WorkspaceImportService] import progress to [ProgressActivityCubit].
class FileTreeImportActivityAdapter {
  FileTreeImportActivityAdapter({
    required ProgressActivityCubit cubit,
    required WorkspaceImportService importService,
  }) : _cubit = cubit,
       _importService = importService;

  final ProgressActivityCubit _cubit;
  final WorkspaceImportService _importService;

  Future<ImportSummary> runTracked({
    required ImportPlan plan,
    required String title,
    required FileTreeImportHistoryMessageBuilder historyMessageFor,
    required Future<ImportSummary> Function({
      required bool Function() isCancelled,
    })
    runImport,
    String? workspaceId,
    void Function(String activityId)? onActivityStarted,
    @visibleForTesting Stream<ImportProgress>? progressStreamOverride,
  }) async {
    if (!shouldShowImportProgress(
      flattenedFileCount: plan.flattenedFileCount,
      maxFileBytes: plan.maxFileBytes,
      destIsLocal: plan.destIsLocal,
    )) {
      return runImport(isCancelled: () => false);
    }

    final activityId = _newActivityId();
    final cancelRequested = ValueNotifier<bool>(false);
    StreamSubscription<ImportProgress>? subscription;

    try {
      final now = DateTime.now();
      _cubit.start(
        ProgressActivity(
          id: activityId,
          kind: ProgressActivityKind.fileTreeImport,
          title: title,
          workspaceId: workspaceId,
          phase: ProgressActivityPhase.running,
          cancellable: true,
          createdAt: now,
          updatedAt: now,
        ),
        onCancelRequested: () {
          cancelRequested.value = true;
        },
      );

      subscription = (progressStreamOverride ?? _importService.progress).listen(
        (event) => _applyImportProgress(activityId, event),
      );

      onActivityStarted?.call(activityId);

      final summary = await runImport(
        isCancelled: () => cancelRequested.value,
      );

      _completeFromSummary(
        activityId,
        summary,
        title: title,
        historyMessage: historyMessageFor(summary),
      );
      return summary;
    } catch (error, stackTrace) {
      _cubit.complete(
        activityId,
        outcome: ProgressActivityPhase.failed,
        historyTitle: title,
        errorMessage: error.toString(),
      );
      Error.throwWithStackTrace(error, stackTrace);
    } finally {
      await subscription?.cancel();
      cancelRequested.dispose();
    }
  }

  void _applyImportProgress(String activityId, ImportProgress event) {
    _cubit.update(
      activityId,
      subtitle: event.currentName.isNotEmpty ? event.currentName : null,
      clearSubtitle: event.currentName.isEmpty,
      completedItems: event.completedItems,
      totalItems: event.totalItems > 0 ? event.totalItems : null,
      clearTotalItems: event.totalItems <= 0,
      bytesDone: event.bytesTotal > 0 ? event.bytesDone : null,
      clearBytesDone: event.bytesTotal <= 0,
      bytesTotal: event.bytesTotal > 0 ? event.bytesTotal : null,
      clearBytesTotal: event.bytesTotal <= 0,
    );
  }

  void _completeFromSummary(
    String activityId,
    ImportSummary summary, {
    required String title,
    required String historyMessage,
  }) {
    final outcome = summary.cancelled
        ? ProgressActivityPhase.cancelled
        : summary.failed > 0
        ? ProgressActivityPhase.failed
        : ProgressActivityPhase.succeeded;

    _cubit.complete(
      activityId,
      outcome: outcome,
      historyTitle: title,
      historyMessage: historyMessage,
    );
  }

  String _newActivityId() =>
      'file-tree-import-${DateTime.now().microsecondsSinceEpoch}';
}
