import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/compose/compose_landing_drop_ingestor.dart';
import 'package:teampilot/services/workspace_dnd/path_namespace.dart';
import 'package:teampilot/services/workspace_dnd/workspace_file_ref.dart';
import '../../support/in_memory_filesystem.dart';

class _RecordingSink {
  final references = <String>[];

  void insertReferences(List<String> refs) => references.addAll(refs);
}

void main() {
  group('ComposeLandingDropIngestor', () {
    test('imports external image drops and inserts @ references', () async {
      final fs = InMemoryFilesystem();
      const root = '/repo';
      const external = '/tmp/drop.png';
      await fs.writeBytes(external, [1, 2, 3]);

      final sink = _RecordingSink();
      final ingestor = ComposeLandingDropIngestor(
        workspaceRoot: root,
        onInsertReferences: sink.insertReferences,
      );

      final outcome = await ingestor.consume(
        WorkspaceDragPayload(
          kind: DragPayloadKind.workspaceFile,
          refs: [
            WorkspaceFileRef(
              nativePath: external,
              namespace: const PathNamespace.localPosix(),
              isDirectory: false,
            ),
          ],
        ),
      );

      expect(outcome.delivered, 1);
      expect(sink.references, ['@/tmp/drop.png']);
    });

    test('ignores non-image files', () async {
      final fs = InMemoryFilesystem();
      await fs.writeString('/tmp/readme.md', '# hi');

      final sink = _RecordingSink();
      final ingestor = ComposeLandingDropIngestor(
        workspaceRoot: '/repo',
        onInsertReferences: sink.insertReferences,
      );

      final outcome = await ingestor.consume(
        WorkspaceDragPayload(
          kind: DragPayloadKind.workspaceFile,
          refs: [
            WorkspaceFileRef(
              nativePath: '/tmp/readme.md',
              namespace: const PathNamespace.localPosix(),
              isDirectory: false,
            ),
          ],
        ),
      );

      expect(outcome.delivered, 0);
      expect(sink.references, isEmpty);
    });
  });
}
