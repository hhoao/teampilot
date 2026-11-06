import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/pages/chat_workbench.dart';

class _Registry extends ChangeNotifier {
  void bump() => notifyListeners();
}

void main() {
  // A rewind edit stops and relaunches the seat, so the pod is briefly null
  // (or replaced). The body root must stay the same widget type across that
  // flip; otherwise Flutter tears down the whole chat subtree and remounts the
  // message thread — the visible double flash on edit submit.
  testWidgets('pod null/non-null flip keeps the subtree element mounted', (
    tester,
  ) async {
    final registry = _Registry();
    final notifier = ValueNotifier<int>(0);
    final relaunched = ValueNotifier<int>(1);
    addTearDown(registry.dispose);
    addTearDown(notifier.dispose);
    addTearDown(relaunched.dispose);
    Listenable? pod = notifier;

    Future<void> pump() => tester.pumpWidget(
      MaterialApp(
        home: wrapPodDependentBody(
          podRegistry: registry,
          resolvePod: () => pod,
          builder: (context, _) => const _StatefulChild(),
        ),
      ),
    );

    await pump();
    final firstState = tester.state<State<_StatefulChild>>(
      find.byType(_StatefulChild),
    );

    // Reconnect start: pod dropped.
    pod = null;
    registry.bump();
    await tester.pump();
    expect(
      tester.state<State<_StatefulChild>>(find.byType(_StatefulChild)),
      same(firstState),
      reason: 'dropping the pod must not remount the chat subtree',
    );

    // Reconnect end: pod back (a fresh instance, as the runtime is relaunched).
    pod = relaunched;
    registry.bump();
    await tester.pump();
    expect(
      tester.state<State<_StatefulChild>>(find.byType(_StatefulChild)),
      same(firstState),
      reason: 'recreating the pod must not remount the chat subtree',
    );
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
