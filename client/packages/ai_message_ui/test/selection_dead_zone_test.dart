import 'package:ai_message_ui/ai_message_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'SelectionDeadZone absorbs long-press drag in SelectionArea+Scrollable gap',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SelectionArea(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    const Text('AAA BBB CCC DDD EEE FFF'),
                    const SelectionDeadZone(
                      child: SizedBox(
                        key: Key('gap'),
                        height: 80,
                        width: double.infinity,
                      ),
                    ),
                    const Text('GGG HHH III JJJ KKK LLL'),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final gap = tester.getCenter(find.byKey(const Key('gap')));
      final gesture = await tester.startGesture(gap);
      await tester.pump(const Duration(seconds: 1));
      await gesture.moveBy(const Offset(0, 50));
      await tester.pump();
      await gesture.up();
      await tester.pump();
    },
  );
}
