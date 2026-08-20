import 'package:ai_message_core/ai_message_core.dart';
import 'package:ai_message_ui/ai_message_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/pages/chat/ask_user_question_bubble.dart';
import 'package:teampilot/theme/app_typography_scale.dart';
import 'package:teampilot/utils/ui/app_keys.dart';

Widget _host(Widget child) {
  final theme = ThemeData(
    useMaterial3: true,
    extensions: [AiMessageTheme.test()],
  );
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
    theme: theme,
    home: TpTheme(
      data: TpThemeData.fromColorScheme(
        theme.colorScheme,
        scale: 1.0,
        controlScale: AppTypographyScale.standard.multiplier,
      ),
      child: Scaffold(body: child),
    ),
  );
}

AiToolCallPart _answeredPart() => const AiToolCallPart(
  toolCallId: 'q',
  toolName: 'AskUserQuestion',
  args: {
    'questions': [
      {
        'question': 'How is the weather today?',
        'options': ['Sunny', 'Rainy'],
      },
      {
        'question': 'What drinks do you like?',
        'options': ['Coffee', 'Tea', 'Water'],
        'multiSelect': true,
      },
      {
        'question': 'How does this feel?',
        'options': ['Okay', 'Great'],
      },
    ],
  },
  result: {
    'answers': {
      'How is the weather today?': 'Sunny',
      'What drinks do you like?': 'Coffee, Tea',
      'How does this feel?': 'Okay',
    },
  },
  status: AiToolCallStatus.complete,
);

void main() {
  group('AskUserQuestionBubble', () {
    testWidgets('stays collapsed and shows asked-count header', (tester) async {
      await tester.pumpWidget(
        _host(AskUserQuestionBubble(part: _answeredPart())),
      );
      expect(find.byKey(AppKeys.askUserQuestionBubble), findsOneWidget);
      expect(find.text('Asked 3 questions'), findsOneWidget);
      expect(find.text('How is the weather today?'), findsNothing);
      expect(find.text('Sunny'), findsNothing);
    });

    testWidgets('expands to question over answer pairs', (tester) async {
      await tester.pumpWidget(
        _host(AskUserQuestionBubble(part: _answeredPart())),
      );
      await tester.tap(find.byKey(AppKeys.askUserQuestionBubbleHeader));
      await tester.pump();
      expect(find.text('How is the weather today?'), findsOneWidget);
      expect(find.text('Sunny'), findsOneWidget);
      expect(find.text('What drinks do you like?'), findsOneWidget);
      expect(find.text('Coffee, Tea'), findsOneWidget);
      expect(find.text('How does this feel?'), findsOneWidget);
      expect(find.text('Okay'), findsOneWidget);
    });

    testWidgets('incomplete tool shows asking header and Unanswered', (
      tester,
    ) async {
      const part = AiToolCallPart(
        toolCallId: 'q',
        toolName: 'AskUserQuestion',
        args: {
          'questions': [
            {
              'question': 'How is the weather today?',
              'options': ['Sunny', 'Rainy'],
            },
          ],
        },
        status: AiToolCallStatus.incomplete,
      );
      await tester.pumpWidget(_host(AskUserQuestionBubble(part: part)));
      expect(find.text('Asking questions'), findsOneWidget);
      await tester.tap(find.byKey(AppKeys.askUserQuestionBubbleHeader));
      await tester.pump();
      expect(find.text('How is the weather today?'), findsOneWidget);
      expect(find.text('Unanswered'), findsOneWidget);
    });
  });

  group('cliAskUserBubbleBuilders', () {
    test('registers askUser tool names', () {
      expect(
        cliAskUserBubbleBuilders().keys,
        containsAll([
          'askuserquestion',
          'ask_user_question',
          'ask_user',
          'askquestion',
          'question',
        ]),
      );
    });

    testWidgets('returns null when questions cannot be parsed', (tester) async {
      const part = AiToolCallPart(
        toolCallId: 'q',
        toolName: 'AskUserQuestion',
        args: {'foo': 'bar'},
        status: AiToolCallStatus.complete,
      );
      final builder = cliAskUserBubbleBuilders()['askuserquestion']!;
      await tester.pumpWidget(
        _host(
          Builder(
            builder: (context) {
              final built = builder(context, part);
              return built ?? const Text('FALLTHROUGH');
            },
          ),
        ),
      );
      expect(find.text('FALLTHROUGH'), findsOneWidget);
      expect(find.byKey(AppKeys.askUserQuestionBubble), findsNothing);
    });
  });
}
