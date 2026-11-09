import 'package:ai_message_core/ai_message_core.dart';
import 'package:ai_message_ui/ai_message_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final message = AiMessage(
    id: '1',
    role: AiRole.assistant,
    parts: const [AiTextPart(text: 'hello')],
  );

  Finder copyIcon() => find.byIcon(Icons.copy_rounded);

  testWidgets('timestamp renders before the copy icon', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AiMessageActionBar(
            message: message,
            timestampText: '11月6日 15:44',
          ),
        ),
      ),
    );
    expect(find.text('11月6日 15:44'), findsOneWidget);
    final tsLeft = tester.getTopLeft(find.text('11月6日 15:44')).dx;
    final copyLeft = tester.getTopLeft(copyIcon()).dx;
    expect(tsLeft, lessThan(copyLeft));
  });

  testWidgets('null timestamp renders no label', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: AiMessageActionBar(message: message)),
      ),
    );
    expect(find.text('11月6日 15:44'), findsNothing);
    expect(copyIcon(), findsOneWidget);
  });

  testWidgets('hover reveal keeps bar height stable with timestamp', (
    tester,
  ) async {
    Widget bar({required bool forceVisible}) {
      return MaterialApp(
        home: Scaffold(
          body: Center(
            child: AiMessageActionBar(
              message: message,
              reveal: AiActionBarReveal.hover,
              forceVisible: forceVisible,
              timestampText: '15:44',
            ),
          ),
        ),
      );
    }

    await tester.pumpWidget(bar(forceVisible: false));
    final hidden = tester.getSize(find.byType(AiMessageActionBar));
    // Unmounted phase: the label is not in the tree at all, only the
    // fixed-height placeholder.
    expect(find.text('15:44'), findsNothing);

    await tester.pumpWidget(bar(forceVisible: true));
    await tester.pump();
    final shown = tester.getSize(find.byType(AiMessageActionBar));
    expect(find.text('15:44'), findsOneWidget);
    expect(shown.height, equals(hidden.height));
  });

  testWidgets('timestamp alone mounts the bar for a copyless message', (
    tester,
  ) async {
    final empty = AiMessage(id: '2', role: AiRole.assistant, parts: const []);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AiMessageActionBar(message: empty, timestampText: '15:44'),
        ),
      ),
    );
    expect(find.text('15:44'), findsOneWidget);
  });
}
