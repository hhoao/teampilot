import 'package:flutter/material.dart';

import '../../l10n/l10n_extensions.dart';
import '../../theme/app_text_styles.dart';

/// Read-only unified-diff dialog with simple +/- / hunk coloring.
///
/// Kept deliberately lightweight (no re-editor diff editor) per the
/// source-control panel's "simple" scope.
class GitDiffDialog extends StatelessWidget {
  const GitDiffDialog({required this.title, required this.diff, super.key});

  final String title;
  final String diff;

  static Future<void> show(
    BuildContext context, {
    required String title,
    required String diff,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => GitDiffDialog(title: title, diff: diff),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final lines = diff.isEmpty
        ? const <String>[]
        : diff.replaceAll('\r\n', '\n').split('\n');

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900, maxHeight: 640),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
              child: Row(
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
            ),
            const Divider(height: 1),
            Expanded(
              child: lines.isEmpty
                  ? Center(
                      child: Text(
                        context.l10n.gitNoChanges,
                        style: AppTextStyles.of(context).bodySmall.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    )
                  : Scrollbar(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.vertical,
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (final line in lines)
                                _DiffLine(line: line, cs: cs),
                            ],
                          ),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DiffLine extends StatelessWidget {
  const _DiffLine({required this.line, required this.cs});

  final String line;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    Color? color;
    Color? background;
    if (line.startsWith('+') && !line.startsWith('+++')) {
      color = const Color(0xFF2EA043);
      background = const Color(0x142EA043);
    } else if (line.startsWith('-') && !line.startsWith('---')) {
      color = cs.error;
      background = cs.error.withValues(alpha: 0.08);
    } else if (line.startsWith('@@')) {
      color = cs.primary;
    } else if (line.startsWith('diff ') ||
        line.startsWith('index ') ||
        line.startsWith('+++') ||
        line.startsWith('---')) {
      color = cs.onSurfaceVariant;
    }

    return Container(
      color: background,
      width: double.infinity,
      child: Text(
        line.isEmpty ? ' ' : line,
        style: TextStyle(
          fontFamily: 'monospace',
          fontFamilyFallback: const ['Menlo', 'Consolas', 'Courier New'],
          fontSize: 12.5,
          height: 1.45,
          color: color ?? cs.onSurface,
        ),
        softWrap: false,
      ),
    );
  }
}
