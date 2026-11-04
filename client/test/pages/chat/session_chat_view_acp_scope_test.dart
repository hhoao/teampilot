import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/pages/chat/session_chat_view.dart';

void main() {
  // Editing a user message rewinds and relaunches the seat. That flips
  // tab.acpRuntime through null (discard) and back to a fresh cubit (attach).
  // The provider root must keep the same widget type across those flips or
  // Flutter remounts the entire chat subtree (message thread, scroll offset,
  // cached bodies) — the visible double flash. The idle cubit is a shared
  // non-null stand-in; before the fix the root alternated between a bare
  // child and a BlocProvider, which this test catches as a State change.
  testWidgets('runtime null/non-null flips keep the subtree State mounted', (
    tester,
  ) async {
    Widget build(bool hasRuntime) => MaterialApp(
      home: acpRuntimeScope(
        runtime: hasRuntime ? idleAcpRuntimeCubit : null,
        child: const _StatefulChild(),
      ),
    );

    await tester.pumpWidget(build(true));
    final firstState = tester.state<State<_StatefulChild>>(
      find.byType(_StatefulChild),
    );

    // Reconnect start: runtime discarded to null.
    await tester.pumpWidget(build(false));
    expect(
      tester.state<State<_StatefulChild>>(find.byType(_StatefulChild)),
      same(firstState),
      reason: 'dropping the ACP runtime must not remount the chat subtree',
    );

    // Reconnect end: a fresh runtime is attached.
    await tester.pumpWidget(build(true));
    expect(
      tester.state<State<_StatefulChild>>(find.byType(_StatefulChild)),
      same(firstState),
      reason: 'recreating the ACP runtime must not remount the chat subtree',
    );

    // A second edit repeats the flip.
    await tester.pumpWidget(build(false));
    await tester.pumpWidget(build(true));
    expect(
      tester.state<State<_StatefulChild>>(find.byType(_StatefulChild)),
      same(firstState),
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
