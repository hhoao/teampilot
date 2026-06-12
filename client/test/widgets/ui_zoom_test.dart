import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/widgets/ui_zoom.dart';

void main() {
  testWidgets('scale 1.0 is a pass-through (MediaQuery size unchanged)', (
    tester,
  ) async {
    late Size seen;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(800, 600)),
        child: UiZoom(
          scale: 1.0,
          child: Builder(
            builder: (context) {
              seen = MediaQuery.sizeOf(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
    expect(seen, const Size(800, 600));
  });

  testWidgets('scale 0.5 doubles the logical canvas the child lays out into', (
    tester,
  ) async {
    late Size seen;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(800, 600)),
        child: UiZoom(
          scale: 0.5,
          child: Builder(
            builder: (context) {
              seen = MediaQuery.sizeOf(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
    expect(seen, const Size(1600, 1200));
  });

  testWidgets('a full-canvas child is laid out at the rescaled size', (
    tester,
  ) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(800, 600)),
        child: UiZoom(
          scale: 0.5,
          child: const SizedBox.expand(key: Key('fill')),
        ),
      ),
    );
    final box = tester.renderObject<RenderBox>(find.byKey(const Key('fill')));
    expect(box.size, const Size(1600, 1200));
  });

  testWidgets(
    'pointer events hit-test across the full window, including the right edge '
    '(regression: scale<1 right/bottom dead-zone)',
    (tester) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      var tappedRight = false;
      await tester.pumpWidget(
        MaterialApp(
          home: UiZoom(
            scale: 0.5,
            child: Align(
              alignment: Alignment.topRight,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => tappedRight = true,
                child: const SizedBox(width: 40, height: 40),
              ),
            ),
          ),
        ),
      );

      // The button sits at the top-right of the 1600x1200 scaled canvas; after
      // the 0.5 transform it paints at the right edge of the 800-wide viewport.
      // Before the OverflowBox/Transform reorder this tap landed in a dead zone.
      await tester.tapAt(const Offset(790, 10));
      await tester.pump();
      expect(tappedRight, isTrue);
    },
  );
}
