import 'package:flutter/material.dart';

import '../../services/workspace_dnd/workspace_drop_target.dart';
import '../../services/workspace_dnd/workspace_file_ref.dart';

/// Wraps a drop destination (e.g. a terminal) in a Flutter [DragTarget] for
/// [WorkspaceDragPayload]s and paints a hover highlight while a compatible drag
/// is over it. Delegates the actual ingest to a [WorkspaceDropTarget] so this
/// widget stays free of projection / quoting / paste concerns.
///
/// [DragTarget] only intercepts pointer events during an active drag, so the
/// wrapped child keeps its normal interaction (terminal focus, selection, taps).
class WorkspaceFileDropRegion extends StatefulWidget {
  const WorkspaceFileDropRegion({
    required this.target,
    required this.child,
    this.onOutcome,
    super.key,
  });

  /// Rebuilt by the caller as the destination changes; consulted for both
  /// [WorkspaceDropTarget.accepts] and [WorkspaceDropTarget.consume].
  final WorkspaceDropTarget target;
  final Widget child;

  /// Notified after a drop so the caller can surface partial rejections.
  final ValueChanged<DropOutcome>? onOutcome;

  @override
  State<WorkspaceFileDropRegion> createState() =>
      _WorkspaceFileDropRegionState();
}

class _WorkspaceFileDropRegionState extends State<WorkspaceFileDropRegion> {
  bool _highlighted = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DragTarget<WorkspaceDragPayload>(
      onWillAcceptWithDetails: (details) {
        final ok = widget.target.accepts(details.data.kind);
        if (ok && !_highlighted) setState(() => _highlighted = true);
        return ok;
      },
      onLeave: (_) {
        if (_highlighted) setState(() => _highlighted = false);
      },
      onAcceptWithDetails: (details) async {
        if (_highlighted) setState(() => _highlighted = false);
        final outcome = await widget.target.consume(details.data);
        widget.onOutcome?.call(outcome);
      },
      builder: (context, candidate, rejected) {
        return Stack(
          fit: StackFit.passthrough,
          children: [
            widget.child,
            if (_highlighted)
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(color: cs.primary, width: 2),
                      color: cs.primary.withValues(alpha: 0.08),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
