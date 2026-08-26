import 'package:flutter_test/flutter_test.dart';
import 'package:tp_markdown/tp_markdown.dart';

void main() {
  setUp(clearMessageContentCache);

  test('top-level bare HTML text compiles to HtmlBlock', () {
    final doc = compileMarkdown('<div>hi</div>\n');
    expect(doc.blocks.single, isA<HtmlBlock>());
    final html = doc.blocks.single as HtmlBlock;
    expect(html.rawHtml, contains('<div>'));
    expect(html.rawHtml, contains('hi'));
  });

  test('paragraph with unsupported inline tag compiles to HtmlBlock', () {
    final doc = compileMarkdown('hello <u>world</u>');
    expect(doc.blocks.single, isA<HtmlBlock>());
  });

  test('list item with unsupported inline tag yields child HtmlBlock', () {
    final doc = compileMarkdown('- a <sub>x</sub>');
    expect(doc.blocks.single, isA<ListBlock>());
    final item = (doc.blocks.single as ListBlock).items.single;
    expect(item.children.single, isA<HtmlBlock>());
  });

  test('task-list checkboxes still compile to ListBlock', () {
    final doc = compileMarkdown('- [x] done\n');
    expect(doc.blocks.single, isA<ListBlock>());
    expect((doc.blocks.single as ListBlock).items.single.isTaskChecked, isTrue);
  });

  test('heading with unsupported inline stays RawLiteralBlock', () {
    final doc = compileMarkdown('# hi <u>x</u>');
    final block = doc.blocks.single;
    expect(block, isA<RawLiteralBlock>());
    expect((block as RawLiteralBlock).rawMarkdown, startsWith('#'));
  });

  test('table with unsupported inline stays RawLiteralBlock', () {
    final doc = compileMarkdown('| A <u>x</u> |\n| --- |\n| b |\n');
    expect(doc.blocks.single, isA<RawLiteralBlock>());
  });

  test('comparison-shaped prose stays a plain paragraph', () {
    // Boundary of `_looksLikeHtml`: `<` not directly followed by a letter is
    // not a tag, so inequality text must keep its rich runs.
    final doc = compileMarkdown('5 < 6 and 3 > 2');
    expect(doc.blocks.single, isA<ParagraphBlock>());
    expect((doc.blocks.single as ParagraphBlock).runs, [
      const TextRun('5 < 6 and 3 > 2'),
    ]);
  });

  test('tag shape inside inline code stays a plain paragraph', () {
    // Inline code is opaque literal text and never counts as raw HTML.
    final doc = compileMarkdown('wrap it in `<div>` please');
    expect(doc.blocks.single, isA<ParagraphBlock>());
    final runs = (doc.blocks.single as ParagraphBlock).runs;
    expect(runs.whereType<CodeRun>().single.text, '<div>');
  });

  test('embedded tag demotes the whole paragraph verbatim', () {
    // Deliberate widening: a `<tag>` shape anywhere in the text demotes the
    // paragraph to an HtmlBlock carrying the markup verbatim.
    final doc = compileMarkdown('compare <b> sizes');
    final block = doc.blocks.single;
    expect(block, isA<HtmlBlock>());
    expect((block as HtmlBlock).rawHtml, contains('<b>'));
  });

  test('heading with embedded tag stays RawLiteralBlock source text', () {
    // The widening also feeds heading demotion; that path keeps source-text
    // rendering because reconstruction injects GFM syntax.
    final doc = compileMarkdown('# Use <em> sparingly');
    final block = doc.blocks.single;
    expect(block, isA<RawLiteralBlock>());
    expect((block as RawLiteralBlock).rawMarkdown, '# Use <em> sparingly');
  });
}
