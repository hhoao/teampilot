import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tp_markdown/tp_markdown.dart';

void main() {
  test('mark helpers use configurable MarkdownTokens mark policy', () {
    const base = TextStyle(fontSize: 14, height: 1.7, fontFamily: 'UI');
    final tokens = MarkdownTokens.test(strongWeight: FontWeight.w600);

    expect(tokens.strongStyle(base).fontWeight, FontWeight.w600);
    expect(tokens.strongStyle(base).fontSize, 14);
    expect(tokens.strongStyle(base).height, 1.7);

    expect(tokens.emphasisStyle(base).fontStyle, FontStyle.italic);
    expect(
      tokens.emphasisStyle(tokens.strongStyle(base)).fontWeight,
      FontWeight.w600,
    );
    expect(
      tokens.emphasisStyle(tokens.strongStyle(base)).fontStyle,
      FontStyle.italic,
    );

    expect(
      tokens.strikeStyle(base).decoration,
      TextDecoration.lineThrough,
    );
  });

  test('MarkdownTokens.inlineCodeAt keeps mono chrome and surrounding metrics',
      () {
    final tokens = MarkdownTokens.test();
    final base = tokens.h1;
    final code = tokens.inlineCodeAt(base);

    expect(code.fontFamily, tokens.inlineCode.fontFamily);
    expect(code.fontSize, base.fontSize);
    expect(code.height, base.height);
    expect(code.letterSpacing, base.letterSpacing);
  });

  test('textStylesForWarmup includes mark-derived body styles', () {
    final tokens = MarkdownTokens.test(strongWeight: FontWeight.w600);
    expect(
      tokens.textStylesForWarmup.any(
        (s) =>
            s.fontWeight == FontWeight.w600 &&
            s.fontSize == tokens.body.fontSize &&
            s.fontStyle != FontStyle.italic,
      ),
      isTrue,
      reason: 'strongStyle(body) must be in single-style warmup fingerprints',
    );
    expect(
      tokens.textStylesForWarmup.any((s) => s.fontStyle == FontStyle.italic),
      isTrue,
    );
  });
}
