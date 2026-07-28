import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/compose/compose_file_drop_ingestor.dart';
import 'package:teampilot/services/workspace_dnd/path_namespace.dart';
import 'package:teampilot/services/workspace_dnd/workspace_file_ref.dart';

class _RecordingSink {
  final references = <String>[];

  void insertReferences(List<String> refs) => references.addAll(refs);
}

void main() {
  group('ComposeFileDropIngestor', () {
    test('imports external image drops and inserts @ references', () async {
      final sink = _RecordingSink();
      final ingestor = ComposeFileDropIngestor(
        workspaceRoot: '/repo',
        onInsertReferences: sink.insertReferences,
      );

      final outcome = await ingestor.consume(
        WorkspaceDragPayload(
          kind: DragPayloadKind.workspaceFile,
          refs: [
            WorkspaceFileRef(
              nativePath: '/tmp/drop.png',
              namespace: const PathNamespace.localPosix(),
              isDirectory: false,
            ),
          ],
        ),
      );

      expect(outcome.delivered, 1);
      expect(sink.references, ['@/tmp/drop.png']);
    });

    test('inserts @ references for non-image files', () async {
      final sink = _RecordingSink();
      final ingestor = ComposeFileDropIngestor(
        workspaceRoot: '/repo',
        onInsertReferences: sink.insertReferences,
      );

      final outcome = await ingestor.consume(
        WorkspaceDragPayload(
          kind: DragPayloadKind.workspaceFile,
          refs: [
            WorkspaceFileRef(
              nativePath: '/tmp/config.json',
              namespace: const PathNamespace.localPosix(),
              isDirectory: false,
            ),
            WorkspaceFileRef(
              nativePath: '/repo/docs/readme.md',
              namespace: const PathNamespace.localPosix(),
              isDirectory: false,
            ),
          ],
        ),
      );

      expect(outcome.delivered, 2);
      expect(sink.references, ['@/tmp/config.json', '@docs/readme.md']);
    });

    test('skips directories', () async {
      final sink = _RecordingSink();
      final ingestor = ComposeFileDropIngestor(
        workspaceRoot: '/repo',
        onInsertReferences: sink.insertReferences,
      );

      final outcome = await ingestor.consume(
        WorkspaceDragPayload(
          kind: DragPayloadKind.workspaceFile,
          refs: [
            WorkspaceFileRef(
              nativePath: '/tmp/folder',
              namespace: const PathNamespace.localPosix(),
              isDirectory: true,
            ),
          ],
        ),
      );

      expect(outcome.delivered, 0);
      expect(sink.references, isEmpty);
    });
  });
}
