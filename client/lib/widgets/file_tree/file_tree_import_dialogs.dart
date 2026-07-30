import 'dart:async';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/l10n/l10n_extensions.dart';
import 'package:teampilot/services/file_tree_import/import_models.dart';
import 'package:teampilot/services/file_tree_import/workspace_import_service.dart';
import 'package:teampilot/widgets/app_toast/app_toast.dart';

class FileTreeImportConflictDialogResult {
  const FileTreeImportConflictDialogResult({
    required this.choice,
    this.applyToRemaining = false,
  });

  final ConflictChoice choice;
  final bool applyToRemaining;
}

/// Remembers apply-to-remaining without changing [ConflictResolver]'s typedef.
class FileTreeImportConflictSession {
  ConflictChoice? _cachedChoice;
  bool _applyToRemaining = false;

  ConflictResolver resolver(BuildContext context) {
    return ({
      required String destPath,
      required bool sourceIsDirectory,
      required bool destIsDirectory,
      required bool typeMismatch,
      required int remainingConflicts,
    }) async {
      if (_applyToRemaining && _cachedChoice != null) {
        return _cachedChoice!;
      }

      if (!context.mounted) {
        return ConflictChoice.cancelAll;
      }

      final result = await showFileTreeImportConflictDialog(
        context,
        destPath: destPath,
        typeMismatch: typeMismatch,
        remainingConflicts: remainingConflicts,
      );

      if (result.applyToRemaining) {
        _applyToRemaining = true;
        _cachedChoice = result.choice;
      }

      return result.choice;
    };
  }
}

Future<FileTreeImportConflictDialogResult> showFileTreeImportConflictDialog(
  BuildContext context, {
  required String destPath,
  required bool typeMismatch,
  required int remainingConflicts,
}) {
  return showDialog<FileTreeImportConflictDialogResult>(
    context: context,
    builder: (dialogContext) => _FileTreeImportConflictDialog(
      destPath: destPath,
      typeMismatch: typeMismatch,
      remainingConflicts: remainingConflicts,
    ),
  ).then(
    (result) =>
        result ??
        const FileTreeImportConflictDialogResult(
          choice: ConflictChoice.cancelAll,
        ),
  );
}

class _FileTreeImportConflictDialog extends StatefulWidget {
  const _FileTreeImportConflictDialog({
    required this.destPath,
    required this.typeMismatch,
    required this.remainingConflicts,
  });

  final String destPath;
  final bool typeMismatch;
  final int remainingConflicts;

  @override
  State<_FileTreeImportConflictDialog> createState() =>
      _FileTreeImportConflictDialogState();
}

