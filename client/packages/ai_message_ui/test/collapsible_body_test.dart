import 'package:ai_message_ui/ai_message_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget wrap(bool open, {required Widget child}) {
    return MaterialApp(
      home: Scaffold(
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [AiCollapsibleBody(open: open, child: child)],
        ),
      ),
    );
  }

  testWidgets('collapsed body is unmounted and holds no ticker', (tester) async {
    var builds = 0;
    await tester.pumpWidget(
      wrap(
        false,
        child: Builder(
          builder: (_) {
            builds++;
            return const SizedBox(height: 120);
          },
        ),
      ),
    );

    expect(builds, 0);
    expect(tester.getSize(find.byType(AiCollapsibleBody)).height, 0);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('opening animates height without rebuilding the child', (
    tester,
  ) async {
    var builds = 0;
    Widget child() => Builder(
      builder: (_) {
        builds++;
        return const SizedBox(height: 120);
      },
    );

    await tester.pumpWidget(wrap(false, child: child()));
    await tester.pumpWidget(wrap(true, child: child()));

    // Mid-animation: the clip grows, the child subtree is laid out once.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final midHeight = tester.getSize(find.byType(AiCollapsibleBody)).height;
    expect(midHeight, greaterThan(0));
    expect(midHeight, lessThan(120));
    expect(builds, 1);

    await tester.pump(const Duration(milliseconds: 150));
    expect(tester.getSize(find.byType(AiCollapsibleBody)).height, 120);
    expect(builds, 1);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('closing keeps the body only for the animation window', (
    tester,
  ) async {
    Widget child() => const SizedBox(height: 120);

    await tester.pumpWidget(wrap(true, child: child()));
    expect(tester.getSize(find.byType(AiCollapsibleBody)).height, 120);

    await tester.pumpWidget(wrap(false, child: child()));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(SizedBox), findsWidgets);

    await tester.pump(const Duration(milliseconds: 150));
    expect(tester.getSize(find.byType(AiCollapsibleBody)).height, 0);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('content growth while open does not start an animation', (
    tester,
  ) async {
    Widget child(double height) => SizedBox(height: height);

    await tester.pumpWidget(wrap(true, child: child(100)));
    expect(tester.getSize(find.byType(AiCollapsibleBody)).height, 100);

    // Streaming content: the wrapper follows the new height immediately.
    await tester.pumpWidget(wrap(true, child: child(240)));
    await tester.pump();
    expect(tester.getSize(find.byType(AiCollapsibleBody)).height, 240);
    expect(tester.binding.transientCallbackCount, 0);
  });
}
