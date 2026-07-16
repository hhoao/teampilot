import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/theme/app_theme.dart';
import 'package:teampilot/theme/app_typography_scale.dart';
import 'package:shared_ui/shared_ui.dart';

// Regression: context-menu item labels (workspace / session / member right-click
// menus all use TpActionMenuItem) must follow the in-app "Text size"
// (typography) setting instead of a hardcoded font size.
void main() {
  Future<double> labelFontSizeFor(
    WidgetTester tester,
    AppTypographyScale typography,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildLightTheme(null, typography),
        home: const Scaffold(
          body: TpActionMenuPanel(
            children: [
              TpActionMenuItem(icon: Icons.edit, label: 'Rename'),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final text = tester.widget<Text>(find.text('Rename'));
    return text.style!.fontSize!;
  }

  testWidgets('menu label font size tracks the typography scale', (
    tester,
  ) async {
    final compact = await labelFontSizeFor(tester, AppTypographyScale.compact);
    final comfortable = await labelFontSizeFor(
      tester,
      AppTypographyScale.comfortable,
    );

    expect(
      comfortable,
      greaterThan(compact),
      reason:
          'comfortable (×1.08) must render larger than compact (×0.92); '
          'a hardcoded fontSize would make them equal',
    );
  });
}
