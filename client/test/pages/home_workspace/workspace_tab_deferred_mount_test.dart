import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/pages/home_workspace/workspace/workspace_tab_deferred_mount.dart';
import 'package:teampilot/theme/workspace_surface_layers.dart';

void main() {
  testWidgets(
    'WorkspaceTabDeferredMount shows card chrome before heavy child',
    (tester) async {
      var builtPage = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: WorkspaceTabDeferredMount(
            active: true,
            builder: (_) {
              builtPage++;
              return const Text('workspace-page');
            },
          ),
        ),
      );

      expect(find.byType(WorkspacePageCardShell), findsOneWidget);
      expect(find.text('workspace-page'), findsNothing);
      expect(builtPage, 0);

      await tester.pump();
      await tester.pump();

      expect(find.text('workspace-page'), findsOneWidget);
      expect(builtPage, 1);
    },
  );
}
