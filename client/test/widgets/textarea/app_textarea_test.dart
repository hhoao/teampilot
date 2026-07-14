import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/theme/app_control_theme.dart';
import 'package:teampilot/theme/app_outline_input_theme.dart';
import 'package:teampilot/theme/app_typography_scale.dart';
import 'package:teampilot/widgets/textarea/app_textarea.dart';
import 'package:teampilot/widgets/textarea/app_textarea_resize_grip.dart';

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
    expect(c!.maxHeight, isNot(equals(c.minHeight)));
  });

  testWidgets('uses muted placeholder and shadcn-like padding', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: themeWithTightInput(),
        home: const Scaffold(
          body: AppTextarea(
            decoration: InputDecoration(hintText: 'Type here'),
          ),
        ),
      ),
    );
    final field = tester.widget<TextField>(find.byType(TextField));
    final decoration = field.decoration!;
    expect(decoration.hintStyle?.color?.a, lessThan(0.7));
    expect(
      decoration.contentPadding,
      const EdgeInsets.symmetric(
        horizontal: kAppTextareaHorizontalPadding,
        vertical: kAppTextareaVerticalPadding,
      ),
    );
  });

  testWidgets('shows focus ring when focused', (tester) async {
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: themeWithTightInput(),
        home: Scaffold(
          body: AppTextarea(focusNode: focusNode, minHeight: 80),
        ),
      ),
    );

    final idle = tester.widget<AnimatedContainer>(
      find.byType(AnimatedContainer),
    );
    final idleShadows =
        (idle.decoration! as BoxDecoration).boxShadow ?? const <BoxShadow>[];
    expect(idleShadows.first.spreadRadius, isNot(kAppTextareaFocusRingSpread));

    focusNode.requestFocus();
    await tester.pumpAndSettle();

    final focused = tester.widget<AnimatedContainer>(
      find.byType(AnimatedContainer),
    );
    final focusedShadows =
        (focused.decoration! as BoxDecoration).boxShadow!;
    expect(focusedShadows.single.spreadRadius, kAppTextareaFocusRingSpread);
  });

  testWidgets('resize grip has enlarged hit target', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: themeWithTightInput(),
        home: const Scaffold(body: AppTextarea()),
      ),
    );
    final grip = tester.getSize(find.byKey(const Key('app-textarea-resize-grip')));
    expect(grip.width, kAppTextareaResizeGripHitSize);
    expect(grip.height, kAppTextareaResizeGripHitSize);
  });

  testWidgets('default minHeight is 80 like ShadTextarea', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: themeWithTightInput(),
        home: const Scaffold(body: AppTextarea()),
      ),
    );
    final shellSize = tester.getSize(find.byType(AppTextarea));
    expect(shellSize.height, 80);
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
