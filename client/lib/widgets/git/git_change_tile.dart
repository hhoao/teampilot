import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../l10n/l10n_extensions.dart';
import '../../models/git_status.dart';
import '../../services/git/git_changes_visible_rows.dart';
import '../../theme/app_text_styles.dart';
import '../app_icon_button.dart';
import '../file_icon_widget.dart';
import '../hover_widget.dart';

/// One changed file row in the source control changes tree.
///
/// Shows a status badge + file name; trailing actions depend on the area:
/// staged rows offer "unstage", unstaged rows offer "discard" + "stage".
/// Tapping the row opens the diff.
class GitChangeTile extends StatefulWidget {
  const GitChangeTile({
    required this.change,
    required this.depth,
    required this.onOpenDiff,
    required this.onStage,
    required this.onUnstage,
    required this.onDiscard,
    this.hoverEnabled = true,
    super.key,
  });

  final GitFileChange change;
  final int depth;
  final VoidCallback onOpenDiff;
  final VoidCallback onStage;
  final VoidCallback onUnstage;
  final VoidCallback onDiscard;
  final bool hoverEnabled;

  @override
  State<GitChangeTile> createState() => _GitChangeTileState();
}

class _GitChangeTileState extends State<GitChangeTile> {
  var _hovered = false;

  @override
  void didUpdateWidget(covariant GitChangeTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.hoverEnabled && _hovered) {
      _hovered = false;
    }
  }

  void _setHovered(bool value) {
    if (!widget.hoverEnabled || _hovered == value) return;
    setState(() => _hovered = value);
  }

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
    final change = widget.change;
    final name = p.basename(change.path);
    final rowColor = _hovered ? HoverWidget.defaultHoverColor(context) : null;

    return RepaintBoundary(
      child: MouseRegion(
        onEnter: (_) => _setHovered(true),
        onExit: (_) => _setHovered(false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onOpenDiff,
          child: Container(
            width: double.infinity,
            height: double.infinity,
            clipBehavior: Clip.none,
            decoration: rowColor != null
                ? BoxDecoration(
                    color: rowColor,
                    borderRadius: BorderRadius.circular(6),
                  )
                : null,
            padding: EdgeInsets.fromLTRB(
              widget.depth * kGitChangesIndentWidth +
                  kGitChangesNodePaddingLeft +
                  kGitChangesRowHorizontalPadding,
              kGitChangesRowVerticalPadding,
              kGitChangesNodePaddingRight + kGitChangesRowHorizontalPadding,
              kGitChangesRowVerticalPadding,
            ),
            child: OverflowBox(
              maxWidth: double.infinity,
              alignment: Alignment.centerLeft,
              child: SizedBox(
                height: kGitChangesNodeHeight,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(width: 16),
                    FileIconWidget(fileName: name),
                    const SizedBox(width: 6),
                    Text(
                      name,
                      maxLines: 1,
                      style: AppTextStyles.of(context).body,
                    ),
                    const SizedBox(width: 8),
                    if (_hovered) ..._actions(context) else _badge(cs),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
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

  List<Widget> _actions(BuildContext context) {
    final l10n = context.l10n;
    if (widget.change.staged) {
      return [
        AppIconButton(
          icon: Icons.remove,
          compact: true,
          size: AppIconButton.kCompactSize,
          tooltip: l10n.gitUnstage,
          onTap: widget.onUnstage,
        ),
      ];
    }
    return [
      AppIconButton(
        icon: Icons.undo,
        compact: true,
        size: AppIconButton.kCompactSize,
        tooltip: l10n.gitDiscard,
        onTap: widget.onDiscard,
      ),
      AppIconButton(
        icon: Icons.add,
        compact: true,
        size: AppIconButton.kCompactSize,
        tooltip: l10n.gitStage,
        onTap: widget.onStage,
      ),
    ];
  }
}
