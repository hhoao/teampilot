import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/content_search/content_search_cubit.dart';
import '../../l10n/l10n_extensions.dart';

/// Renders aggregated search results: a file header per [ContentSearchFileGroup]
/// followed by its matching lines with the match range highlighted.
class SearchPanelResults extends StatelessWidget {
  const SearchPanelResults({
    required this.files,
    required this.query,
    required this.truncated,
    required this.replacement,
    required this.onOpenResult,
    required this.onReplaceSingle,
    super.key,
  });

  final List<ContentSearchFileGroup> files;
  final String query;
  final bool truncated;
  final String replacement;
  final void Function(String path, int lineNumber) onOpenResult;
  final Future<void> Function(String path, String replacement) onReplaceSingle;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final styles = TpTextStyles.of(context);
    if (files.isEmpty) {
      return Center(
        child: Text(
          query.trim().isEmpty
              ? l10n.workspaceSearchEmptyHint
              : l10n.workspaceSearchNoResults,
          style: styles.mutedSm,
        ),
      );
    }
    final itemCount = files.length + (truncated ? 1 : 0);
    return ListView.builder(
      itemCount: itemCount,
      itemBuilder: (context, index) {
        if (index == files.length) {
          return Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              l10n.workspaceSearchTruncated,
              style: styles.mutedSm,
            ),
          );
        }
        final group = files[index];
        return _FileGroupTile(
          group: group,
          replacement: replacement,
          onOpenResult: onOpenResult,
          onReplaceSingle: onReplaceSingle,
        );
      },
    );
  }
}

class _FileGroupTile extends StatelessWidget {
  const _FileGroupTile({
    required this.group,
    required this.replacement,
    required this.onOpenResult,
    required this.onReplaceSingle,
  });

  final ContentSearchFileGroup group;
  final String replacement;
  final void Function(String path, int lineNumber) onOpenResult;
  final Future<void> Function(String path, String replacement) onReplaceSingle;

  int get _pendingCount => group.lines.where((l) => !l.replaced).length;

  Future<void> _confirmReplace(BuildContext context) async {
    final l10n = context.l10n;
    final count = _pendingCount;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => TpDialog(
        maxWidth: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TpDialogHeader(title: l10n.workspaceSearchReplaceAllTitle),
            const SizedBox(height: 16),
            Text(l10n.workspaceSearchReplaceAllMessage(count)),
            TpDialogActions(
              children: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: Text(l10n.cancel),
                ),
                TpButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: Text(l10n.workspaceSearchReplace),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (ok != true || !context.mounted) return;
    await onReplaceSingle(group.path, replacement);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);
    final pending = _pendingCount;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 10, 8, 2),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  group.relativePath,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: styles.smSemibold,
                ),
              ),
              Text('$pending', style: styles.smColored(cs.onSurfaceVariant)),
              const SizedBox(width: 4),
              TpButton(
                size: TpControlSize.small,
                variant: TpButtonVariant.outline,
                onPressed: replacement.isNotEmpty && pending > 0
                    ? () => _confirmReplace(context)
                    : null,
                child: Text(
                  context.l10n.workspaceSearchReplaceAll,
                  style: styles.xs,
                ),
              ),
            ],
          ),
        ),
        for (final line in group.lines)
          _LineTile(
            line: line,
            onTap: () => onOpenResult(group.path, line.lineNumber),
          ),
        Divider(height: 1, thickness: 1, color: cs.outlineVariant),
      ],
    );
  }
}

class _LineTile extends StatelessWidget {
  const _LineTile({required this.line, required this.onTap});

  final ContentSearchLineMatch line;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);
    final base = styles.sm;
    final text = line.lineText;
    final start = line.matchStart.clamp(0, text.length);
    final end = line.matchEnd.clamp(start, text.length);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 28,
              child: Text(
                '${line.lineNumber}',
                textAlign: TextAlign.right,
                style: styles.smColored(cs.onSurfaceVariant),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text.rich(
                TextSpan(
                  style: base,
                  children: [
                    if (start > 0) TextSpan(text: text.substring(0, start)),
                    TextSpan(
                      text: text.substring(start, end),
                      style: TextStyle(
                        color: cs.primary,
                        fontWeight: FontWeight.w600,
                        backgroundColor: cs.primary.withValues(alpha: 0.14),
                      ),
                    ),
                    if (end < text.length) TextSpan(text: text.substring(end)),
                  ],
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
