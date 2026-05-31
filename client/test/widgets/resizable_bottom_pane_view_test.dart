import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/widgets/resizable_split_view.dart';

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
              return ResizableSplitView(
                axis: Axis.vertical,
                primaryAtEnd: true,
                first: const Placeholder(),
                second: const Placeholder(),
                initialPrimarySize: height,
                minPrimarySize: 120,
                minSecondarySize: 120,
                maxPrimarySize: 480,
                onPrimarySizeChanged: (next) {
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

    final divider = find.byKey(const Key('resizable-split-divider'));
    expect(divider, findsOneWidget);

    await tester.drag(divider, const Offset(0, -40));
    await tester.pumpAndSettle();

    expect(lastReported, 240.0);
  });
}
