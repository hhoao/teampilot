import 'package:tp_markdown/tp_markdown.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('prepareStreamingMarkdown closes odd fences', () {
    expect(
      prepareStreamingMarkdown('before\n```dart\ncode'),
      'before\n```dart\ncode\n```',
    );
  });

  test('prepareStreamingMarkdown leaves even fences alone', () {
    const raw = 'before\n```\ncode\n```\nafter';
    expect(prepareStreamingMarkdown(raw), raw);
  });

  test('prepareStreamingMarkdown handles indented opening fence', () {
    expect(
      prepareStreamingMarkdown('  ```\npartial'),
      '  ```\npartial\n```',
    );
  });

  test('prepareStreamingMarkdown inserts blank line before heading after html', () {
    // dart markdown otherwise swallows `##` into the HtmlBlock text node
    // (huji README: </div>\\n## 概述), so badges hoist past the heading.
    expect(
      prepareStreamingMarkdown(
        '<div align="center"><img src="a.svg"></div>\n## 概述\n\nhi',
      ),
      '<div align="center"><img src="a.svg"></div>\n\n## 概述\n\nhi',
    );
  });

  test('compileMarkdown keeps heading after html div without blank line', () {
    final doc = compileMarkdown(
      '<div align="center">\n'
      '  <a href="x"><img src="https://img.shields.io/badge/x.svg"></a>\n'
      '</div>\n'
      '## 概述\n'
      '\n'
      'hi\n',
    );
    expect(
      doc.blocks.whereType<HtmlBlock>().any((b) => b.rawHtml.contains('##')),
      isFalse,
      reason: 'heading must not stay inside HtmlBlock',
    );
    expect(
      doc.blocks.whereType<HeadingBlock>().any((h) => h.level == 2),
      isTrue,
    );
    final kinds = doc.blocks.map((b) => b.kind).toList();
    expect(kinds.indexOf(MarkdownBlockKind.html), lessThan(kinds.indexOf(MarkdownBlockKind.heading2)));
  });
}
