import 'package:flutter/material.dart';

import '../../services/workspace_dnd/workspace_file_ref.dart';
import '../../theme/app_text_styles.dart';

/// Wraps a file-tree-style row so it can be dragged onto a [WorkspaceDropTarget]
/// (e.g. a terminal). The drag-source half of workspace drag-and-drop: any row
/// that can name a [WorkspaceDragPayload] becomes draggable by wrapping its
/// visual in this — the row itself stays unaware of drop mechanics.
///
/// Uses [Draggable] (movement-threshold), not long-press, so desktop taps to
/// open a file still register. Feedback is a lightweight chip — no GlobalKey
/// reparenting — to stay clear of the nested-LayoutBuilder drag fragility the
/// workbench has hit before.
class DraggableFileRow extends StatelessWidget {
  const DraggableFileRow({
    required this.payload,
    required this.label,
    required this.child,
    this.enabled = true,
    super.key,
  });

  /// Built once per row; carries the dragged refs in their source namespace.
  final WorkspaceDragPayload payload;

  /// Filename shown in the drag feedback chip.
  final String label;

  final Widget child;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    if (!enabled || payload.isEmpty) return child;
    return Draggable<WorkspaceDragPayload>(
      data: payload,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: _DragFeedback(label: label, count: payload.refs.length),
      childWhenDragging: Opacity(opacity: 0.4, child: child),
      child: child,
    );
  }
}

class _DragFeedback extends StatelessWidget {
  const _DragFeedback({required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = count > 1 ? '$label +${count - 1}' : label;
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: cs.secondaryContainer,
          borderRadius: BorderRadius.circular(6),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.insert_drive_file_outlined, size: 14, color: cs.onSecondaryContainer),
            const SizedBox(width: 6),
            Text(
              text,
              style: AppTextStyles.of(context).bodySmallColored(
                cs.onSecondaryContainer,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
