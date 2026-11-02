import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/pages/chat_workbench.dart';

class _Counter extends StatefulWidget {
  const _Counter();

  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  var _count = 0;

  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: () => setState(() => _count++),
    child: Text('count: $_count'),
  );
}

void main() {
  testWidgets('the pod appearing later keeps the workbench body mounted', (
    tester,
  ) async {
    final pod = ValueNotifier<int>(0);
    addTearDown(pod.dispose);
    var rendered = 0;

    Widget harness(Listenable? listenable) => MaterialApp(
      home: wrapPodDependentBody(
        pod: listenable,
        builder: (context) {
          rendered++;
          return const _Counter();
        },
      ),
    );

    await tester.pumpWidget(harness(null));
    await tester.tap(find.byType(TextButton));
    await tester.pump();
    expect(find.text('count: 1'), findsOneWidget);

    // First connect creates the pod. The wrapper kind must not change, or the
    // whole subtree (chat thread, compose, scroll) is remounted.
    await tester.pumpWidget(harness(pod));
    expect(find.text('count: 1'), findsOneWidget);

    // Pod notifications still drive the body.
    final before = rendered;
    pod.value++;
    await tester.pump();
    expect(rendered, greaterThan(before));
    expect(find.text('count: 1'), findsOneWidget);
  });
}
