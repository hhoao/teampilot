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
}
