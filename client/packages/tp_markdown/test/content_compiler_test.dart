import 'package:tp_markdown/tp_markdown.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  bool hasUnsupported(MarkdownDocument doc) =>
      doc.blocks.any((b) => b is RawLiteralBlock);

  test('compiles heading', () {
    final doc = compileMarkdown('## Hello world');
    expect(hasUnsupported(doc), isFalse);
    expect(doc.blocks, hasLength(1));
    expect(doc.blocks.single, isA<HeadingBlock>());
    final h = doc.blocks.single as HeadingBlock;
    expect(h.level, 2);
    expect(h.runs, [const TextRun('Hello world')]);
  });

  test('compiles paragraph with bold and link', () {
    final doc = compileMarkdown(
      'See [link](https://example.com) and **bold**.',
    );
    expect(hasUnsupported(doc), isFalse);
    expect(doc.blocks.single, isA<ParagraphBlock>());
    final runs = (doc.blocks.single as ParagraphBlock).runs;
    expect(runs[0], const TextRun('See '));
    expect(runs[1], isA<LinkRun>());
    final link = runs[1] as LinkRun;
    expect(link.url, 'https://example.com');
    expect(link.children, [const TextRun('link')]);
    expect(runs[2], const TextRun(' and '));
    expect(runs[3], isA<StrongRun>());
    expect((runs[3] as StrongRun).children, [const TextRun('bold')]);
    expect(runs[4], const TextRun('.'));
  });

  test('compiles fenced code block', () {
    final doc = compileMarkdown('```dart\nprint(1);\n```');
    expect(hasUnsupported(doc), isFalse);
    expect(doc.blocks.single, isA<CodeBlock>());
    final code = doc.blocks.single as CodeBlock;
    expect(code.language, 'dart');
    expect(code.text, 'print(1);\n');
  });

  test('compiles indented code block', () {
    final doc = compileMarkdown('    code line\n');
    expect(hasUnsupported(doc), isFalse);
    expect(doc.blocks.single, isA<CodeBlock>());
    final code = doc.blocks.single as CodeBlock;
    expect(code.language, isNull);
    expect(code.text, 'code line\n');
  });

  test('compiles GFM table with bold cell', () {
    final doc = compileMarkdown(
      '| A | B |\n| --- | --- |\n| x | **y** |\n',
    );
    expect(hasUnsupported(doc), isFalse);
    expect(doc.blocks.single, isA<TableBlock>());
    final table = doc.blocks.single as TableBlock;
    expect(table.headers, hasLength(2));
    expect(table.headers[0].runs, [const TextRun('A')]);
    expect(table.headers[1].runs, [const TextRun('B')]);
    expect(table.rows, hasLength(1));
    expect(table.rows.single[0].runs, [const TextRun('x')]);
    expect(table.rows.single[1].runs.single, isA<StrongRun>());
    expect(
      (table.rows.single[1].runs.single as StrongRun).children,
      [const TextRun('y')],
    );
  });

  test('GFM table with image in cell compiles', () {
    final doc = compileMarkdown(
      '| A | B |\n| --- | --- |\n| x | ![alt](x.png) |\n',
    );
    expect(hasUnsupported(doc), isFalse);
    expect(doc.blocks.single, isA<TableBlock>());
    final table = doc.blocks.single as TableBlock;
    expect(table.rows.single[1].runs.single, isA<ImageRun>());
    expect((table.rows.single[1].runs.single as ImageRun).src, 'x.png');
  });

  test('compiles nested list', () {
    final doc = compileMarkdown('- a\n  - b\n');
    expect(hasUnsupported(doc), isFalse);
    expect(doc.blocks.single, isA<ListBlock>());
    final list = doc.blocks.single as ListBlock;
    expect(list.ordered, isFalse);
    expect(list.items, hasLength(1));
    expect(list.items.single.runs, [const TextRun('a')]);
    expect(list.items.single.children, hasLength(1));
    final nested = list.items.single.children.single as ListBlock;
    expect(nested.ordered, isFalse);
    expect(nested.items.single.runs, [const TextRun('b')]);
  });

  test('compiles task list checked and unchecked', () {
    final doc = compileMarkdown('- [x] done\n- [ ] todo\n');
    expect(hasUnsupported(doc), isFalse);
    expect(doc.blocks.single, isA<ListBlock>());
    final list = doc.blocks.single as ListBlock;
    expect(list.items, hasLength(2));
    expect(list.items[0].isTaskChecked, isTrue);
    expect(list.items[0].runs, [const TextRun('done')]);
    expect(list.items[1].isTaskChecked, isFalse);
    expect(list.items[1].runs, [const TextRun('todo')]);
  });

  test('compiles blockquote', () {
    final doc = compileMarkdown('> quoted **text**\n');
    expect(hasUnsupported(doc), isFalse);
    expect(doc.blocks.single, isA<BlockquoteBlock>());
    final quote = doc.blocks.single as BlockquoteBlock;
    expect(quote.blocks.single, isA<ParagraphBlock>());
    final runs = (quote.blocks.single as ParagraphBlock).runs;
    expect(runs[0], const TextRun('quoted '));
    expect(runs[1], isA<StrongRun>());
  });

  test('compiles thematic break', () {
    final doc = compileMarkdown('---\n');
    expect(hasUnsupported(doc), isFalse);
    expect(doc.blocks.single, isA<HorizontalRuleBlock>());
  });

  test('heading with inline image compiles ImageRun', () {
    final doc = compileMarkdown('## Hello ![alt](x.png)');
    expect(hasUnsupported(doc), isFalse);
    expect(doc.blocks.single, isA<HeadingBlock>());
    final runs = (doc.blocks.single as HeadingBlock).runs;
    expect(runs.whereType<ImageRun>(), isNotEmpty);
    expect(runs.whereType<ImageRun>().single.src, 'x.png');
  });

  test('images compile to ImageBlock not RawLiteral', () {
    final doc = compileMarkdown('![alt](x.png)');
    expect(doc.blocks.single, isA<ImageBlock>());
    expect((doc.blocks.single as ImageBlock).src, 'x.png');
    expect((doc.blocks.single as ImageBlock).alt, 'alt');
  });

  test('adjacent image lines without blank line compile to ImageBlocks', () {
    // GFM merges these into one <p> with two <img>s; they must stay block
    // images (README hero screenshots), not tiny inline ImageRuns.
    final doc = compileMarkdown(
      '![a](assets/image.png)\n![b](assets/image1.png)\n',
    );
    expect(doc.blocks, hasLength(2));
    expect(doc.blocks[0], isA<ImageBlock>());
    expect(doc.blocks[1], isA<ImageBlock>());
    expect((doc.blocks[0] as ImageBlock).src, 'assets/image.png');
    expect((doc.blocks[1] as ImageBlock).src, 'assets/image1.png');
  });

  test('inline image in paragraph compiles to ImageRun', () {
    final doc = compileMarkdown('hi ![a](b.png) there');
    final p = doc.blocks.single as ParagraphBlock;
    expect(p.runs.whereType<ImageRun>(), isNotEmpty);
    expect(p.runs.whereType<ImageRun>().single.src, 'b.png');
    expect(p.runs.whereType<ImageRun>().single.alt, 'a');
  });

  test('image inside list item compiles (not RawLiteral)', () {
    final doc = compileMarkdown('- ![a](b.png)');
    expect(doc.blocks.whereType<RawLiteralBlock>(), isEmpty);
    expect(doc.blocks.single, isA<ListBlock>());
    final item = (doc.blocks.single as ListBlock).items.single;
    expect(item.runs.whereType<ImageRun>(), isNotEmpty);
    expect(item.runs.whereType<ImageRun>().single.src, 'b.png');
  });

  test('raw HTML becomes unsupported', () {
    final doc = compileMarkdown('<div>hi</div>\n');
    expect(doc.blocks, isNotEmpty);
    expect(doc.blocks.any((b) => b is RawLiteralBlock), isTrue);
  });
}
