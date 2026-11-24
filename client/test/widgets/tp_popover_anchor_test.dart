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

  Widget bottomTriggerPopover({
    required TpPopoverController controller,
    required Widget panel,
    bool capHeightToAnchorSide = false,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomLeft,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 24),
            child: TpPopover(
              controller: controller,
              transitionDuration: Duration.zero,
              padding: EdgeInsets.zero,
              capHeightToAnchorSide: capHeightToAnchorSide,
              anchor: const TpAnchor(
                childAlignment: Alignment.topLeft,
                overlayAlignment: Alignment.bottomLeft,
                offset: Offset(0, 4),
              ),
              popover: (context) => panel,
              child: const SizedBox(key: Key('anchor'), width: 120, height: 32),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets(
    'a menu that does not fit below flips above the trigger, not over it',
    (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final controller = TpPopoverController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        bottomTriggerPopover(
          controller: controller,
          panel: const SizedBox(key: Key('panel'), width: 200, height: 300),
        ),
      );
      controller.show();
      await tester.pumpAndSettle();

      final anchor = tester.getRect(find.byKey(const Key('anchor')));
      final panel = tester.getRect(find.byKey(const Key('panel')));
      // Flipping must anchor the panel's bottom to the trigger's top edge,
      // leaving the 4px gap the below-placement would have used.
      expect(panel.bottom, moreOrLessEquals(anchor.top - 4));
      expect(panel.bottom, lessThanOrEqualTo(anchor.top));
      expect(panel.top, greaterThanOrEqualTo(0));
    },
  );

  testWidgets(
    'an oversized menu is capped to the roomier side instead of covering '
    'the trigger',
    (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final controller = TpPopoverController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        bottomTriggerPopover(
          controller: controller,
          capHeightToAnchorSide: true,
          panel: SingleChildScrollView(
            key: const Key('panel'),
            child: const SizedBox(width: 200, height: 2000),
          ),
        ),
      );
      controller.show();
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      final anchor = tester.getRect(find.byKey(const Key('anchor')));
      final panel = tester.getRect(find.byKey(const Key('panel')));
      expect(panel.height, lessThan(2000));
      expect(panel.bottom, lessThanOrEqualTo(anchor.top));
      expect(panel.top, greaterThanOrEqualTo(0));
    },
  );
}
