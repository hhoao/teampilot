import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/widgets/pane_entry_animation.dart';

void main() {
  testWidgets('PaneEntryAnimation renders child', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PaneEntryAnimation(
            child: Text('pane'),
          ),
        ),
      ),
    );

    expect(find.text('pane'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 220));
    expect(find.text('pane'), findsOneWidget);
  });
}
