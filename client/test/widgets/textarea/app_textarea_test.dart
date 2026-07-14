import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/theme/app_control_theme.dart';
import 'package:teampilot/theme/app_outline_input_theme.dart';
import 'package:teampilot/theme/app_typography_scale.dart';
import 'package:teampilot/widgets/textarea/app_textarea.dart';

void main() {
  ThemeData themeWithTightInput() {
    final base = ThemeData.light();
    final control = AppControlTheme.fromScale(AppTypographyScale.standard);
    return base.copyWith(
      extensions: [control],
      inputDecorationTheme: buildAppOutlineInputDecorationTheme(
        colorScheme: base.colorScheme,
        textTheme: base.textTheme,
        control: control,
      ),
    );
  }

  testWidgets('accepts typed text', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: themeWithTightInput(),
        home: const Scaffold(body: AppTextarea()),
      ),
    );
    await tester.enterText(find.byType(TextField), 'hello');
    expect(find.text('hello'), findsOneWidget);
  });

  testWidgets('respects enabled: false', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: themeWithTightInput(),
        home: const Scaffold(body: AppTextarea(enabled: false)),
      ),
    );
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.enabled, isFalse);
  });

  testWidgets('decoration clears single-line tight height', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: themeWithTightInput(),
        home: const Scaffold(
          body: AppTextarea(minHeight: 120, maxHeight: 300),
        ),
      ),
    );
    final field = tester.widget<TextField>(find.byType(TextField));
    final c = field.decoration?.constraints;
    expect(c, isNotNull);
    expect(c!.maxHeight, isNot(equals(c.minHeight))); // not tightFor single track
  });

  testWidgets('3-line chrome-inclusive minHeight does not overflow', (
    tester,
  ) async {
    const style = TextStyle(fontSize: 14, height: 20 / 14);
    FlutterError? overflow;
    final oldOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      final message = details.exceptionAsString();
      if (message.contains('overflowed')) {
        overflow = details.exception is FlutterError
            ? details.exception as FlutterError
            : FlutterError(message);
      }
      oldOnError?.call(details);
    };
    addTearDown(() => FlutterError.onError = oldOnError);

    await tester.pumpWidget(
      MaterialApp(
        theme: themeWithTightInput(),
        home: Scaffold(
          body: AppTextarea(
            style: style,
            minHeight: appTextareaHeightForLines(style, lines: 3),
            maxHeight: appTextareaHeightForLines(style, lines: 6),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsOneWidget);
    expect(overflow, isNull);
    expect(tester.takeException(), isNull);
  });

  test('appTextareaHeightForLines includes padding and border chrome', () {
    const style = TextStyle(fontSize: 14, height: 20 / 14);
    expect(
      appTextareaHeightForLines(style, lines: 3),
      3 * 20 + kAppTextareaVerticalPadding * 2 + kAppTextareaBorderWidth * 2,
    );
  });
}
