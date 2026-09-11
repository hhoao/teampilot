import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/widgets/ui_zoom.dart';

/// Regression for floating-tab drag jumping to the pointer's top-left on
/// Windows (UiZoom `1/dpr` wraps Overlay in [Transform.scale]). Requires
/// `tool/flutter_patches/reorderable_overlay_transform.patch`.
void main() {
  testWidgets(
    'reorder overlay proxy stays under the pointer when UiZoom scales the overlay',
    (tester) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          // Production wraps the Navigator/Overlay with UiZoom (see main.dart).
          builder: (context, child) => UiZoom(
            scale: 0.5,
            child: child ?? const SizedBox.shrink(),
          ),
          home: const Scaffold(body: _HorizontalReorderStrip()),
        ),
      );

      final tab = find.text('Tab 0');
      final origin = tester.getTopLeft(tab);
      final grab = tester.getCenter(tab);

      final gesture = await tester.startGesture(grab);
      await gesture.moveBy(const Offset(40, 0));
      await tester.pump();

      final dragged = tester.getTopLeft(tab);
      expect(
        dragged.dx,
        closeTo(origin.dx + 40, 1),
        reason:
            'proxy must track the pointer; a jump toward the cursor top-left '
            'means overlay Positioned mixed global coords with Transform.scale',
      );
      expect(dragged.dy, closeTo(origin.dy, 1));

      await gesture.up();
    },
  );
}

class _HorizontalReorderStrip extends StatelessWidget {
  const _HorizontalReorderStrip();

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      scrollDirection: Axis.horizontal,
      slivers: [
        SliverReorderableList(
          itemCount: 3,
          onReorderItem: (oldIndex, newIndex) {},
          itemBuilder: (context, index) {
            return ReorderableDragStartListener(
              key: ValueKey(index),
              index: index,
              child: SizedBox(
                width: 120,
                height: 40,
                child: Text('Tab $index'),
              ),
            );
          },
        ),
      ],
    );
  }
}
