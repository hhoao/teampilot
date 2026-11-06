import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/pages/chat_workbench.dart';

class _Registry extends ChangeNotifier {
  void bump() => notifyListeners();
}

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
  testWidgets('a pod created after the first build reaches the body', (
    tester,
  ) async {
    final registry = _Registry();
    addTearDown(registry.dispose);
    Listenable? pod;
    var rendered = 0;
    var resolvedPods = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: wrapPodDependentBody(
          podRegistry: registry,
          resolvePod: () => pod,
          builder: (context, resolved) {
            rendered++;
            if (resolved != null) resolvedPods++;
            return const _Counter();
          },
        ),
      ),
    );
    await tester.tap(find.byType(TextButton));
    await tester.pump();
    expect(find.text('count: 1'), findsOneWidget);
    expect(resolvedPods, 0);

    // First connect creates the pod: the registry is the only signal (pod
    // state changes do not emit ChatState), so without it the body would keep
    // resolving null forever.
    final created = ValueNotifier<int>(0);
    addTearDown(created.dispose);
    pod = created;
    registry.bump();
    await tester.pump();
    expect(resolvedPods, 1);
    expect(
      find.text('count: 1'),
      findsOneWidget,
      reason: 'the wrapper must not remount the chat subtree',
    );

    // The body is bound to the new pod, not to the pre-creation listener.
    final before = rendered;
    created.value++;
    await tester.pump();
    expect(rendered, greaterThan(before));
    expect(find.text('count: 1'), findsOneWidget);
  });
}
