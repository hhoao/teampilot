import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/pages/chat_workbench.dart';

void main() {
  // A rewind edit stops and relaunches the seat, so the pod is briefly null
  // (or replaced). The body root must stay the same widget type across that
  // flip; otherwise Flutter tears down the whole chat subtree and remounts the
  // message thread — the visible double flash on edit submit.
  testWidgets('pod null/non-null flip keeps the subtree element mounted', (
    tester,
  ) async {
    final notifier = ValueNotifier<int>(0);

    Widget build(Listenable? pod) => MaterialApp(
      home: wrapPodDependentBody(
        pod: pod,
        builder: (context) => const _StatefulChild(),
      ),
    );

    await tester.pumpWidget(build(notifier));
    final firstState = tester.state<State<_StatefulChild>>(
      find.byType(_StatefulChild),
    );

    // Reconnect start: pod dropped.
    await tester.pumpWidget(build(null));
    expect(
      tester.state<State<_StatefulChild>>(find.byType(_StatefulChild)),
      same(firstState),
      reason: 'dropping the pod must not remount the chat subtree',
    );

    // Reconnect end: pod back (a fresh instance, as the runtime is relaunched).
    final relaunched = ValueNotifier<int>(1);
    await tester.pumpWidget(build(relaunched));
    expect(
      tester.state<State<_StatefulChild>>(find.byType(_StatefulChild)),
      same(firstState),
      reason: 'recreating the pod must not remount the chat subtree',
    );

    notifier.dispose();
    relaunched.dispose();
  });
}

class _StatefulChild extends StatefulWidget {
  const _StatefulChild();

  @override
  State<_StatefulChild> createState() => _StatefulChildState();
}

class _StatefulChildState extends State<_StatefulChild> {
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
