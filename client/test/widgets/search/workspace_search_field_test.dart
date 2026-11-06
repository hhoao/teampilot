import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/pages/home_workspace/workspace/workspace_search_widgets.dart';

void main() {
  testWidgets('WorkspaceSearchField uses the pill decoration', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WorkspaceSearchField(
            controller: controller,
            hint: 'Search workspace',
            onChanged: (_) {},
            onClear: controller.clear,
          ),
        ),
      ),
    );

    final field = tester.widget<TextField>(find.byType(TextField));
    final border = field.decoration!.enabledBorder! as OutlineInputBorder;
    expect(
      border.borderRadius,
      const BorderRadius.all(Radius.circular(tpSearchPillRadius)),
    );
  });
}
