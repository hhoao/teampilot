import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/services/selection_ai/selection_ask_ai.dart';

void main() {
  testWidgets('empty AI context does not open compose dialog', (tester) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (builderContext) {
            context = builderContext;
            return const SizedBox();
          },
        ),
      ),
    );

    await SelectionAskAi.openComposeDialog(
      context,
      aiContext: '  ',
      workspace: Workspace(workspaceId: 'workspace-1', createdAt: 1),
      tabScopeId: 'workspace-1',
    );
    await tester.pump();

    expect(find.byType(Dialog), findsNothing);
  });
}
