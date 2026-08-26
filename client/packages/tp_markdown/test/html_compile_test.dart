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
}
