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

  testWidgets('pumpUntilSettled reports a bounded timeout', (tester) async {
    await tester.pumpWidget(const _AlwaysAnimating());

    TestFailure? failure;
    try {
      await pumpUntilSettled(
        tester,
        timeout: const Duration(milliseconds: 32),
        step: const Duration(milliseconds: 16),
      );
    } on TestFailure catch (error) {
      failure = error;
    }

    expect(failure?.message, contains('widget tree to settle'));
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

class _AlwaysAnimating extends StatefulWidget {
  const _AlwaysAnimating();

  @override
  State<_AlwaysAnimating> createState() => _AlwaysAnimatingState();
}

class _AlwaysAnimatingState extends State<_AlwaysAnimating> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPersistentFrameCallback((_) {
      if (mounted) WidgetsBinding.instance.scheduleFrame();
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
