import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';

void main() {
  testWidgets('catalog search header uses the pill decoration', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TpCatalogDiscoveryHeader(
            title: 'Skills',
            searchController: controller,
            searchHint: 'Search skills',
            onSearchChanged: (_) {},
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
