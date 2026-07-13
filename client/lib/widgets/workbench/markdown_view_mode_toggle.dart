import 'package:flutter/material.dart';

import '../../l10n/l10n_extensions.dart';
import '../../services/editor/markdown_view_mode_store.dart';
import '../../theme/app_icon_sizes.dart';
import '../app_icon_button.dart';

/// Compact Source | Preview pill for markdown files (mirrors File|Diff).
class MarkdownViewModeToggle extends StatelessWidget {
  const MarkdownViewModeToggle({
    required this.mode,
    required this.onModeChanged,
    super.key,
  });

  final MarkdownViewMode mode;
  final ValueChanged<MarkdownViewMode> onModeChanged;

  static const double _size = AppIconButton.kCompactSize;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final color = cs.iconMuted;
    return Container(
      height: _size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Segment(
            icon: Icons.code,
            tooltip: l10n.markdownViewToggleSource,
            selected: mode == MarkdownViewMode.source,
            color: color,
            onTap: () => onModeChanged(MarkdownViewMode.source),
          ),
          Container(width: 1, height: 14, color: cs.outlineVariant),
          _Segment(
            icon: Icons.visibility_outlined,
            tooltip: l10n.markdownViewTogglePreview,
            selected: mode == MarkdownViewMode.preview,
            color: color,
            onTap: () => onModeChanged(MarkdownViewMode.preview),
          ),
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.icon,
    required this.tooltip,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: selected
            ? cs.onSurface.withValues(alpha: 0.12)
            : Colors.transparent,
        child: InkWell(
          onTap: onTap,
          hoverColor: color.withValues(alpha: 0.12),
          splashColor: color.withValues(alpha: 0.2),
          child: SizedBox(
            width: 30,
            height: MarkdownViewModeToggle._size,
            child: Icon(icon, size: context.appIconSizes.sm, color: color),
          ),
        ),
      ),
    );
  }
}
