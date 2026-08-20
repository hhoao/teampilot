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
  testWidgets('renders permission description with allow / reject buttons', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        AiPermissionCard(
          description: 'Run `npm install`',
          showAlwaysAllow: true,
          onReply: (_) async => const AiInteractiveOk(),
          onAnswerInTerminal: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(AiPermissionCard.cardKey), findsOneWidget);
    expect(find.textContaining('npm install'), findsWidgets);
    expect(find.text('Allow once'), findsOneWidget);
    expect(find.text('Always allow'), findsOneWidget);
    expect(find.text('Reject'), findsOneWidget);
  });

  testWidgets('Allow once replies "once"', (tester) async {
    final replies = <String>[];
    await tester.pumpWidget(
      _host(
        AiPermissionCard(
          description: 'Run `npm install`',
          onReply: (reply) async {
            replies.add(reply);
            return const AiInteractiveOk();
          },
          onAnswerInTerminal: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(AiPermissionCard.allowOnceButtonKey));
    await tester.pumpAndSettle();

    expect(replies, ['once']);
  });

  testWidgets('Always allow replies "always"', (tester) async {
    final replies = <String>[];
    await tester.pumpWidget(
      _host(
        AiPermissionCard(
          description: 'Run `npm install`',
          showAlwaysAllow: true,
          onReply: (reply) async {
            replies.add(reply);
            return const AiInteractiveOk();
          },
          onAnswerInTerminal: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(AiPermissionCard.alwaysButtonKey));
    await tester.pumpAndSettle();

    expect(replies, ['always']);
  });

  testWidgets('Always allow hidden when showAlwaysAllow is false', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        AiPermissionCard(
          description: 'Run `npm install`',
          onReply: (_) async => const AiInteractiveOk(),
          onAnswerInTerminal: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(AiPermissionCard.alwaysButtonKey), findsNothing);
    expect(find.byKey(AiPermissionCard.allowOnceButtonKey), findsOneWidget);
    expect(find.byKey(AiPermissionCard.rejectButtonKey), findsOneWidget);
  });

  testWidgets('Reject replies "reject"', (tester) async {
    final replies = <String>[];
    await tester.pumpWidget(
      _host(
        AiPermissionCard(
          description: 'Run `npm install`',
          showAlwaysAllow: true,
          onReply: (reply) async {
            replies.add(reply);
            return const AiInteractiveOk();
          },
          onAnswerInTerminal: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(AiPermissionCard.rejectButtonKey));
    await tester.pumpAndSettle();

    expect(replies, ['reject']);
  });

  testWidgets('failed reply shows inline error', (tester) async {
    await tester.pumpWidget(
      _host(
        AiPermissionCard(
          description: 'Run `npm install`',
          showAlwaysAllow: true,
          onReply: (_) async => const AiInteractiveFailed('unsupported'),
          onAnswerInTerminal: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(AiPermissionCard.allowOnceButtonKey));
    await tester.pumpAndSettle();

    expect(find.byKey(AiPermissionCard.inlineErrorKey), findsOneWidget);
  });
}
