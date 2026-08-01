import 'package:ai_message_ui/ai_message_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final t = MarkdownTokens.test();

  test('gapBetween priority: first / heading next / after heading / paragraphs', () {
    expect(gapBetween(null, MarkdownBlockKind.paragraph, t), 0);
    expect(
      gapBetween(MarkdownBlockKind.paragraph, MarkdownBlockKind.heading2, t),
      t.headingTop(2),
    );
    expect(
      gapBetween(MarkdownBlockKind.heading2, MarkdownBlockKind.list, t),
      t.headingBottom,
    );
    expect(
      gapBetween(MarkdownBlockKind.paragraph, MarkdownBlockKind.paragraph, t),
      t.paragraphGap,
    );
    expect(
      gapBetween(MarkdownBlockKind.paragraph, MarkdownBlockKind.code, t),
      t.blockGap,
    );
  });

  test('h6-sized body tokens do not change gap rules (kind-based only)', () {
    final bodyLike = MarkdownTokens.test();
    expect(bodyLike.h6.fontSize, bodyLike.body.fontSize);
    expect(
      gapBetween(MarkdownBlockKind.paragraph, MarkdownBlockKind.paragraph, bodyLike),
      bodyLike.paragraphGap,
    );
  });

  test('gapBetween covers hr and heading→paragraph', () {
    expect(
      gapBetween(MarkdownBlockKind.paragraph, MarkdownBlockKind.horizontalRule, t),
      t.ruleGap,
    );
    expect(
      gapBetween(MarkdownBlockKind.heading1, MarkdownBlockKind.paragraph, t),
      t.headingBottom,
    );
  });
}
