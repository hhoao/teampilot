import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../l10n/l10n_extensions.dart';
import '../../models/git_status.dart';
import '../../services/git/git_changes_visible_rows.dart';
import '../../theme/app_text_styles.dart';
import '../app_icon_button.dart';
import '../file_icon_widget.dart';
import '../hover_widget.dart';

/// One changed file row in the source control panel.
///
/// Shows a status badge + file name; trailing actions depend on the area:
/// staged rows offer "unstage", unstaged rows offer "discard" + "stage".
/// Tapping the row opens the diff.
class GitChangeTile extends StatefulWidget {
  const GitChangeTile({
    required this.change,
    required this.onOpenDiff,
    required this.onStage,
    required this.onUnstage,
    required this.onDiscard,
    this.depth = 0,
    this.treeLayout = false,
    super.key,
  });

  final GitFileChange change;
  final VoidCallback onOpenDiff;
  final VoidCallback onStage;
  final VoidCallback onUnstage;
  final VoidCallback onDiscard;
  final int depth;
  final bool treeLayout;

  @override
  State<GitChangeTile> createState() => _GitChangeTileState();
}

class _GitChangeTileState extends State<GitChangeTile> {
  var _hovered = false;

  Color _badgeColor(ColorScheme cs) => switch (widget.change.kind) {
    GitChangeKind.added => const Color(0xFF2EA043),
    GitChangeKind.untracked => const Color(0xFF2EA043),
    GitChangeKind.deleted => cs.error,
    GitChangeKind.conflicted => cs.error,
    GitChangeKind.renamed => cs.primary,
    GitChangeKind.modified => const Color(0xFFB58900),
  };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final change = widget.change;
    final name = p.basename(change.path);
    final dir = p.dirname(change.path);
    final showDir = !widget.treeLayout && dir != '.' && dir.isNotEmpty;
    final rowColor = _hovered ? HoverWidget.defaultHoverColor(context) : null;
    final leftPadding = widget.treeLayout
        ? widget.depth * kGitChangesIndentWidth + kGitChangesNodePaddingLeft
        : kGitChangesNodePaddingLeft;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onOpenDiff,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: widget.treeLayout ? double.infinity : null,
          height: widget.treeLayout ? double.infinity : null,
          clipBehavior: Clip.none,
          decoration: rowColor != null
              ? BoxDecoration(
                  color: rowColor,
                  borderRadius: BorderRadius.circular(6),
                )
              : null,
          padding: EdgeInsets.only(
            left: leftPadding,
            right: kGitChangesNodePaddingRight,
            top: widget.treeLayout ? 0 : 4,
            bottom: widget.treeLayout ? 0 : 4,
          ),
          child: widget.treeLayout
              ? _buildTreeRow(context, cs, l10n, change, name)
              : _buildListRow(context, cs, l10n, change, name, showDir, dir),
        ),
      ),
    );
  }

  Widget _buildTreeRow(
    BuildContext context,
    ColorScheme cs,
    AppLocalizations l10n,
    GitFileChange change,
    String name,
  ) {
    return OverflowBox(
      maxWidth: double.infinity,
      alignment: Alignment.centerLeft,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(width: 16),
          FileIconWidget(fileName: name),
          const SizedBox(width: 6),
          Text(name, maxLines: 1, style: AppTextStyles.of(context).body),
          const SizedBox(width: 8),
          if (_hovered) ..._actions(l10n) else _badge(cs),
        ],
      ),
    );
  }

  Widget _buildListRow(
    BuildContext context,
    ColorScheme cs,
    AppLocalizations l10n,
    GitFileChange change,
    String name,
    bool showDir,
    String dir,
  ) {
    return Row(
      children: [
        const SizedBox(width: 2),
        FileIconWidget(fileName: name),
        const SizedBox(width: 6),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Flexible(
                child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              if (showDir) ...[
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    dir,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.of(context).caption.copyWith(
                      color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        if (_hovered) ..._actions(l10n) else _badge(cs),
      ],
    );
  }

  Widget _badge(ColorScheme cs) => SizedBox(
    width: 22,
    child: Text(
      widget.change.badge,
      textAlign: TextAlign.center,
      style: AppTextStyles.of(
        context,
      ).bodySmall.copyWith(color: _badgeColor(cs), fontWeight: FontWeight.w700),
    ),
  );

  List<Widget> _actions(AppLocalizations l10n) {
    if (widget.change.staged) {
      return [
        AppIconButton(
          icon: Icons.remove,
          compact: true, size: AppIconButton.kCompactSize,
          tooltip: l10n.gitUnstage,
          onTap: widget.onUnstage,
        ),
      ];
    }
    return [
      AppIconButton(
        icon: Icons.undo,
        compact: true, size: AppIconButton.kCompactSize,
        tooltip: l10n.gitDiscard,
        onTap: widget.onDiscard,
      ),
      AppIconButton(
        icon: Icons.add,
        compact: true, size: AppIconButton.kCompactSize,
        tooltip: l10n.gitStage,
        onTap: widget.onStage,
      ),
    ];
  }
}
