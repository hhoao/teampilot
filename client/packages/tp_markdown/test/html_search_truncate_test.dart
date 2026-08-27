import 'package:flutter_test/flutter_test.dart';
import 'package:tp_markdown/tp_markdown.dart';

void main() {
  setUp(clearMessageContentCache);

  test('search finds plain text inside HtmlBlock', () {
    final doc = compileMarkdown('before\n\n<div>needle text</div>\n');
    final index = MarkdownSearchIndex.of(doc);
    final hits = index.search(const MarkdownSearchQuery(pattern: 'needle'));
    expect(hits, hasLength(1));
    expect(index.containers[hits.single.container].blockIndex, 1);
  });

  test('truncation estimates HtmlBlock by raw length', () {
    final longHtml = '<div>${'x' * 500}</div>';
    final doc = compileMarkdown('$longHtml\n\nshort tail');
    final result = truncateMessageContent(
      doc,
      budget: const ContentCollapseBudget(maxChars: 100),
    );
    expect(result.wasTruncated, isTrue);
  });
}
