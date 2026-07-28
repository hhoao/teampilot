import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/compose/compose_file_drop_ingestor.dart';
import 'package:teampilot/widgets/compose/compose_file_drop_region.dart';
import 'package:teampilot/widgets/workspace_dnd/external_file_drop_region.dart';
import 'package:teampilot/widgets/workspace_dnd/workspace_file_drop_region.dart';

void main() {
  testWidgets('ComposeFileDropRegion wraps External and Workspace drop regions',
      (tester) async {
    final target = ComposeFileDropIngestor(
      workspaceRoot: '/repo',
      onInsertReferences: (_) {},
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ComposeFileDropRegion(
          target: target,
          child: const SizedBox(key: Key('child')),
        ),
      ),
    );
    expect(find.byType(ExternalFileDropRegion), findsOneWidget);
    expect(find.byType(WorkspaceFileDropRegion), findsOneWidget);
    expect(find.byKey(const Key('child')), findsOneWidget);
  });
}