class _FileTreeImportConflictDialogState
    extends State<_FileTreeImportConflictDialog> {
  var _applyToRemaining = false;

  void _pop(ConflictChoice choice) {
    Navigator.of(context).pop(
      FileTreeImportConflictDialogResult(
        choice: choice,
        applyToRemaining: _applyToRemaining,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final basename = p.basename(widget.destPath);

    return TpDialog(
      maxWidth: 480,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TpDialogHeader(title: l10n.fileTreeImportConflictTitle),
          const SizedBox(height: 16),
          Text(l10n.fileTreeImportConflictBody(basename)),
          const SizedBox(height: 8),
          Text(l10n.fileTreeImportConflictRemaining(widget.remainingConflicts)),
          if (widget.typeMismatch) ...[
            const SizedBox(height: 8),
            Text(
              l10n.fileTreeImportConflictTypeMismatch,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(l10n.fileTreeImportApplyRemaining),
            value: _applyToRemaining,
            onChanged: (value) {
              setState(() => _applyToRemaining = value ?? false);
            },
          ),
          TpDialogActions(
            children: [
              TextButton(
                onPressed: () => _pop(ConflictChoice.cancelAll),
                child: Text(l10n.fileTreeImportCancelAll),
              ),
              TextButton(
                onPressed: () => _pop(ConflictChoice.skip),
                child: Text(l10n.fileTreeImportSkip),
              ),
              FilledButton(
                onPressed: widget.typeMismatch
                    ? null
                    : () => _pop(ConflictChoice.overwrite),
                child: Text(l10n.fileTreeImportOverwrite),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Shows import progress until [task] completes. [cancelRequested] is set when
/// the user taps Cancel.
Future<T> showFileTreeImportProgressDialog<T>({
  required BuildContext context,
  required Stream<ImportProgress> progress,
  required ValueNotifier<bool> cancelRequested,
  required Future<T> task,
}) async {
  final taskCompletion = Completer<T>();
  unawaited(
    task
        .then(taskCompletion.complete)
        .catchError((Object error, StackTrace stackTrace) {
          if (!taskCompletion.isCompleted) {
            taskCompletion.completeError(error, stackTrace);
          }
        }),
  );

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => _FileTreeImportProgressDialog<T>(
      progress: progress,
      cancelRequested: cancelRequested,
      task: taskCompletion.future,
    ),
  );
  return await taskCompletion.future;
}

class _FileTreeImportProgressDialog<T> extends StatefulWidget {
  const _FileTreeImportProgressDialog({
    required this.progress,
    required this.cancelRequested,
    required this.task,
  });

  final Stream<ImportProgress> progress;
  final ValueNotifier<bool> cancelRequested;
  final Future<T> task;

  @override
  State<_FileTreeImportProgressDialog<T>> createState() =>
      _FileTreeImportProgressDialogState<T>();
}

class _FileTreeImportProgressDialogState<T>
    extends State<_FileTreeImportProgressDialog<T>> {
  ImportProgress? _latest;
  var _running = true;
  StreamSubscription<ImportProgress>? _subscription;
  late final Future<T> _taskFuture;

  @override
  void initState() {
    super.initState();
    _taskFuture = widget.task;
    _subscription = widget.progress.listen((event) {
      if (!mounted) return;
      setState(() => _latest = event);
    });
    unawaited(
      _taskFuture.then((_) {
        if (!mounted) return;
        setState(() => _running = false);
        Navigator.of(context).pop();
      }).catchError((Object _, StackTrace __) {
        if (!mounted) return;
        setState(() => _running = false);
        Navigator.of(context).pop();
      }),
    );
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  double? _progressValue(ImportProgress? progress) {
    if (progress == null) return null;
    if (progress.bytesTotal > 0) {
      return progress.bytesDone / progress.bytesTotal;
    }
    if (progress.totalItems > 0) {
      return progress.completedItems / progress.totalItems;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final progress = _latest;
    final progressValue = _progressValue(progress);

    return PopScope(
      canPop: !_running,
      child: TpDialog(
        maxWidth: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TpDialogHeader(title: l10n.fileTreeImportProgressTitle),
            const SizedBox(height: 16),
            if (progress != null && progress.currentName.isNotEmpty)
              Text(l10n.fileTreeImportProgressCurrent(progress.currentName)),
            if (progress != null && progress.totalItems > 0) ...[
              const SizedBox(height: 8),
              Text(
                l10n.fileTreeImportProgressItems(
                  progress.completedItems,
                  progress.totalItems,
                ),
              ),
            ],
            const SizedBox(height: 12),
            LinearProgressIndicator(value: progressValue ?? 0),
            TpDialogActions(
              children: [
                TextButton(
                  onPressed: _running
                      ? () => widget.cancelRequested.value = true
                      : null,
                  child: Text(l10n.fileTreeImportProgressCancel),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Toast when import ends with skips, failures, or cancellation.
void showFileTreeImportSummaryIfNeeded(
  BuildContext context,
  ImportSummary summary,
) {
  if (summary.failed <= 0 && summary.skipped <= 0 && !summary.cancelled) {
    return;
  }

  final l10n = context.l10n;
  var message = l10n.fileTreeImportSummary(
    summary.succeeded,
    summary.skipped,
    summary.failed,
  );
  if (summary.cancelled) {
    message = '$message${l10n.fileTreeImportSummaryCancelledSuffix}';
  }
  AppToast.show(
    context,
    message: message,
    variant: summary.failed > 0
        ? TpToastVariant.warning
        : TpToastVariant.info,
  );
}

/// Toast for invalid self/descendant drop targets.
void showFileTreeImportRejectSelfToast(BuildContext context) {
  AppToast.show(
    context,
    message: context.l10n.fileTreeImportRejectSelf,
    variant: TpToastVariant.warning,
  );
}
