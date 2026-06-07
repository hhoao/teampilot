import 'package:flutter/material.dart';

import '../../services/git/git_changes_visible_rows.dart';
import '../../theme/app_text_styles.dart';
import '../hover_widget.dart';

/// Folder row in the git changes tree view.
class GitChangeFolderTile extends StatefulWidget {
  const GitChangeFolderTile({
    required this.name,
    required this.depth,
    required this.isExpanded,
    required this.onToggle,
    super.key,
  });

  final String name;
  final int depth;
  final bool isExpanded;
  final VoidCallback onToggle;

  @override
  State<GitChangeFolderTile> createState() => _GitChangeFolderTileState();
}

class _GitChangeFolderTileState extends State<GitChangeFolderTile> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rowColor = _hovered ? HoverWidget.defaultHoverColor(context) : null;

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
              ],
            ),
          ),
        ),
      ),
    );
  }
}
