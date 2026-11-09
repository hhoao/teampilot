import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:shared_ui/shared_ui.dart';
import '../../l10n/l10n_extensions.dart';
import '../../services/file_tree_import/import_models.dart';
import '../../services/file_tree_import/workspace_import_service.dart';
import '../app_toast/app_toast.dart';

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
          TpDialogHeader(title: l10n.fileTree.importConflictTitle),
          const SizedBox(height: 16),
          Text(l10n.fileTree.importConflictBody(name: basename)),
          const SizedBox(height: 8),
          Text(
            widget.remainingConflicts == 0
                ? l10n.fileTree.importConflictRemainingZero
                : l10n.fileTree.importConflictRemaining(
                    count: widget.remainingConflicts,
                  ),
          ),
          if (widget.typeMismatch) ...[
            const SizedBox(height: 8),
            Text(
              l10n.fileTree.importConflictTypeMismatch,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(l10n.fileTree.importApplyRemaining),
            value: _applyToRemaining,
            onChanged: (value) {
              setState(() => _applyToRemaining = value ?? false);
            },
          ),
          TpDialogActions(
            children: [
              TextButton(
                onPressed: () => _pop(ConflictChoice.cancelAll),
                child: Text(l10n.fileTree.importCancelAll),
              ),
              TextButton(
                onPressed: () => _pop(ConflictChoice.skip),
                child: Text(l10n.fileTree.importSkip),
              ),
              FilledButton(
                onPressed: widget.typeMismatch
                    ? null
                    : () => _pop(ConflictChoice.overwrite),
                child: Text(l10n.fileTree.importOverwrite),
              ),
            ],
          ),
        ],
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
  var message = l10n.fileTree.importSummary(
    succeeded: summary.succeeded,
    skipped: summary.skipped,
    failed: summary.failed,
  );
  if (summary.cancelled) {
    message = '$message${l10n.fileTree.importSummaryCancelledSuffix}';
  }
  AppToast.show(
    context,
    message: message,
    variant: summary.failed > 0 ? TpToastVariant.warning : TpToastVariant.info,
  );
}

/// Toast for invalid self/descendant drop targets.
void showFileTreeImportRejectSelfToast(BuildContext context) {
  AppToast.show(
    context,
    message: context.l10n.fileTree.importRejectSelf,
    variant: TpToastVariant.warning,
  );
}
