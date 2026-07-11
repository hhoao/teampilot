import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/theme/app_button_theme.dart';
import 'package:teampilot/theme/app_control_theme.dart';
import 'package:teampilot/theme/app_theme.dart';
import 'package:teampilot/theme/app_typography_scale.dart';

void main() {
  test(
    'input and standard button min heights share AppControlTheme.height',
    () {
      final theme = buildDarkTheme();
      final control = theme.extension<AppControlTheme>()!;
      final inputMin = theme.inputDecorationTheme.constraints?.minHeight;
      expect(inputMin, control.height);

      Size? minOf(ButtonStyle? style) => style?.minimumSize?.resolve({});
      expect(minOf(theme.filledButtonTheme.style)?.height, control.height);
      expect(minOf(theme.outlinedButtonTheme.style)?.height, control.height);
      expect(minOf(theme.elevatedButtonTheme.style)?.height, control.height);
      expect(minOf(theme.textButtonTheme.style)?.height, control.height);
    },
  );

  test('control height tracks typography scale', () {
    final std = buildDarkTheme(null, AppTypographyScale.standard);
    final comfy = buildDarkTheme(null, AppTypographyScale.comfortable);
    expect(
      comfy.extension<AppControlTheme>()!.height,
      greaterThan(std.extension<AppControlTheme>()!.height),
    );
    expect(
      comfy.inputDecorationTheme.constraints?.minHeight,
      comfy.extension<AppControlTheme>()!.height,
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
    final control = theme.extension<AppControlTheme>()!;
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

  testWidgets('painted TextField and FilledButton heights match control', (
    tester,
  ) async {
    final theme = buildDarkTheme();
    final control = theme.extension<AppControlTheme>()!;
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
              FilledButton(onPressed: () {}, child: const Text('Go')),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.getSize(find.byType(TextField)).height, control.height);
    expect(tester.getSize(find.byType(FilledButton)).height, control.height);
  });

  testWidgets('appButtonStyle size presets change painted height', (
    tester,
  ) async {
    final theme = buildDarkTheme();
    final control = theme.extension<AppControlTheme>()!;
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: Column(
                children: [
                  FilledButton(
                    style: appButtonStyle(context, size: AppControlSize.small),
                    onPressed: () {},
                    child: const Text('S'),
                  ),
                  FilledButton(
                    style: appButtonStyle(context, size: AppControlSize.medium),
                    onPressed: () {},
                    child: const Text('M'),
                  ),
                  FilledButton(
                    style: appButtonStyle(context, size: AppControlSize.large),
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
