import 'package:flutter/material.dart';

import '../../l10n/l10n_extensions.dart';
import 'diff_view_controller.dart';

/// Which diff layout the viewer is showing.
enum DiffViewMode { sideBySide, unified }

/// Toolbar for the diff viewer: layout switch, ignore-whitespace toggle, and
/// next/previous-change navigation with a counter.
class DiffToolbar extends StatelessWidget {
  const DiffToolbar({
    required this.controller,
    required this.mode,
    required this.onModeChanged,
    required this.ignoreWhitespace,
    required this.onIgnoreWhitespaceChanged,
    this.showIgnoreWhitespace = true,
    this.fullContext = false,
    required this.onFullContextChanged,
    this.showFullContext = false,
    this.onOpenSource,
    super.key,
  });

  final DiffViewController controller;
  final DiffViewMode mode;
  final ValueChanged<DiffViewMode> onModeChanged;
  final bool ignoreWhitespace;
  final ValueChanged<bool> onIgnoreWhitespaceChanged;
  final bool showIgnoreWhitespace;

  /// When true, the whole file is shown; otherwise only changed regions.
  final bool fullContext;
  final ValueChanged<bool> onFullContextChanged;
  final bool showFullContext;

  /// Opens the underlying file in the editor. Hidden when null.
  final VoidCallback? onOpenSource;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;

    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(bottom: BorderSide(color: cs.outlineVariant)),
      ),
      child: Row(
        children: [
          SegmentedButton<DiffViewMode>(
            showSelectedIcon: false,
            style: ButtonStyle(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            segments: [
              ButtonSegment(
                value: DiffViewMode.sideBySide,
                icon: Icon(Icons.view_column_outlined, size: 18),
                tooltip: l10n.diffViewSideBySide,
              ),
              ButtonSegment(
                value: DiffViewMode.unified,
                icon: Icon(Icons.view_agenda_outlined, size: 18),
                tooltip: l10n.diffViewUnified,
              ),
            ],
            selected: {mode},
            onSelectionChanged: (s) => onModeChanged(s.first),
          ),
          if (showFullContext) ...[
            const SizedBox(width: 8),
            FilterChip(
              visualDensity: VisualDensity.compact,
              label: Text(l10n.diffShowAllLines),
              selected: fullContext,
              onSelected: onFullContextChanged,
            ),
          ],
          if (showIgnoreWhitespace) ...[
            const SizedBox(width: 8),
            FilterChip(
              visualDensity: VisualDensity.compact,
              label: Text(l10n.diffIgnoreWhitespace),
              selected: ignoreWhitespace,
              onSelected: onIgnoreWhitespaceChanged,
            ),
          ],
          const Spacer(),
          if (onOpenSource != null)
            IconButton(
              icon: Icon(Icons.open_in_new),
              tooltip: l10n.diffOpenSourceFile,
              visualDensity: VisualDensity.compact,
              onPressed: onOpenSource,
            ),
          AnimatedBuilder(
            animation: controller,
            builder: (context, _) {
              final total = controller.changeCount;
              final enabled = total > 0;
              final current = controller.current < 0
                  ? 0
                  : controller.current + 1;
              return Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.keyboard_arrow_up),
                    tooltip: l10n.diffPreviousChange,
                    visualDensity: VisualDensity.compact,
                    onPressed: enabled ? controller.previous : null,
                  ),
                  ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 52),
                    child: Text(
                      enabled
                          ? l10n.diffChangeCounter(current, total)
                          : l10n.diffNoChanges,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.keyboard_arrow_down),
                    tooltip: l10n.diffNextChange,
                    visualDensity: VisualDensity.compact,
                    onPressed: enabled ? controller.next : null,
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
