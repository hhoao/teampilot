import 'package:ai_message_core/ai_message_core.dart';
import 'package:ai_message_ui/ai_message_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tp_markdown/tp_markdown.dart';

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
  testWidgets('renders markdown plan and opens terminal', (tester) async {
    var opened = false;
    await tester.pumpWidget(
      _host(
        AiExitPlanModeCard(
          planText: '1. Refactor the launcher.\n2. Add tests.',
          planFilePath: '/tmp/plan.md',
          onOpenTerminal: () => opened = true,
          onOpenPlanFile: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(AiExitPlanModeCard.cardKey), findsOneWidget);
    expect(find.byType(MarkdownView), findsOneWidget);
    expect(find.text('/tmp/plan.md'), findsOneWidget);
    expect(find.byKey(AiExitPlanModeCard.approveButtonKey), findsNothing);

    await tester.tap(find.byKey(AiExitPlanModeCard.openTerminalButtonKey));
    await tester.pumpAndSettle();
    expect(opened, isTrue);
  });

  testWidgets('expand/collapse toggles', (tester) async {
    await tester.pumpWidget(
      _host(
        AiExitPlanModeCard(
          planText: 'Long plan text here.',
          onOpenTerminal: () {},
          onOpenPlanFile: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(AiExitPlanModeCard.expandButtonKey), findsOneWidget);
    expect(find.text('Expand'), findsOneWidget);

    await tester.tap(find.byKey(AiExitPlanModeCard.expandButtonKey));
    await tester.pumpAndSettle();
    expect(find.text('Collapse'), findsOneWidget);
  });

  testWidgets('copy button copies plan text', (tester) async {
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await tester.pumpWidget(
      _host(
        AiExitPlanModeCard(
          planText: 'Copy me',
          onOpenTerminal: () {},
          onOpenPlanFile: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(AiExitPlanModeCard.copyPlanButtonKey));
    await tester.pumpAndSettle();
    expect(copied, ['Copy me']);
  });

  testWidgets('plan file path tap calls onOpenPlanFile', (tester) async {
    String? openedPath;
    await tester.pumpWidget(
      _host(
        AiExitPlanModeCard(
          planText: 'plan',
          planFilePath: '/tmp/plan.md',
          onOpenTerminal: () {},
          onOpenPlanFile: (p) => openedPath = p,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('/tmp/plan.md'));
    await tester.pumpAndSettle();
    expect(openedPath, '/tmp/plan.md');
  });

  testWidgets('in-chat approve/reject visible and approve shows error', (
    tester,
  ) async {
    var approved = false;
    await tester.pumpWidget(
      _host(
        AiExitPlanModeCard(
          planText: 'plan',
          onApprove: () async {
            approved = true;
            return const AiInteractiveFailed('no_pending_approval');
          },
          onReject: () async => const AiInteractiveOk(),
          onOpenTerminal: () {},
          onOpenPlanFile: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(AiExitPlanModeCard.approveButtonKey), findsOneWidget);
    expect(find.byKey(AiExitPlanModeCard.rejectButtonKey), findsOneWidget);

    await tester.tap(find.byKey(AiExitPlanModeCard.approveButtonKey));
    await tester.pumpAndSettle();
    expect(approved, isTrue);
    expect(find.byKey(AiExitPlanModeCard.inlineErrorKey), findsOneWidget);
  });
}
