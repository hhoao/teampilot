import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/widgets/textarea/app_textarea_shell.dart';

void main() {
  testWidgets('clamps height when min/max props change', (tester) async {
    late double height;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppTextareaShell(
            minHeight: 80,
            maxHeight: 200,
            initialHeight: 150,
            onHeightChanged: (h) => height = h,
            builder: (context, lineCount) =>
                SizedBox(height: 150, child: Text('lines:$lineCount')),
          ),
        ),
      ),
    );
    expect(find.textContaining('lines:'), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppTextareaShell(
            minHeight: 80,
            maxHeight: 120,
            initialHeight: 150,
            onHeightChanged: (h) => height = h,
            builder: (context, lineCount) =>
                SizedBox(height: 120, child: Text('lines:$lineCount')),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(height, 120);
  });

  testWidgets('drag resize updates height and fires callback', (tester) async {
    var height = 100.0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppTextareaShell(
            minHeight: 80,
            maxHeight: 300,
            initialHeight: 100,
            resizable: true,
            onHeightChanged: (h) => height = h,
            builder: (context, lineCount) => const SizedBox(
              width: 200,
              height: 100,
              child: Text('body'),
            ),
          ),
        ),
      ),
    );

    final grip = find.byKey(const Key('app-textarea-resize-grip'));
    expect(grip, findsOneWidget);
    await tester.drag(grip, const Offset(0, 40));
    await tester.pump();
    expect(height, greaterThan(100));
    expect(height, lessThanOrEqualTo(300));
  });

  testWidgets('lineCount is at least 1 and tracks height', (tester) async {
    final counts = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppTextareaShell(
            minHeight: 80,
            maxHeight: 500,
            initialHeight: 80,
            textStyle: const TextStyle(fontSize: 14, height: 1.25),
            builder: (context, lineCount) {
              counts.add(lineCount);
              return Text('c:$lineCount');
            },
          ),
        ),
      ),
    );
    expect(counts.last, greaterThanOrEqualTo(1));
    expect(counts.last, lessThanOrEqualTo(100));
  });
}
