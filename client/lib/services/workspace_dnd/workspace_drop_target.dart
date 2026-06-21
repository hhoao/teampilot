import 'workspace_file_ref.dart';

/// Result of consuming a drop, surfaced so the UI can report partial success
/// (e.g. local files rejected when dropped on a remote terminal).
class DropOutcome {
  const DropOutcome({this.delivered = 0, this.rejectedCrossNamespace = 0});

  /// Refs successfully injected into the target.
  final int delivered;

  /// Refs skipped because they live on a different machine than the target and
  /// the cross-namespace strategy declined them.
  final int rejectedCrossNamespace;

  bool get anyDelivered => delivered > 0;
  bool get anyRejected => rejectedCrossNamespace > 0;

  static const empty = DropOutcome();
}

/// A place a [WorkspaceDragPayload] can be dropped (terminal, editor, composer).
/// Each target declares the payload kinds it understands and how to consume
/// them; the UI layer wraps it in a Flutter `DragTarget`. Adding a new drop
/// destination means implementing this — existing sources stay untouched.
abstract interface class WorkspaceDropTarget {
  bool accepts(DragPayloadKind kind);

  Future<DropOutcome> consume(WorkspaceDragPayload payload);
}
