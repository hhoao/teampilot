import 'package:ai_message_core/ai_message_core.dart';
import 'package:ai_message_ui/ai_message_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/pages/chat/cli_task_bubbles.dart';
import 'package:teampilot/theme/app_typography_scale.dart';

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

void main() {
  testWidgets('TaskCreate bubble shows subject and pending pill', (tester) async {
    final part = AiToolCallPart(
      toolCallId: 'c',
      toolName: 'TaskCreate',
      args: const {
        'subject': 'T1: do a thing',
        'description': 'details',
        'activeForm': 'Doing it',
      },
      status: AiToolCallStatus.complete,
    );
    await tester.pumpWidget(_host(CliTaskCreateBubble(part: part)));
    // Header label + subject render as a rich Text — match with findRichText.
    expect(find.textContaining('TaskCreate', findRichText: true), findsOneWidget);
    expect(find.textContaining('T1: do a thing', findRichText: true), findsOneWidget);
    // The status pill is a plain Text.
    expect(find.text('Pending'), findsOneWidget);
    // Tapping the pill toggles the expanded detail.
    await tester.tap(find.text('Pending'));
    await tester.pump();
    expect(find.text('details'), findsOneWidget);
    expect(find.text('Doing it'), findsOneWidget);
  });

  testWidgets('TaskUpdate bubble shows task id and status transition',
      (tester) async {
    final part = AiToolCallPart(
      toolCallId: 'u',
      toolName: 'TaskUpdate',
      args: const {'taskId': '9', 'status': 'in_progress'},
      status: AiToolCallStatus.complete,
    );
    await tester.pumpWidget(_host(CliTaskUpdateBubble(part: part)));
    expect(find.textContaining('TaskUpdate · T9', findRichText: true), findsOneWidget);
    expect(find.text('In progress'), findsOneWidget);
  });

  testWidgets('TodoWrite bubble shows count pill and expandable todo list',
      (tester) async {
    final part = AiToolCallPart(
      toolCallId: 't',
      toolName: 'TodoWrite',
      args: const {
        'merge': false,
        'todos': [
          {'id': 'a', 'content': 'Task A', 'status': 'in_progress'},
          {'id': 'b', 'content': 'Task B', 'status': 'pending'},
        ],
      },
      status: AiToolCallStatus.complete,
    );
    await tester.pumpWidget(_host(CliTodoWriteBubble(part: part)));
    expect(find.textContaining('TodoWrite', findRichText: true), findsOneWidget);
    expect(find.text('0/2'), findsOneWidget);
    await tester.tap(find.text('0/2'));
    await tester.pump();
    expect(find.text('Task A'), findsOneWidget);
    expect(find.text('Task B'), findsOneWidget);
  });

  testWidgets('cliTaskBubbleBuilders returns create + update + todowrite',
      (_) async {
    final builders = cliTaskBubbleBuilders();
    expect(
      builders.keys,
      containsAll(['taskcreate', 'taskupdate', 'todowrite']),
    );
  });
}
