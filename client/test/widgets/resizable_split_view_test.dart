import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/widgets/resizable_split_view.dart';

void main() {
  testWidgets('respects minSecondarySize when dragging primary', (tester) async {
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
}
