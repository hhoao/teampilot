import '../workspace_dnd/workspace_drop_target.dart';
import '../workspace_dnd/workspace_file_ref.dart';
import 'compose_file_attach.dart';

/// Compose drop target: inserts `@` path references for files and directories.
class ComposeFileDropIngestor implements WorkspaceDropTarget {
  ComposeFileDropIngestor({
    required this.workspaceRoot,
    required this.onInsertReferences,
  });

  final String workspaceRoot;
  final void Function(List<String> references) onInsertReferences;

  @override
  bool accepts(DragPayloadKind kind) => kind == DragPayloadKind.workspaceFile;

  @override
  Future<DropOutcome> consume(WorkspaceDragPayload payload) async {
    if (!accepts(payload.kind) || payload.isEmpty) return DropOutcome.empty;

    final references = <String>[];
    var skipped = 0;
    for (final ref in payload.refs) {
      final reference = await resolveComposeFileReference(
        absolutePath: ref.nativePath,
        workspaceRoot: workspaceRoot,
      );
      if (reference == null) {
        skipped += 1;
        continue;
      }
      // Match @-mention directory tokens (`@docs/`) so dropped folders
      // keep the same trailing-slash spelling as autocomplete.
      references.add(
        ref.isDirectory && !reference.endsWith('/')
            ? '$reference/'
            : reference,
      );
    }

    if (references.isEmpty) {
      return DropOutcome(rejectedCrossNamespace: skipped);
    }

    onInsertReferences(references);
    return DropOutcome(
      delivered: references.length,
      rejectedCrossNamespace: skipped,
    );
  }
}
