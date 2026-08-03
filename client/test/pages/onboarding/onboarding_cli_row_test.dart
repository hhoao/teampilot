import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/pages/onboarding/steps/onboarding_cli_row.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/theme/app_typography_scale.dart';
import 'package:teampilot/utils/ui/app_keys.dart';

Widget _wrap(Widget child) {
  final theme = ThemeData(useMaterial3: true);
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
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

Future<void> _pumpRow(
  WidgetTester tester,
  Size viewport, {
  String? detectedPath,
}) async {
  tester.view.physicalSize = viewport;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final registry = CliToolRegistry.builtIn();
  final definition = registry.tryGet(CliTool.claude)!;
  final controller = TextEditingController(
    text: detectedPath ?? '',
  );
  final busy = ValueNotifier<bool>(false);
  addTearDown(busy.dispose);
  addTearDown(controller.dispose);

  await tester.pumpWidget(
    _wrap(
      OnboardingCliRow(
        definition: definition,
        label: 'Claude Code',
        controller: controller,
        detectedPath: detectedPath,
        supportsInstall: true,
        installing: false,
        busyListenable: busy,
        onPathChanged: (_) {},
        onInstall: () {},
      ),
    ),
  );
}

void main() {
  testWidgets('stacks path field below header when width < sm', (tester) async {
    await _pumpRow(tester, const Size(390, 800));

    final iconTop = tester
        .getTopLeft(find.byKey(const ValueKey('onboarding-cli-icon-claude')))
        .dy;
    final fieldTop = tester.getTopLeft(find.byType(TextField)).dy;

    expect(fieldTop, greaterThan(iconTop + 8));
  });

  testWidgets('keeps single row when width >= sm', (tester) async {
    await _pumpRow(tester, const Size(800, 800));

    final iconTop = tester
        .getTopLeft(find.byKey(const ValueKey('onboarding-cli-icon-claude')))
        .dy;
    final fieldTop = tester.getTopLeft(find.byType(TextField)).dy;

    expect((fieldTop - iconTop).abs(), lessThan(20));
  });

  testWidgets('exposes stable keys for path field and install button', (
    tester,
  ) async {
    await _pumpRow(tester, const Size(390, 800));

    expect(
      find.byKey(AppKeys.cliExecutablePathFieldFor(CliTool.claude)),
      findsOneWidget,
    );
    expect(
      find.byKey(AppKeys.cliInstallButtonFor(CliTool.claude)),
      findsOneWidget,
    );
  });

  testWidgets('keeps detected status icon beside label on narrow layout', (
    tester,
  ) async {
    await _pumpRow(
      tester,
      const Size(390, 800),
      detectedPath: '/root/.local/bin/claude',
    );

    final labelRight = tester.getTopRight(find.text('Claude Code')).dx;
    final statusLeft = tester
        .getTopLeft(find.byIcon(Icons.check_circle_outline))
        .dx;
    final rowRight = tester.getTopRight(find.byType(OnboardingCliRow)).dx;

    // Status sits immediately after the label, not at the card trailing edge.
    expect(statusLeft - labelRight, lessThan(20));
    expect(rowRight - statusLeft, greaterThan(100));
  });
}
