import 'package:ai_message_core/ai_message_core.dart';
import 'package:ai_message_ui/ai_message_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child) {
  final theme = ThemeData(
    useMaterial3: true,
    extensions: [AiMessageTheme.test()],
  );
  return MaterialApp(
    theme: theme,
    home: Scaffold(body: child),
  );
}

void main() {
  testWidgets('stays collapsed and shows asked-count header', (tester) async {
    await tester.pumpWidget(
      _host(
        const AiAskUserQuestionBubble(
          target: AiAskUserTarget(
            asking: false,
            items: [
              AiAskUserItem(
                question: 'How is the weather today?',
                answer: 'Sunny',
              ),
              AiAskUserItem(
                question: 'What drinks do you like?',
                answer: 'Coffee, Tea',
              ),
              AiAskUserItem(question: 'How does this feel?', answer: 'Okay'),
            ],
          ),
        ),
      ),
    );
    expect(find.byKey(AiAskUserQuestionBubble.bubbleKey), findsOneWidget);
    expect(find.text('Asked 3 questions'), findsOneWidget);
    expect(find.text('How is the weather today?'), findsNothing);
  });

  testWidgets('expands to question over answer pairs', (tester) async {
    await tester.pumpWidget(
      _host(
        const AiAskUserQuestionBubble(
          target: AiAskUserTarget(
            asking: false,
            items: [
              AiAskUserItem(
                question: 'How is the weather today?',
                answer: 'Sunny',
              ),
              AiAskUserItem(
                question: 'What drinks do you like?',
                answer: 'Coffee, Tea',
              ),
              AiAskUserItem(question: 'How does this feel?', answer: null),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(AiAskUserQuestionBubble.headerKey));
    await tester.pump();
    expect(find.text('How is the weather today?'), findsOneWidget);
    expect(find.text('Sunny'), findsOneWidget);
    expect(find.text('Unanswered'), findsOneWidget);
  });

  testWidgets('asking state uses asking header', (tester) async {
    await tester.pumpWidget(
      _host(
        const AiAskUserQuestionBubble(
          target: AiAskUserTarget(
            asking: true,
            items: [AiAskUserItem(question: 'Q?', answer: null)],
          ),
        ),
      ),
    );
    expect(find.text('Asking questions'), findsOneWidget);
  });
}
