import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tp_markdown/tp_markdown.dart';

void main() {
  test('gapBetween collapses adjacent vertical margins', () {
    final t = MarkdownTokens.test(
      paragraphMargin: const EdgeInsets.only(bottom: 16),
      h2Margin: const EdgeInsets.only(top: 36, bottom: 8),
    );
    expect(gapBetween(null, MarkdownBlockKind.paragraph, t), 0);
    expect(
      gapBetween(MarkdownBlockKind.paragraph, MarkdownBlockKind.heading2, t),
      36, // max(16, 36)
    );
    expect(
      gapBetween(MarkdownBlockKind.heading2, MarkdownBlockKind.list, t),
      8, // max(8, 0)
    );
    expect(
      gapBetween(MarkdownBlockKind.paragraph, MarkdownBlockKind.paragraph, t),
      16, // max(16, 0)
    );
    expect(
      gapBetween(MarkdownBlockKind.paragraph, MarkdownBlockKind.code, t),
      16,
    );
    expect(
      gapBetween(MarkdownBlockKind.heading1, MarkdownBlockKind.paragraph, t),
      8, // default h1 bottom
    );
  });

  test('gapBetween covers hr and heading→heading', () {
    final t = MarkdownTokens.test(
      paragraphMargin: const EdgeInsets.only(bottom: 16),
      horizontalRuleMargin: const EdgeInsets.only(bottom: 28),
      h1Margin: const EdgeInsets.only(top: 40, bottom: 8),
      h2Margin: const EdgeInsets.only(top: 36, bottom: 8),
    );
    expect(
      gapBetween(MarkdownBlockKind.paragraph, MarkdownBlockKind.horizontalRule, t),
      16,
    );
    expect(
      gapBetween(MarkdownBlockKind.heading1, MarkdownBlockKind.heading2, t),
      36, // max(8, 36)
    );
  });
}
