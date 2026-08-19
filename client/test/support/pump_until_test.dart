import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'post_frame_test_harness.dart';

void main() {
  testWidgets('pumpUntil reports a bounded timeout', (tester) async {
    await tester.pumpWidget(const SizedBox.shrink());

    TestFailure? failure;
    try {
      await pumpUntil(
        tester,
        () => false,
        description: 'the never-rendered marker',
        timeout: const Duration(milliseconds: 32),
        step: const Duration(milliseconds: 16),
      );
    } on TestFailure catch (error) {
      failure = error;
    }
    expect(failure?.message, contains('the never-rendered marker'));
  });
}
