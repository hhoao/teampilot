import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/content_search/content_search_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../find/find_bar_widgets.dart';

/// Renders aggregated search results: collapsible file groups with matching
/// lines, a hover replace action per file, and the truncation footer.
class SearchPanelResults extends StatelessWidget {
  const SearchPanelResults({
    required this.files,
    required this.query,
    required this.truncated,
    required this.replacement,
    required this.collapsedPaths,
    required this.onToggleGroup,
    required this.onOpenResult,
    required this.onReplaceSingle,
    super.key,
  });

  final List<ContentSearchFileGroup> files;
  final String query;
  final bool truncated;
  final String replacement;
  final Set<String> collapsedPaths;
  final void Function(String path) onToggleGroup;
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
          key: ValueKey('search-group-${group.path}'),
          group: group,
          collapsed: collapsedPaths.contains(group.path),
          replacement: replacement,
          onToggleGroup: () => onToggleGroup(group.path),
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
    required this.collapsed,
    required this.replacement,
    required this.onToggleGroup,
    required this.onOpenResult,
    required this.onReplaceSingle,
    super.key,
  });

  final ContentSearchFileGroup group;
  final bool collapsed;
  final String replacement;
  final VoidCallback onToggleGroup;
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _GroupHeader(
          group: group,
          collapsed: collapsed,
          pendingCount: _pendingCount,
          replaceEnabled: replacement.isNotEmpty && _pendingCount > 0,
          onToggle: onToggleGroup,
          onReplace: () => _confirmReplace(context),
        ),
        if (!collapsed)
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

class _GroupHeader extends StatefulWidget {
  const _GroupHeader({
    required this.group,
    required this.collapsed,
    required this.pendingCount,
    required this.replaceEnabled,
    required this.onToggle,
    required this.onReplace,
  });

  final ContentSearchFileGroup group;
  final bool collapsed;
  final int pendingCount;
  final bool replaceEnabled;
  final VoidCallback onToggle;
  final VoidCallback onReplace;

  @override
  State<_GroupHeader> createState() => _GroupHeaderState();
}

class _GroupHeaderState extends State<_GroupHeader> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: InkWell(
        onTap: widget.onToggle,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
          child: Row(
            children: [
              AnimatedRotation(
                turns: widget.collapsed ? 0 : 0.25,
                duration: const Duration(milliseconds: 120),
                child: Icon(
                  Icons.chevron_right,
                  size: 14,
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 2),
              Expanded(
                child: Text(
                  widget.group.relativePath,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: styles.smSemibold,
                ),
              ),
              Text(
                '${widget.pendingCount}',
                style: styles.smColored(cs.onSurfaceVariant),
              ),
              const SizedBox(width: 4),
              // Hover-only per-file replace action, like the VS Code search
              // view. AnimatedOpacity keeps it hit-testable so tests can tap
              // it without synthesizing a hover.
              AnimatedOpacity(
                opacity: _hovering ? 1 : 0,
                duration: const Duration(milliseconds: 120),
                child: FindActionButton(
                  key: const ValueKey('search-file-replace-all'),
                  assetPath: FindBarIcons.replaceAll,
                  tooltip: context.l10n.workspaceSearchReplaceAll,
                  enabled: widget.replaceEnabled,
                  width: 22,
                  height: 22,
                  onTap: widget.onReplace,
                ),
              ),
            ],
          ),
        ),
      ),
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
