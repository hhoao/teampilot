import 'package:ai_message_core/ai_message_core.dart';
import 'package:ai_message_ui/ai_message_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';

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

const _singleQuestion = AiAskUserQuestion(
  question: 'Pick color?',
  header: 'Color',
  options: [
    AiAskUserOption(label: 'Red'),
    AiAskUserOption(label: 'Blue'),
  ],
);

const _multiQuestions = [
  AiAskUserQuestion(
    question: 'Pick color?',
    header: 'Color',
    options: [
      AiAskUserOption(label: 'Red'),
      AiAskUserOption(label: 'Blue'),
    ],
  ),
  AiAskUserQuestion(
    question: 'Pick size?',
    header: 'Size',
    options: [
      AiAskUserOption(label: 'S'),
      AiAskUserOption(label: 'L'),
    ],
  ),
];

void main() {
  testWidgets('select option + submit sends answers', (tester) async {
    final submissions = <AiAskUserSubmission>[];
    await tester.pumpWidget(
      _host(
        AiAskUserQuestionCard(
          questions: const [_singleQuestion],
          onSubmit: (submission) async {
            submissions.add(submission);
            return const AiInteractiveOk();
          },
          onCancel: () async => const AiInteractiveOk(),
          onAnswerInTerminal: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(AiAskUserQuestionCard.cardKey), findsOneWidget);
    expect(find.text('Pick color?'), findsOneWidget);
    expect(find.text('Enter your answer…'), findsOneWidget);

    final continueBtn = find.byKey(AiAskUserQuestionCard.continueButtonKey);
    expect(continueBtn, findsOneWidget);
    expect(tester.widget<TpButton>(continueBtn).onPressed, isNull);

    await tester.tap(
      find.byKey(
        AiAskUserQuestionCard.optionKey(questionIndex: 0, optionIndex: 1),
      ),
    );
    await tester.pumpAndSettle();

    final submit = find.byKey(AiAskUserQuestionCard.submitButtonKey);
    expect(submit, findsOneWidget);
    expect(tester.widget<TpButton>(submit).onPressed, isNotNull);

    await tester.tap(submit);
    await tester.pumpAndSettle();

    expect(submissions, hasLength(1));
    expect(submissions.single.answers, [
      ['Blue'],
    ]);
    expect(submissions.single.optionIndices, [1]);
  });

  testWidgets('custom answer submits free text', (tester) async {
    final submissions = <AiAskUserSubmission>[];
    await tester.pumpWidget(
      _host(
        AiAskUserQuestionCard(
          questions: const [_singleQuestion],
          onSubmit: (submission) async {
            submissions.add(submission);
            return const AiInteractiveOk();
          },
          onCancel: () async => const AiInteractiveOk(),
          onAnswerInTerminal: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(
        AiAskUserQuestionCard.optionKey(questionIndex: 0, optionIndex: 2),
      ),
      'Custom purple',
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(AiAskUserQuestionCard.submitButtonKey));
    await tester.pumpAndSettle();

    expect(submissions, hasLength(1));
    expect(submissions.single.answers, [
      ['Custom purple'],
    ]);
    expect(submissions.single.freeText, 'Custom purple');
  });

  testWidgets('multi-question pager + submit all answers', (tester) async {
    final submissions = <AiAskUserSubmission>[];
    await tester.pumpWidget(
      _host(
        AiAskUserQuestionCard(
          questions: _multiQuestions,
          onSubmit: (submission) async {
            submissions.add(submission);
            return const AiInteractiveOk();
          },
          onCancel: () async => const AiInteractiveOk(),
          onAnswerInTerminal: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('1 / 2'), findsOneWidget);
    expect(find.text('Pick color?'), findsOneWidget);
    expect(find.text('Pick size?'), findsNothing);

    await tester.tap(
      find.byKey(
        AiAskUserQuestionCard.optionKey(questionIndex: 0, optionIndex: 0),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('2 / 2'), findsOneWidget);
    expect(find.text('Pick size?'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
    expect(
      tester
          .widget<TpButton>(find.byKey(AiAskUserQuestionCard.continueButtonKey))
          .onPressed,
      isNotNull,
    );

    await tester.tap(
      find.byKey(
        AiAskUserQuestionCard.optionKey(questionIndex: 1, optionIndex: 1),
      ),
    );
    await tester.pumpAndSettle();

    final submit = find.byKey(AiAskUserQuestionCard.submitButtonKey);
    expect(submit, findsOneWidget);
    expect(tester.widget<TpButton>(submit).onPressed, isNotNull);
    expect(tester.widget<TpButton>(submit).variant, TpButtonVariant.primary);

    await tester.tap(submit);
    await tester.pumpAndSettle();

    expect(submissions.single.answers, [
      ['Red'],
      ['L'],
    ]);
    expect(submissions.single.optionIndices, [0, 1]);
  });

  testWidgets('answered page shows Continue back to incomplete', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        AiAskUserQuestionCard(
          questions: _multiQuestions,
          onSubmit: (_) async => const AiInteractiveOk(),
          onCancel: () async => const AiInteractiveOk(),
          onAnswerInTerminal: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(
        AiAskUserQuestionCard.optionKey(questionIndex: 0, optionIndex: 0),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('2 / 2'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.chevron_left_rounded));
    await tester.pumpAndSettle();
    expect(find.text('1 / 2'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);

    final continueBtn = find.byKey(AiAskUserQuestionCard.continueButtonKey);
    expect(tester.widget<TpButton>(continueBtn).onPressed, isNotNull);

    await tester.tap(continueBtn);
    await tester.pumpAndSettle();
    expect(find.text('2 / 2'), findsOneWidget);
    expect(find.text('Pick size?'), findsOneWidget);
  });

  testWidgets('Ignore cancels ask', (tester) async {
    var cancelled = 0;
    await tester.pumpWidget(
      _host(
        AiAskUserQuestionCard(
          questions: const [_singleQuestion],
          onSubmit: (_) async => const AiInteractiveOk(),
          onCancel: () async {
            cancelled += 1;
            return const AiInteractiveOk();
          },
          onAnswerInTerminal: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Ignore'));
    await tester.pumpAndSettle();

    expect(cancelled, 1);
  });

  testWidgets('failed answer shows inline error', (tester) async {
    await tester.pumpWidget(
      _host(
        AiAskUserQuestionCard(
          questions: const [_singleQuestion],
          onSubmit: (_) async =>
              const AiInteractiveFailed('terminal_disconnected'),
          onCancel: () async => const AiInteractiveOk(),
          onAnswerInTerminal: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(
        AiAskUserQuestionCard.optionKey(questionIndex: 0, optionIndex: 0),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(AiAskUserQuestionCard.submitButtonKey));
    await tester.pumpAndSettle();

    expect(find.byKey(AiAskUserQuestionCard.inlineErrorKey), findsOneWidget);
    expect(
      find.text(
        'Terminal is disconnected. Reconnect or answer in the Terminal.',
      ),
      findsOneWidget,
    );
  });
}
