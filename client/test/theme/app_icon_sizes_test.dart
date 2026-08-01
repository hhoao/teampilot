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

  test('resolveIconMultiplier ignores OS text baseline at dual standard', () {
    const osBaseline = 1.5;
    final mapped = TpIconSizes.resolveIconMultiplier(
      effectiveTextMultiplier: osBaseline,
      textBaseline: osBaseline,
    );
    expect(mapped, TpIconSizes.baselineScale);
  });

  test('resolveIconMultiplier tracks in-app text preset 1:1', () {
    const baseline = 1.0;
    final comfy = AppTypographyScale.comfortable.multiplier;
    final stdMapped = TpIconSizes.resolveIconMultiplier(
      effectiveTextMultiplier: baseline,
      textBaseline: baseline,
    );
    final comfyMapped = TpIconSizes.resolveIconMultiplier(
      effectiveTextMultiplier: comfy,
      textBaseline: baseline,
    );
    expect(comfyMapped / stdMapped, comfy / baseline);
  });

  test('icon theme scales with in-app text preset', () {
    final std = buildDarkTheme(null, AppTypographyScale.standard);
    final comfy = buildDarkTheme(null, AppTypographyScale.comfortable);

    final stdIconMult = TpIconSizes.resolveIconMultiplier(
      effectiveTextMultiplier: 1.0,
      textBaseline: 1.0,
    );
    expect(std.iconTheme.size, TpIconSizes.mdBase * stdIconMult);
    expect(
      comfy.iconTheme.size! / std.iconTheme.size!,
      AppTypographyScale.comfortable.multiplier,
    );
  });

  test('desktop high-DPI keeps icon/text on-screen ratio vs 100%', () {
    const dpr = 1.5;
    const bodyLargeBase = AppTypographyScale.bodyLargeBase;
    const uiZoom = 1.0 / dpr;

    // Text theme includes dpr; icons ignore absolute OS baseline.
    final textOnScreen = bodyLargeBase * dpr * uiZoom;
    final iconMult = TpIconSizes.resolveIconMultiplier(
      effectiveTextMultiplier: dpr,
      textBaseline: dpr,
    );
    final iconOnScreen = TpIconSizes.mdBase * iconMult * uiZoom;
    final ratioAtDpr = iconOnScreen / textOnScreen;

    final textAt100 = bodyLargeBase;
    final iconAt100 = TpIconSizes.mdBase *
        TpIconSizes.resolveIconMultiplier(
          effectiveTextMultiplier: 1.0,
          textBaseline: 1.0,
        );
    final ratioAt100 = iconAt100 / textAt100;

    // After UiZoom compensation, high-DPI icons are denser than 100% (by design:
    // icons stay fixed while text is inflated then zoomed). Ratio must match the
    // compensated desktop path — not the unstripped OS-baseline path.
    expect(ratioAtDpr, closeTo(iconAt100 * uiZoom / textAt100, 0.001));
    expect(ratioAtDpr, lessThan(ratioAt100));
  });

  test('paired icons strip OS baseline so desktop dual-standard matches toolbar', () {
    const dpr = 1.5;
    const labelFont = AppTypographyScale.bodyLargeBase * dpr;
    final paired = TpIconSizes.iconSizeForTextFontSize(
      labelFont,
      textBaseAtScale1: AppTypographyScale.bodyLargeBase,
      textBaseline: dpr,
    );
    final toolbar = TpIconSizes.mdBase *
        TpIconSizes.resolveIconMultiplier(
          effectiveTextMultiplier: dpr,
          textBaseline: dpr,
        );
    expect(paired, toolbar);
  });
}
