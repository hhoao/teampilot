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
          alwaysOptions: const ['Always allow'],
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

  testWidgets('tapping allow once replies allowOnce', (tester) async {
    AiPermissionReply? captured;
    await tester.pumpWidget(
      _host(
        AiPermissionCard(
          description: 'Run `npm install`',
          alwaysOptions: const ['Always allow'],
          onReply: (reply) async {
            captured = reply;
            return const AiInteractiveOk();
          },
          onAnswerInTerminal: () {},
        ),
      ),
    );
    await tester.tap(find.byKey(AiPermissionCard.allowOnceButtonKey));
    await tester.pumpAndSettle();
    expect(captured!.kind, AiPermissionReplyKind.allowOnce);
  });

  testWidgets('tapping the always button replies with the option index', (
    tester,
  ) async {
    AiPermissionReply? captured;
    await tester.pumpWidget(
      _host(
        AiPermissionCard(
          description: 'Bash rm -rf node_modules',
          alwaysOptions: const [
            'Always allow Bash(rm -rf node_modules)',
            'Always allow Bash',
          ],
          onReply: (reply) async {
            captured = reply;
            return const AiInteractiveOk();
          },
          onAnswerInTerminal: () {},
        ),
      ),
    );
    await tester.tap(
      find.byKey(AiPermissionCard.alwaysButtonKey),
    ); // first option
    await tester.pumpAndSettle();
    expect(captured!.kind, AiPermissionReplyKind.always);
    expect(captured!.alwaysOptionIndex, 0);
    // second always button is keyed by index
    await tester.tap(find.byKey(const Key('opencode-permission-always-1')));
    await tester.pumpAndSettle();
    expect(captured!.alwaysOptionIndex, 1);
  });

  testWidgets('no always buttons when alwaysOptions is empty', (tester) async {
    await tester.pumpWidget(
      _host(
        AiPermissionCard(
          description: 'Run `npm install`',
          onReply: (reply) async => const AiInteractiveOk(),
          onAnswerInTerminal: () {},
        ),
      ),
    );
    expect(find.byKey(AiPermissionCard.alwaysButtonKey), findsNothing);
  });

  testWidgets('Reject replies reject', (tester) async {
    AiPermissionReply? captured;
    await tester.pumpWidget(
      _host(
        AiPermissionCard(
          description: 'Run `npm install`',
          alwaysOptions: const ['Always allow'],
          onReply: (reply) async {
            captured = reply;
            return const AiInteractiveOk();
          },
          onAnswerInTerminal: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(AiPermissionCard.rejectButtonKey));
    await tester.pumpAndSettle();

    expect(captured!.kind, AiPermissionReplyKind.reject);
    expect(captured!.alwaysOptionIndex, isNull);
  });

  testWidgets('failed reply shows inline error', (tester) async {
    await tester.pumpWidget(
      _host(
        AiPermissionCard(
          description: 'Run `npm install`',
          alwaysOptions: const ['Always allow'],
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
