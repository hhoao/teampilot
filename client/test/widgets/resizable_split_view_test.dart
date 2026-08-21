import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/widgets/resizable_split_view.dart';

void main() {
  testWidgets('zero-width parent does not throw while clamping primary size', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(40, 400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ResizableSplitView(
            first: SizedBox(key: Key('primary-pane')),
            second: SizedBox(key: Key('secondary-pane')),
            initialPrimarySize: 180,
            minPrimarySize: 120,
            minSecondarySize: 120,
            maxPrimarySize: 500,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('respects minSecondarySize when dragging primary', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(600, 400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ResizableSplitView(
            first: const SizedBox(key: Key('primary-pane')),
            second: const SizedBox(key: Key('secondary-pane')),
            initialPrimarySize: 400,
            minPrimarySize: 120,
            minSecondarySize: 240,
            maxPrimarySize: 500,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final divider = find.byKey(const Key('resizable-split-divider'));
    await tester.drag(divider, const Offset(200, 0));
    await tester.pumpAndSettle();

    // 600 - 1 divider - 240 min secondary = 359 max primary
    final primary = tester.getSize(find.byKey(const Key('primary-pane')));
    expect(primary.width, lessThanOrEqualTo(359));
    expect(primary.width, greaterThanOrEqualTo(120));
  });

  testWidgets('keeps absolute primary size when parent grows', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ResizableSplitView(
            first: const SizedBox(key: Key('primary-pane')),
            second: const SizedBox(key: Key('secondary-pane')),
            initialPrimarySize: 280,
            minPrimarySize: 120,
            minSecondarySize: 120,
            maxPrimarySize: double.infinity,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.getSize(find.byKey(const Key('primary-pane'))).width, 280);

    await tester.binding.setSurfaceSize(const Size(1200, 400));
    await tester.pumpAndSettle();

    expect(tester.getSize(find.byKey(const Key('primary-pane'))).width, 280);
  });

  testWidgets('drag end reports pixel size and survives parent grow', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    var primarySize = 280.0;
    double? lastReported;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return ResizableSplitView(
                first: const SizedBox(key: Key('primary-pane')),
                second: const SizedBox(key: Key('secondary-pane')),
                initialPrimarySize: primarySize,
                minPrimarySize: 120,
                minSecondarySize: 120,
                maxPrimarySize: double.infinity,
                onPrimarySizeChanged: (next) {
                  lastReported = next;
                  setState(() => primarySize = next);
                },
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final divider = find.byKey(const Key('resizable-split-divider'));
    await tester.drag(divider, const Offset(40, 0));
    await tester.pumpAndSettle();

    expect(lastReported, 320);
    expect(tester.getSize(find.byKey(const Key('primary-pane'))).width, 320);

    await tester.binding.setSurfaceSize(const Size(1200, 400));
    await tester.pumpAndSettle();

    expect(tester.getSize(find.byKey(const Key('primary-pane'))).width, 320);
  });

  testWidgets('initial fraction seeds once then stays absolute', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ResizableSplitView(
            first: const SizedBox(key: Key('primary-pane')),
            second: const SizedBox(key: Key('secondary-pane')),
            initialPrimarySize: 200,
            initialPrimaryFraction: 0.4,
            minPrimarySize: 120,
            minSecondarySize: 120,
            maxPrimarySize: double.infinity,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.getSize(find.byKey(const Key('primary-pane'))).width, 400);

    await tester.binding.setSurfaceSize(const Size(1500, 400));
    await tester.pumpAndSettle();

    expect(tester.getSize(find.byKey(const Key('primary-pane'))).width, 400);
  });

  testWidgets('restores preferred size after temporary clamp', (tester) async {
    // 500 available → max primary = 500 - 1 - 200 = 299
    await tester.binding.setSurfaceSize(const Size(500, 400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ResizableSplitView(
            first: const SizedBox(key: Key('primary-pane')),
            second: const SizedBox(key: Key('secondary-pane')),
            initialPrimarySize: 360,
            minPrimarySize: 120,
            minSecondarySize: 200,
            maxPrimarySize: double.infinity,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester.getSize(find.byKey(const Key('primary-pane'))).width,
      299,
    );

    await tester.binding.setSurfaceSize(const Size(1000, 400));
    await tester.pumpAndSettle();

    expect(tester.getSize(find.byKey(const Key('primary-pane'))).width, 360);
  });
}
