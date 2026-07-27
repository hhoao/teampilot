import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/selection_ai/selection_ask_ai_fab_host.dart';

void main() {
  testWidgets('FAB appears one frame after selection becomes active', (
    tester,
  ) async {
    final notifier = ValueNotifier(0);
    addTearDown(notifier.dispose);
    var active = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SelectionAskAiFabHost(
            listenable: notifier,
            selectionActive: () => active,
            readAiContext: () => active ? 'ctx' : '',
            onAskAi: (_) async {},
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.chat_outlined), findsNothing);
    active = true;
    notifier.value++;
    expect(find.byIcon(Icons.chat_outlined), findsNothing);
    await tester.pump();
    await tester.pump();
    expect(find.byIcon(Icons.chat_outlined), findsOneWidget);
  });

  testWidgets('FAB passes the latest AI context when tapped', (tester) async {
    final notifier = ValueNotifier(0);
    addTearDown(notifier.dispose);
    var aiContext = 'first';
    String? received;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SelectionAskAiFabHost(
            listenable: notifier,
            selectionActive: () => true,
            readAiContext: () => aiContext,
            onAskAi: (value) async => received = value,
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    aiContext = 'latest';
    await tester.tap(find.byIcon(Icons.chat_outlined));
    await tester.pump();
    expect(received, 'latest');
  });

  testWidgets('FAB stays hidden for empty context or an open menu', (
    tester,
  ) async {
    final notifier = ValueNotifier(0);
    addTearDown(notifier.dispose);
    var aiContext = '   ';

    Widget buildHost({required bool menuOpen}) {
      return MaterialApp(
        home: Scaffold(
          body: SelectionAskAiFabHost(
            listenable: notifier,
            selectionActive: () => true,
            readAiContext: () => aiContext,
            onAskAi: (_) async {},
            menuOpen: menuOpen,
            child: const SizedBox.expand(),
          ),
        ),
      );
    }

    await tester.pumpWidget(buildHost(menuOpen: false));
    await tester.pump();
    await tester.pump();
    expect(find.byIcon(Icons.chat_outlined), findsNothing);

    aiContext = 'ctx';
    await tester.pumpWidget(buildHost(menuOpen: true));
    await tester.pump();
    await tester.pump();
    expect(find.byIcon(Icons.chat_outlined), findsNothing);
  });
}
