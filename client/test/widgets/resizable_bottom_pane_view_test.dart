import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/widgets/split_layout.dart';

void main() {
  testWidgets('reports bottom height when divider drag ends', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    var height = 200.0;
    double? lastReported;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return TwoPaneSplitView(
                axis: Axis.vertical,
                fixedChildIndex: 1,
                first: const Placeholder(),
                second: const Placeholder(),
                size: height,
                minSize: 120,
                maxSize: 480,
                onSizeChanged: (next) {
                  lastReported = next;
                  setState(() => height = next);
                },
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final divider = find.byType(DividerWidget);
    expect(divider, findsOneWidget);

    await tester.drag(divider, const Offset(0, -40));
    await tester.pumpAndSettle();

    expect(lastReported, 240.0);
  });
}
