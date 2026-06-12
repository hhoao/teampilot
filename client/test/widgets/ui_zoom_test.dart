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
}
