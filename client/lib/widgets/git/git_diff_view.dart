import 'package:flutter/material.dart';

import '../../l10n/l10n_extensions.dart';
import '../../theme/app_text_styles.dart';
import '../app_dialog.dart';
import '../diff/diff_viewer.dart';

/// Dialog hosting the full [DiffViewer] (side-by-side / unified, inline
/// highlights, change navigation) for a single source-control file change.
class GitDiffDialog extends StatelessWidget {
  const GitDiffDialog({
    required this.title,
    required this.diff,
    this.filePath,
    this.reloadDiff,
    this.onOpenSource,
    super.key,
  });

  final String title;
  final String diff;

  /// Path used for syntax highlighting (defaults to [title]).
  final String? filePath;

  /// Re-fetches the diff text for a given ignore-whitespace setting. When null,
  /// the ignore-whitespace toggle is hidden.
  final Future<String?> Function(bool ignoreWhitespace, bool fullContext)?
      reloadDiff;

  /// Opens the underlying file in the editor; shown as a toolbar button.
  final VoidCallback? onOpenSource;

  static Future<void> show(
    BuildContext context, {
    required String title,
    required String diff,
    String? filePath,
    Future<String?> Function(bool ignoreWhitespace, bool fullContext)?
        reloadDiff,
    VoidCallback? onOpenSource,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => GitDiffDialog(
        title: title,
        diff: diff,
        filePath: filePath,
        reloadDiff: reloadDiff,
        onOpenSource: onOpenSource,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      maxWidth: 1100,
      maxHeight: 720,
      contentPadding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: AppTextStyles.of(context).body.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                tooltip: MaterialLocalizations.of(context).closeButtonLabel,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const Divider(height: 1),
          Expanded(
            child: diff.trim().isEmpty
                ? Center(child: Text(context.l10n.diffNoChanges))
                : DiffViewer.fromUnifiedDiff(
                    diffText: diff,
                    filePath: filePath ?? title,
                    reloadDiff: reloadDiff,
                    onOpenSource: onOpenSource == null
                        ? null
                        : () {
                            Navigator.of(context).pop();
                            onOpenSource!.call();
                          },
                  ),
          ),
        ],
      ),
    );
  }
}
