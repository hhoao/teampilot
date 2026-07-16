import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/theme/app_button_theme.dart';
import 'package:teampilot/theme/app_theme.dart';
import 'package:teampilot/theme/app_typography_scale.dart';

TpControlMetrics _controlFor(ThemeData theme, AppTypographyScale scale) {
  // Control metrics are baked into button/input ThemeData at build time;
  // they are not reinstalled as a ThemeExtension (TpTheme owns runtime tokens).
  return TpControlMetrics.fromScale(scale.multiplier);
}

Widget _withTpTheme({
  required ThemeData theme,
  required double controlScale,
  required Widget child,
}) {
  return MaterialApp(
    theme: theme,
    home: TpTheme(
      data: TpThemeData.fromColorScheme(
        theme.colorScheme,
        scale: 1.0,
        controlScale: controlScale,
      ),
      child: child,
    ),
  );
}

void main() {
  test('buttons keep compact track with horizontal-only padding', () {
    final theme = buildDarkTheme();
    final control = _controlFor(theme, AppTypographyScale.standard);
    expect(control.height, TpControlMetrics.heightBase);
    expect(control.horizontalPadding, TpControlMetrics.horizontalPaddingBase);
    expect(control.medium.height, lessThan(control.input.height));

    Size? minOf(ButtonStyle? style) => style?.minimumSize?.resolve({});
    Size? maxOf(ButtonStyle? style) => style?.maximumSize?.resolve({});
    expect(minOf(theme.filledButtonTheme.style)?.height, control.medium.height);
    expect(maxOf(theme.outlinedButtonTheme.style)?.height, control.medium.height);
    expect(theme.outlinedButtonTheme.style?.tapTargetSize, MaterialTapTargetSize.shrinkWrap);

    final buttonPad = theme.outlinedButtonTheme.style?.padding?.resolve({});
    expect(buttonPad, isA<EdgeInsets>());
    final buttonInset = buttonPad! as EdgeInsets;
    expect(buttonInset.left, control.horizontalPadding);
    expect(buttonInset.right, control.horizontalPadding);
    expect(buttonInset.top, 0);
    expect(buttonInset.bottom, 0);
  });

  test('outline inputs keep taller track with real vertical padding', () {
    final theme = buildDarkTheme();
    final control = _controlFor(theme, AppTypographyScale.standard);
    expect(control.input.height, TpControlMetrics.inputHeightBase);
    expect(
      control.input.horizontalPadding,
      TpControlMetrics.inputHorizontalPaddingBase,
    );
    expect(
      control.input.verticalPadding,
      TpControlMetrics.inputVerticalPaddingBase,
    );

    expect(
      theme.inputDecorationTheme.constraints?.minHeight,
      control.input.height,
    );
    expect(
      theme.inputDecorationTheme.constraints?.maxHeight,
      control.input.height,
    );

    final padding = theme.inputDecorationTheme.contentPadding;
    expect(padding, isA<EdgeInsets>());
    final inset = padding! as EdgeInsets;
    expect(inset.left, control.input.horizontalPadding);
    expect(inset.top, control.input.verticalPadding);
  });

  test('control height tracks typography scale', () {
    final std = buildDarkTheme(null, AppTypographyScale.standard);
    final comfy = buildDarkTheme(null, AppTypographyScale.comfortable);
    final stdControl = _controlFor(std, AppTypographyScale.standard);
    final comfyControl = _controlFor(comfy, AppTypographyScale.comfortable);
    expect(comfyControl.height, greaterThan(stdControl.height));
    expect(comfyControl.input.height, greaterThan(stdControl.input.height));
    expect(
      comfy.inputDecorationTheme.constraints?.minHeight,
      comfyControl.input.height,
    );
  });

  testWidgets('standard buttons use onSurface foreground', (tester) async {
    final theme = buildDarkTheme();
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: Column(
            children: [
              FilledButton(onPressed: () {}, child: const Text('filled')),
              FilledButton.tonal(onPressed: () {}, child: const Text('tonal')),
              OutlinedButton(onPressed: () {}, child: const Text('outlined')),
              TextButton(onPressed: () {}, child: const Text('text')),
            ],
          ),
        ),
      ),
    );

    Color fg(String label) {
      final element = tester.element(find.text(label));
      return DefaultTextStyle.of(element).style.color!;
    }

    final onSurface = theme.colorScheme.onSurface;
    expect(fg('filled'), onSurface);
    expect(fg('tonal'), onSurface);
    expect(fg('outlined'), onSurface);
    expect(fg('text'), onSurface);
  });

  test('filled/outlined/elevated use modest rounded rect, not stadium', () {
    final theme = buildDarkTheme();
    final control = _controlFor(theme, AppTypographyScale.standard);
    OutlinedBorder? shapeOf(ButtonStyle? style) {
      final s = style?.shape?.resolve({});
      return s is OutlinedBorder ? s : null;
    }

    bool looksModestRound(OutlinedBorder? b) {
      if (b is! RoundedRectangleBorder) return false;
      final r = b.borderRadius;
      if (r is! BorderRadius) return false;
      final x = r.topLeft.x;
      return (x - control.radius).abs() < 0.5 && x < 20;
    }

    expect(looksModestRound(shapeOf(theme.filledButtonTheme.style)), isTrue);
    expect(looksModestRound(shapeOf(theme.outlinedButtonTheme.style)), isTrue);
    expect(looksModestRound(shapeOf(theme.elevatedButtonTheme.style)), isTrue);
    expect(shapeOf(theme.filledButtonTheme.style), isNot(isA<StadiumBorder>()));
  });

  testWidgets('buttons stay below input track height', (tester) async {
    final theme = buildDarkTheme();
    final control = _controlFor(theme, AppTypographyScale.standard);
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: Row(
            children: [
              const SizedBox(
                width: 160,
                child: TextField(decoration: InputDecoration(hintText: 'h')),
              ),
              OutlinedButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.download_outlined, size: 18),
                label: const Text('安装'),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester.getSize(find.byType(TextField)).height,
      control.input.height,
    );
    expect(
      tester.getSize(find.byType(OutlinedButton)).height,
      control.medium.height,
    );
    expect(control.medium.height, TpControlMetrics.heightBase);
    expect(control.input.height, TpControlMetrics.inputHeightBase);
    expect(control.medium.height, lessThan(control.input.height));
  });

  testWidgets('TextField hint stays inset from outline edges', (tester) async {
    final theme = buildDarkTheme();
    final control = _controlFor(theme, AppTypographyScale.standard);
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: const Scaffold(
          body: SizedBox(
            width: 200,
            child: TextField(decoration: InputDecoration(hintText: 'hint')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final field = tester.getTopLeft(find.byType(TextField));
    final hint = tester.getTopLeft(find.text('hint'));
    expect(
      hint.dx - field.dx,
      greaterThanOrEqualTo(control.medium.horizontalPadding),
    );
    expect(hint.dy - field.dy, greaterThanOrEqualTo(3));
  });

  testWidgets('appButtonStyle size presets change painted height', (
    tester,
  ) async {
    final theme = buildDarkTheme();
    final control = _controlFor(theme, AppTypographyScale.standard);
    await tester.pumpWidget(
      _withTpTheme(
        theme: theme,
        controlScale: 1.0,
        child: Builder(
          builder: (context) {
            return Scaffold(
              body: Column(
                children: [
                  FilledButton(
                    style: appButtonStyle(context, size: TpControlSize.small),
                    onPressed: () {},
                    child: const Text('S'),
                  ),
                  FilledButton(
                    style: appButtonStyle(context, size: TpControlSize.medium),
                    onPressed: () {},
                    child: const Text('M'),
                  ),
                  FilledButton(
                    style: appButtonStyle(context, size: TpControlSize.large),
                    onPressed: () {},
                    child: const Text('L'),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester.getSize(find.widgetWithText(FilledButton, 'S')).height,
      control.small.height,
    );
    expect(
      tester.getSize(find.widgetWithText(FilledButton, 'M')).height,
      control.medium.height,
    );
    expect(
      tester.getSize(find.widgetWithText(FilledButton, 'L')).height,
      control.large.height,
    );
  });
}
