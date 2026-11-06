import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/pages/home_workspace/workspaces_tab.dart';

void main() {
  testWidgets('WorkspacesFilterField uses a stadium radius', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WorkspacesFilterField(
            controller: controller,
            hintText: 'Filter workspaces',
            onChanged: (_) {},
          ),
        ),
      ),
    );

    final containerFinder = find.descendant(
      of: find.byType(WorkspacesFilterField),
      matching: find.byType(AnimatedContainer),
    );
    final size = tester.getSize(containerFinder);
    final container = tester.widget<AnimatedContainer>(containerFinder);
    final decoration = container.decoration! as BoxDecoration;
    expect(
      decoration.borderRadius,
      BorderRadius.circular(size.height / 2),
    );
  });
}
