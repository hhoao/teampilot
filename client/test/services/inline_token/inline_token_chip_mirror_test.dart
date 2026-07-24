import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/services/inline_token/inline_token_palette.dart';

void main() {
  test('defaultInlineTokenPattern requires leading whitespace or start', () {
    String? onlyMatch(String text) {
      final matches = defaultInlineTokenPattern.allMatches(text).toList();
      if (matches.isEmpty) return null;
      expect(matches, hasLength(1));
      return matches.single.group(0);
    }

    expect(onlyMatch('@file'), '@file');
    expect(onlyMatch('see @file'), '@file');
    expect(onlyMatch('/skill'), '/skill');
    expect(onlyMatch('run /skill'), '/skill');
    expect(onlyMatch('user@host'), isNull);
    expect(onlyMatch('https://example.com'), isNull);
    expect(onlyMatch('a/b'), isNull);
  });

  test('buildTpTokenMirrorLayoutSpans paints token glyphs with palette color', () {
    const style = TextStyle(fontSize: 14, height: 1.5, color: Colors.black);
    const scheme = ColorScheme.light();
    final spans = buildTpTokenMirrorLayoutSpans(
      text: 'use /writing-plans on @src/main.dart',
      baseStyle: style,
      tokenPattern: defaultInlineTokenPattern,
      colorScheme: scheme,
      resolvePalette: resolveSlashAtTokenPalette,
    );

    expect(spans.length, 4);
    expect((spans[0] as TextSpan).text, 'use ');
    final slash = spans[1] as TextSpan;
    expect(slash.text, '/writing-plans');
    expect(
      slash.style?.color,
      resolveSlashAtTokenPalette('/writing-plans', scheme).foreground,
    );
  });

  test('tpTokenPillWidth never extends past layout token end', () {
    const layoutWidth = 180.0;
    expect(
      tpTokenPillWidth(layoutWidth),
      layoutWidth + tpTokenPillLeftBleed,
    );
  });
}
