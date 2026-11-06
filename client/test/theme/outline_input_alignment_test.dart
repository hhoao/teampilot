import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/theme/app_theme.dart';
import 'package:teampilot/theme/app_typography_scale.dart';

/// Regression guard for the outline-input track: the decorator lays its text
/// out from the top, so the theme's vertical content padding must fill the
/// forced box height or every field's text rides above its own centre.
void main() {
  Future<void> expectFieldTextCentred(
    WidgetTester tester,
    AppTypographyScale scale,
  ) async {
    tester.view.physicalSize = const Size(1200, 400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildLightTheme(null, scale),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 400,
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('field'),
                      decoration: const InputDecoration(hintText: 'path'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    key: const Key('action'),
                    onPressed: () {},
                    child: const Text('Browse'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final field = tester.getRect(find.byKey(const Key('field')));
    final editable = tester.getRect(
      find.descendant(
        of: find.byKey(const Key('field')),
        matching: find.byType(EditableText),
      ),
    );
    final action = tester.getRect(find.byKey(const Key('action')));
    final actionLabel = tester.getRect(find.text('Browse'));

    expect(
      editable.center.dy,
      moreOrLessEquals(field.center.dy, epsilon: 0.5),
      reason: 'input text should sit on the field box centre at $scale',
    );
    expect(
      editable.center.dy,
      moreOrLessEquals(actionLabel.center.dy, epsilon: 0.5),
      reason: 'input text should line up with the row action at $scale',
    );
    expect(
      field.center.dy,
      moreOrLessEquals(action.center.dy, epsilon: 0.5),
      reason: 'the row centres every control box',
    );
  }

  for (final scale in [
    AppTypographyScale.standard,
    AppTypographyScale.compact,
    AppTypographyScale.comfortable,
    const AppTypographyScale(multiplier: 1.3),
  ]) {
    testWidgets('outline input text is centred at scale ${scale.multiplier}', (
      tester,
    ) async {
      await expectFieldTextCentred(tester, scale);
    });
  }
}
