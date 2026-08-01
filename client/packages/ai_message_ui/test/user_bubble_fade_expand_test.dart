import 'package:ai_message_core/ai_message_core.dart';
import 'package:ai_message_ui/ai_message_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

String _lines(int n) => List.generate(n, (i) => 'line-$i').join('\n');

void main() {
  testWidgets('short user bubble has no expand_more', (tester) async {
    await tester.pumpWidget(_app(AiMessage(
      id: 'u1',
      role: AiRole.user,
      parts: const [AiTextPart(text: 'hi')],
    )));
    await tester.pump();
    expect(find.byIcon(Icons.expand_more), findsNothing);
  });

  testWidgets('tall user bubble expands and collapses via chevron', (tester) async {
    await tester.pumpWidget(_app(AiMessage(
      id: 'u1',
      role: AiRole.user,
      parts: [AiTextPart(text: _lines(40))],
    )));
    await tester.pump();
    expect(find.byKey(const ValueKey('ai-fade-expand-chevron')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('ai-fade-expand-chevron')));
    await tester.pump();
    expect(find.byIcon(Icons.expand_less), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('ai-fade-expand-chevron')));
    await tester.pump();
    expect(find.byIcon(Icons.expand_more), findsOneWidget);
  });

  testWidgets('narrow thread width does not throw when action bar shown',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 60,
            child: AiMessageView(
              message: const AiMessage(
                id: 'u1',
                role: AiRole.user,
                parts: [AiTextPart(text: 'hi')],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('hi'), findsOneWidget);
  });

  testWidgets('message text change resets to collapsed', (tester) async {
    final msg1 = AiMessage(
      id: 'u1',
      role: AiRole.user,
      parts: [AiTextPart(text: _lines(40))],
    );
    await tester.pumpWidget(_app(msg1));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('ai-fade-expand-chevron')));
    await tester.pump();
    expect(find.byIcon(Icons.expand_less), findsOneWidget);

    final msg2 = AiMessage(
      id: 'u1',
      role: AiRole.user,
      parts: [AiTextPart(text: '${_lines(40)}\nextra')],
    );
    await tester.pumpWidget(_app(msg2));
    await tester.pump();
    expect(find.byIcon(Icons.expand_more), findsOneWidget);
  });
}

Widget _app(AiMessage message) => MaterialApp(
  home: Scaffold(body: AiMessageView(message: message)),
);
