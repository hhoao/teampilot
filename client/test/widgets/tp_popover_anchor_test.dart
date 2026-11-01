import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';

void main() {
  testWidgets(
    'growing a bottom-anchored panel keeps its bottom edge on the anchor',
    (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final controller = TpPopoverController();
      addTearDown(controller.dispose);
      var panelHeight = 120.0;
      late StateSetter setPanelHeight;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomLeft,
              child: StatefulBuilder(
                builder: (context, setState) {
                  setPanelHeight = setState;
                  return TpPopover(
                    controller: controller,
                    transitionDuration: Duration.zero,
                    padding: EdgeInsets.zero,
                    anchor: const TpAnchor(
                      childAlignment: Alignment.bottomLeft,
                      overlayAlignment: Alignment.topLeft,
                      offset: Offset(0, -8),
                    ),
                    popover: (context) => SizedBox(
                      key: const Key('panel'),
                      width: 200,
                      height: panelHeight,
                    ),
                    child: const SizedBox(
                      key: Key('anchor'),
                      width: 40,
                      height: 24,
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );

      controller.show();
      await tester.pumpAndSettle();

      final anchor = tester.getRect(find.byKey(const Key('anchor')));
      final before = tester.getRect(find.byKey(const Key('panel')));
      expect(before.bottom, moreOrLessEquals(anchor.top - 8));

      // Taller content (e.g. an error line rendered after a failed refresh)
      // must grow upward from the anchor, not flip above it.
      setPanelHeight(() => panelHeight = 600);
      await tester.pumpAndSettle();

      final after = tester.getRect(find.byKey(const Key('panel')));
      expect(after.height, greaterThan(before.height));
      expect(after.bottom, moreOrLessEquals(anchor.top - 8));
      expect(after.top, lessThan(before.top));
    },
  );
}
