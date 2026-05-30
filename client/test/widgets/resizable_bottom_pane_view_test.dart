import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/widgets/split_layout.dart';

void main() {
  testWidgets('dragging divider down increases reported bottom height', (
    tester,
  ) async {
    var height = 200.0;
    double? lastReported;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return ResizableBottomPaneView(
                top: const Placeholder(),
                bottom: const Placeholder(),
                bottomHeight: height,
                minBottomHeight: 120,
                maxBottomHeight: 480,
                onBottomHeightChanged: (next) {
                  lastReported = next;
                  setState(() => height = next);
                },
              );
            },
          ),
        ),
      ),
    );

    await tester.drag(find.byType(MultiSplitView), const Offset(0, 40));
    await tester.pump();

    expect(lastReported, 240.0);
  });
}
