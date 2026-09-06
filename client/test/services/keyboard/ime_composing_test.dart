import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/keyboard/ime_composing.dart';

void main() {
  testWidgets(
    'active only while the focused field has a non-empty composing range',
    (tester) async {
      final controller = TextEditingController(text: 'nihao');
      final focusNode = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TextField(controller: controller, focusNode: focusNode),
          ),
        ),
      );
      focusNode.requestFocus();
      await tester.pump();

      // No composition yet.
      expect(imeCompositionActive(), isFalse);

      // IME marks the region being composed (candidate window up).
      controller.value = controller.value.copyWith(
        composing: const TextRange(start: 0, end: 5),
      );
      expect(imeCompositionActive(), isTrue);

      // Composition committed / cancelled — range resets to empty.
      controller.value = controller.value.copyWith(
        composing: TextRange.empty,
      );
      expect(imeCompositionActive(), isFalse);
    },
  );

  testWidgets('false when no editable text holds focus', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SizedBox())),
    );
    expect(FocusManager.instance.primaryFocus, isNotNull);
    expect(imeCompositionActive(), isFalse);
  });
}
