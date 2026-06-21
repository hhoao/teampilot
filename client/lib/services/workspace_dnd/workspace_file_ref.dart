import 'path_namespace.dart';

/// What kind of thing is being dragged. Drop targets accept a subset; new drag
/// sources (git changes, search hits, editor tabs) add a kind here without
/// touching existing targets.
enum DragPayloadKind {
  /// A file or directory from a workspace folder.
  workspaceFile,
}

/// A single dragged filesystem entry, carrying enough identity to survive being
/// dropped somewhere with a different path namespace.
///
/// [nativePath] is spelled in [namespace]; a drop target re-expresses it in its
/// own namespace via [PathProjection].
class WorkspaceFileRef {
  const WorkspaceFileRef({
    required this.nativePath,
    required this.namespace,
    required this.isDirectory,
  });

  /// Absolute path as the *source* sees it (the file tree's filesystem).
  final String nativePath;

  /// The namespace [nativePath] is spelled in (captured at drag start).
  final PathNamespace namespace;

  final bool isDirectory;

  @override
  bool operator ==(Object other) =>
      other is WorkspaceFileRef &&
      other.nativePath == nativePath &&
      other.namespace == namespace &&
      other.isDirectory == isDirectory;

  @override
  int get hashCode => Object.hash(nativePath, namespace, isDirectory);

  @override
  String toString() => 'WorkspaceFileRef($nativePath @ $namespace)';
}

/// The neutral payload transported by `Draggable<WorkspaceDragPayload>` and
/// consumed by a [WorkspaceDropTarget]. Always a list so multi-select drags are
/// the same shape as single-file drags.
class WorkspaceDragPayload {
  const WorkspaceDragPayload({required this.kind, required this.refs});

  /// Convenience for the common single-file drag.
  WorkspaceDragPayload.singleFile(WorkspaceFileRef ref)
    : kind = DragPayloadKind.workspaceFile,
      refs = [ref];

  final DragPayloadKind kind;
  final List<WorkspaceFileRef> refs;

  bool get isEmpty => refs.isEmpty;
}
