import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/theme/app_control_theme.dart';
import 'package:teampilot/theme/app_outline_input_theme.dart';
import 'package:teampilot/theme/app_typography_scale.dart';
import 'package:teampilot/theme/workspace_surface_layers.dart';
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

  testWidgets('expands and wraps — never maxLines: 1', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: themeWithTightInput(),
        home: const Scaffold(body: AppTextarea(minHeight: 80)),
      ),
    );
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.expands, isTrue);
    expect(field.maxLines, isNull);
    expect(field.minLines, isNull);
    expect(field.keyboardType, TextInputType.multiline);
  });

  testWidgets('hides platform scrollbar', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: themeWithTightInput(),
        home: const Scaffold(body: AppTextarea(minHeight: 80)),
      ),
    );
    final scrollConfig = tester.widget<ScrollConfiguration>(
      find.descendant(
        of: find.byType(AppTextarea),
        matching: find.byType(ScrollConfiguration),
      ),
    );
    expect(scrollConfig.behavior, isA<AppTextareaScrollBehavior>());
    expect(find.byType(Scrollbar), findsNothing);
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

  testWidgets('fill color matches single-line outline inputs', (tester) async {
    final theme = themeWithTightInput();
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: const Scaffold(body: AppTextarea()),
      ),
    );
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(
      field.decoration?.fillColor,
      theme.colorScheme.workspaceCard,
    );
    expect(
      field.decoration?.fillColor,
      theme.inputDecorationTheme.fillColor,
    );
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
      kAppTextareaContentPadding,
    );
  });

  testWidgets('focus border matches single-line outline inputs', (tester) async {
    final theme = themeWithTightInput();
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: const Scaffold(body: AppTextarea(minHeight: 80)),
      ),
    );

    expect(find.byType(AnimatedContainer), findsNothing);

    final field = tester.widget<TextField>(find.byType(TextField));
    final focused =
        field.decoration!.focusedBorder! as OutlineInputBorder;
    final themeFocused =
        theme.inputDecorationTheme.focusedBorder! as OutlineInputBorder;
    expect(focused.borderSide.width, 1.5);
    expect(focused.borderSide.color, themeFocused.borderSide.color);
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
      3 * 20 +
          kAppTextareaTopPadding +
          kAppTextareaBottomPadding +
          kAppTextareaBottomInset +
          kAppTextareaBorderWidth * 2,
    );
  });
}
