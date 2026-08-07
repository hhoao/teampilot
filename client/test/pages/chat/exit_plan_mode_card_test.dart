import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/pages/chat/exit_plan_mode_card.dart';
import 'package:teampilot/theme/app_typography_scale.dart';
import 'package:teampilot/utils/ui/app_keys.dart';

void main() {
  testWidgets('shows plan text, path, and Open Terminal CTA', (tester) async {
    var opened = false;
    final theme = ThemeData(useMaterial3: true);
    await tester.pumpWidget(
      MaterialApp(
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
          child: Scaffold(
            body: ExitPlanModeCard(
              planText: '1. Refactor the launcher.\n2. Add tests.',
              planFilePath: '/tmp/plan.md',
              onOpenTerminal: () => opened = true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(AppKeys.exitPlanModeCard), findsOneWidget);
    expect(find.textContaining('Refactor the launcher'), findsOneWidget);
    expect(find.text('/tmp/plan.md'), findsOneWidget);

    await tester.tap(find.byKey(AppKeys.agentPermissionOpenTerminalButton));
    await tester.pumpAndSettle();

    expect(opened, isTrue);
  });
}
