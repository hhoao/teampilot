import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/theme/app_theme.dart';
import 'package:teampilot/theme/app_typography_scale.dart';

void main() {
  test('TpIconSizes.fromScale uses baseline sizes at multiplier 1.0', () {
    final resolved = TpIconSizes.fromScale(1.0);
    expect(resolved.md, TpIconSizes.mdBase);
    expect(resolved.hero, TpIconSizes.heroBase);
  });

  test('resolveIconMultiplier tracks OS text baseline only', () {
    const osBaseline = 1.5;
    final mapped = TpIconSizes.resolveIconMultiplier(textBaseline: osBaseline);
    expect(mapped, TpIconSizes.baselineScale * osBaseline);
  });

  test('iconSizeForTextFontSize keeps icon/text ratio when label font grows', () {
    const baseFont = AppTypographyScale.bodyLargeBase;
    const grownFont = baseFont * 1.2;
    final baseIcon = TpIconSizes.iconSizeForTextFontSize(
      baseFont,
      textBaseAtScale1: baseFont,
    );
    final grownIcon = TpIconSizes.iconSizeForTextFontSize(
      grownFont,
      textBaseAtScale1: baseFont,
    );
    expect(grownIcon / baseIcon, 1.2);
    expect(grownIcon / grownFont, baseIcon / baseFont);
  });

  test('icon theme ignores in-app text-size preset at baseline 1.0', () {
    final std = buildDarkTheme(null, AppTypographyScale.standard);
    final comfy = buildDarkTheme(null, AppTypographyScale.comfortable);

    final stdIconMult = TpIconSizes.resolveIconMultiplier(textBaseline: 1.0);
    expect(std.iconTheme.size, TpIconSizes.mdBase * stdIconMult);
    expect(comfy.iconTheme.size, std.iconTheme.size);
  });

  test('toolbar icon/text on-screen ratio stable across simulated high-DPI', () {
    const dpr = 1.5;
    const bodyLargeBase = AppTypographyScale.bodyLargeBase;
    const uiZoom = 1.0 / dpr;

    final textBaseline = dpr;
    final iconMult = TpIconSizes.resolveIconMultiplier(textBaseline: textBaseline);
    final pairedIcon = TpIconSizes.iconSizeForTextFontSize(
      bodyLargeBase * textBaseline,
      textBaseAtScale1: bodyLargeBase,
    );

    final textOnScreen = bodyLargeBase * textBaseline * uiZoom;
    final iconOnScreen = pairedIcon * uiZoom;
    final ratioAtDpr = iconOnScreen / textOnScreen;

    final textAt100 = bodyLargeBase;
    final iconAt100 = TpIconSizes.iconSizeForTextFontSize(
      bodyLargeBase,
      textBaseAtScale1: bodyLargeBase,
    );
    final ratioAt100 = iconAt100 / textAt100;

    expect(ratioAtDpr, closeTo(ratioAt100, 0.001));
  });

  test('paired icons track text zoom while toolbar md stays on OS baseline', () {
    const textBaseline = 1.0;
    const typography = 1.2;
    const uiZoom = 0.68;

    final labelFont = AppTypographyScale.bodyLargeBase * textBaseline * typography;
    final pairedIcon = TpIconSizes.iconSizeForTextFontSize(
      labelFont,
      textBaseAtScale1: AppTypographyScale.bodyLargeBase,
    );
    final toolbarIcon = TpIconSizes.mdBase *
        TpIconSizes.resolveIconMultiplier(textBaseline: textBaseline);

    final pairedRatio =
        (pairedIcon * uiZoom) / (labelFont * uiZoom);
    final toolbarRatio =
        (toolbarIcon * uiZoom) / (labelFont * uiZoom);

    expect(pairedRatio, closeTo(1.485, 0.001));
    expect(toolbarRatio, lessThan(pairedRatio));
  });
}
