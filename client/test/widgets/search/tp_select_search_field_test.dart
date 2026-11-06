import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';

void main() {
  testWidgets('TpSelectSearchField uses the pill decoration', (tester) async {
    final controller = TextEditingController();
    final focus = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focus.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TpSelectSearchField(
            controller: controller,
            focusNode: focus,
            hintText: 'Search',
            onChanged: (_) {},
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
