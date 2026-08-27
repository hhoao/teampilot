import 'package:flutter_test/flutter_test.dart';
import 'package:tp_markdown/tp_markdown.dart';

void main() {
  test('HtmlBlock kind and equality', () {
    const block = HtmlBlock(rawHtml: '<div>hi</div>');
    expect(block.kind, MarkdownBlockKind.html);
    expect(block, const HtmlBlock(rawHtml: '<div>hi</div>'));
    expect(block.hashCode, const HtmlBlock(rawHtml: '<div>hi</div>').hashCode);
    expect(block, isNot(const HtmlBlock(rawHtml: '<b>x</b>')));
  });

  test('html block margins follow paragraph rhythm', () {
    final tokens = MarkdownTokens.test();
    expect(
      tokens.marginOf(MarkdownBlockKind.html),
      tokens.marginOf(MarkdownBlockKind.paragraph),
    );
  });
}
