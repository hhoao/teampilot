import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/services/inline_token/inline_token_palette.dart';

void main() {
  test('buildTpTokenMirrorLayoutSpans keeps token glyphs transparent', () {
    const style = TextStyle(fontSize: 14, height: 1.5, color: Colors.black);
    final spans = buildTpTokenMirrorLayoutSpans(
      text: 'use /writing-plans on @src/main.dart',
      baseStyle: style,
      tokenPattern: defaultInlineTokenPattern,
    );

    expect(spans.length, 4);
    expect((spans[0] as TextSpan).text, 'use ');
    final slash = spans[1] as TextSpan;
    expect(slash.text, '/writing-plans');
    expect(slash.style?.color, Colors.transparent);
  });

  test('tpTokenPillWidth never extends past layout token end', () {
    const layoutWidth = 180.0;
    expect(
      tpTokenPillWidth(layoutWidth),
      layoutWidth + tpTokenPillLeftBleed,
    );
  });
}
