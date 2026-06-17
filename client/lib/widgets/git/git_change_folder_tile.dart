import 'package:flutter/material.dart';

import '../../l10n/l10n_extensions.dart';
import '../../services/git/git_changes_visible_rows.dart';
import '../../theme/app_text_styles.dart';
import '../app_icon_button.dart';
import '../hover_widget.dart';

/// Folder row in the git changes tree view.
class GitChangeFolderTile extends StatefulWidget {
  const GitChangeFolderTile({
    required this.name,
    required this.depth,
    required this.isExpanded,
    required this.onToggle,
    this.onStage,
    this.onUnstage,
    super.key,
  });

  final String name;
  final int depth;
  final bool isExpanded;
  final VoidCallback onToggle;
  final VoidCallback? onStage;
  final VoidCallback? onUnstage;

  @override
  State<GitChangeFolderTile> createState() => _GitChangeFolderTileState();
}

class _GitChangeFolderTileState extends State<GitChangeFolderTile> {
  var _hovered = false;

  List<Widget> _actions(BuildContext context) {
    final l10n = context.l10n;
    final actions = <Widget>[];
    if (widget.onUnstage != null) {
      actions.add(
        AppIconButton(
          icon: Icons.remove,
          compact: true,
          size: AppIconButton.kCompactSize,
          tooltip: l10n.gitUnstageFolder,
          onTap: widget.onUnstage!,
        ),
      );
    }
    if (widget.onStage != null) {
      actions.add(
        AppIconButton(
          icon: Icons.add,
          compact: true,
          size: AppIconButton.kCompactSize,
          tooltip: l10n.gitStageFolder,
          onTap: widget.onStage!,
        ),
      );
    }
    return actions;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rowColor = _hovered ? HoverWidget.defaultHoverColor(context) : null;
    final showActions =
        _hovered && (widget.onStage != null || widget.onUnstage != null);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onToggle,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: double.infinity,
          height: double.infinity,
          clipBehavior: Clip.none,
          decoration: rowColor != null
              ? BoxDecoration(
                  color: rowColor,
                  borderRadius: BorderRadius.circular(6),
                )
              : null,
          padding: EdgeInsets.only(
            left:
                widget.depth * kGitChangesIndentWidth +
                kGitChangesNodePaddingLeft,
            right: kGitChangesNodePaddingRight,
          ),
          child: OverflowBox(
            maxWidth: double.infinity,
            alignment: Alignment.centerLeft,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: AnimatedRotation(
                    turns: widget.isExpanded ? 0.25 : 0.0,
                    duration: const Duration(milliseconds: 150),
                    child: Icon(
                      Icons.chevron_right,
                      size: 16,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
                Icon(
                  widget.isExpanded ? Icons.folder_open : Icons.folder_outlined,
                  color: cs.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Text(
                  widget.name,
                  maxLines: 1,
                  style: AppTextStyles.of(context).body,
                ),
                if (showActions) ...[
                  const SizedBox(width: 8),
                  ..._actions(context),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
