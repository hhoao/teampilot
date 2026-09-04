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
  testWidgets('compact card hides plan content and opens terminal', (
    tester,
  ) async {
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
    expect(
      find.byType(MarkdownView),
      findsNothing,
      reason: 'plan content renders only in the floating preview',
    );
    expect(find.byKey(AiExitPlanModeCard.viewPlanButtonKey), findsOneWidget);
    expect(find.text('/tmp/plan.md'), findsOneWidget);
    expect(find.byKey(AiExitPlanModeCard.approveButtonKey), findsNothing);
    expect(
      find.byKey(AiExitPlanModeCard.openTerminalButtonKey),
      findsOneWidget,
    );

    await tester.tap(find.byKey(AiExitPlanModeCard.openTerminalButtonKey));
    await tester.pumpAndSettle();
    expect(opened, isTrue);
  });

  testWidgets('view plan opens the floating preview with markdown', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        AiExitPlanModeCard(
          planText: '1. Refactor the launcher.',
          onOpenTerminal: () {},
          onOpenPlanFile: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(AiExitPlanModeCard.viewPlanButtonKey));
    await tester.pumpAndSettle();

    expect(find.byKey(AiExitPlanModeCard.previewDialogKey), findsOneWidget);
    expect(find.byType(MarkdownView), findsOneWidget);

    // Close via the dialog header close button.
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();
    expect(find.byKey(AiExitPlanModeCard.previewDialogKey), findsNothing);
  });

  testWidgets('copy button in preview copies plan text', (tester) async {
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

    await tester.tap(find.byKey(AiExitPlanModeCard.viewPlanButtonKey));
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

  testWidgets('preview footer opens the plan file and closes the dialog', (
    tester,
  ) async {
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

    await tester.tap(find.byKey(AiExitPlanModeCard.viewPlanButtonKey));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open plan file'));
    await tester.pumpAndSettle();
    expect(openedPath, '/tmp/plan.md');
    expect(find.byKey(AiExitPlanModeCard.previewDialogKey), findsNothing);
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
