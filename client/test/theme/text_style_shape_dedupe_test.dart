import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/theme/app_font_resolver.dart';
import 'package:teampilot/theme/app_text_styles_warmup.dart';

void main() {
  test('interactive warmup dedupes styles that share a shape fingerprint', () {
    final fonts = AppFontResolver.resolve(
      uiFontId: 'system',
      monoFontId: 'jetbrainsMono',
      platform: TargetPlatform.linux,
    );
    final theme = bootstrapThemeForTextWarmup(fonts);
    final all = textStylesForThemeWarmup(theme);
    final deduped = dedupeTextStylesByShapeKey(all);

    final allKeys = all.map(textStyleShapeKey).toSet();
    final dedupedKeys = deduped.map(textStyleShapeKey).toSet();

    expect(
      deduped.length,
      lessThan(all.length),
      reason: 'expected dedupe: ${all.length} → ${deduped.length}',
    );
    expect(dedupedKeys, allKeys);
    expect(deduped.length, dedupedKeys.length);
    // Rough savings signal for boot (keep in sync with typical theme scale).
    expect(deduped.length, lessThanOrEqualTo(all.length ~/ 2 + 5));
  });

  test('textStyleShapeKey ignores height and letterSpacing', () {
    const a = TextStyle(
      fontFamily: 'Noto Sans SC',
      fontSize: 14,
      fontWeight: FontWeight.w400,
      height: 1.2,
      letterSpacing: 0.2,
    );
    const b = TextStyle(
      fontFamily: 'Noto Sans SC',
      fontSize: 14,
      fontWeight: FontWeight.w400,
      height: 1.5,
      letterSpacing: 0.5,
    );
    expect(textStyleShapeKey(a), textStyleShapeKey(b));
  });
}
