import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/editor/markdown_http_image_urls.dart';
import 'package:tp_markdown/tp_markdown.dart';

void main() {
  test('collectMarkdownHttpImageUrls finds ImageBlock HtmlBlock and ImageRun', () {
    const doc = MarkdownDocument(
      blocks: [
        ImageBlock(src: 'https://img.shields.io/badge/x.svg'),
        HtmlBlock(
          rawHtml:
              '<a href="https://e.dev"><img src="https://example.com/a.png"></a>',
        ),
        ParagraphBlock(
          runs: [
            ImageRun(src: 'https://cdn.example/b.jpg'),
            TextRun(' local '),
            ImageRun(src: './local.png'),
          ],
        ),
      ],
    );

    final urls = collectMarkdownHttpImageUrls(doc);
    expect(
      urls,
      containsAll([
        'https://img.shields.io/badge/x.png',
        'https://example.com/a.png',
        'https://cdn.example/b.jpg',
      ]),
    );
    expect(urls, isNot(contains('./local.png')));
  });
}
