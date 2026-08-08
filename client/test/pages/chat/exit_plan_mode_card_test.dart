import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/pages/chat/exit_plan_mode_card.dart';
import 'package:teampilot/services/terminal/exit_plan_mode_approval_service.dart';
import 'package:teampilot/theme/app_typography_scale.dart';
import 'package:teampilot/utils/ui/app_keys.dart';
import 'package:tp_markdown/tp_markdown.dart';

Widget _wrap(Widget child) {
  final theme = ThemeData(useMaterial3: true);
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
  testWidgets('renders markdown plan and opens terminal', (tester) async {
    var opened = false;
    await tester.pumpWidget(
      _wrap(
        ExitPlanModeCard(
          planText: '1. Refactor the launcher.\n2. Add tests.',
          planFilePath: '/tmp/plan.md',
          onOpenTerminal: () => opened = true,
          onOpenPlanFile: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(AppKeys.exitPlanModeCard), findsOneWidget);
    expect(find.byType(MarkdownView), findsOneWidget);
    expect(find.text('/tmp/plan.md'), findsOneWidget);
    // No in-chat approve → primary Open Terminal.
    expect(
      find.byKey(AppKeys.exitPlanModeApproveButton),
      findsNothing,
    );

    await tester.tap(find.byKey(AppKeys.agentPermissionOpenTerminalButton));
    await tester.pumpAndSettle();
    expect(opened, isTrue);
  });

  testWidgets('expand/collapse toggles', (tester) async {
    await tester.pumpWidget(
      _wrap(
        ExitPlanModeCard(
          planText: 'Long plan text here.',
          onOpenTerminal: () {},
          onOpenPlanFile: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(AppKeys.exitPlanModeExpandButton), findsOneWidget);
    expect(find.text('Expand'), findsOneWidget);

    await tester.tap(find.byKey(AppKeys.exitPlanModeExpandButton));
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
      () => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );

    await tester.pumpWidget(
      _wrap(
        ExitPlanModeCard(
          planText: 'Copy me',
          onOpenTerminal: () {},
          onOpenPlanFile: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(AppKeys.exitPlanModeCopyPlanButton));
    await tester.pumpAndSettle();
    expect(copied, ['Copy me']);
  });

  testWidgets('plan file path tap calls onOpenPlanFile', (tester) async {
    String? openedPath;
    await tester.pumpWidget(
      _wrap(
        ExitPlanModeCard(
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

  testWidgets('in-chat approve/reject visible and approve shows error',
      (tester) async {
    var approved = false;
    await tester.pumpWidget(
      _wrap(
        ExitPlanModeCard(
          planText: 'plan',
          onApprove: () async {
            approved = true;
            return const ExitPlanApprovalFailed('no_pending_approval');
          },
          onReject: () async => const ExitPlanApprovalOk(),
          onOpenTerminal: () {},
          onOpenPlanFile: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(AppKeys.exitPlanModeApproveButton), findsOneWidget);
    expect(find.byKey(AppKeys.exitPlanModeRejectButton), findsOneWidget);

    await tester.tap(find.byKey(AppKeys.exitPlanModeApproveButton));
    await tester.pumpAndSettle();
    expect(approved, isTrue);
    expect(find.byKey(AppKeys.exitPlanModeInlineError), findsOneWidget);
  });
}
