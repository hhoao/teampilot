import 'package:flutter_test/flutter_test.dart';
import 'package:tp_markdown/src/render/html_sanitizer.dart';

void main() {
  group('sanitizeHtmlDocument', () {
    test('removes script iframe object embed elements', () {
      final doc = sanitizeHtmlDocument(
        '<p>ok</p><script>alert(1)</script>'
        '<iframe src="https://evil.dev"></iframe>'
        '<object data="x"></object><embed src="y">',
      );
      for (final tag in const ['script', 'iframe', 'object', 'embed']) {
        expect(doc.querySelectorAll(tag), isEmpty, reason: tag);
      }
      expect(doc.querySelector('p')!.text, 'ok');
    });

    test('strips event handler attributes', () {
      final doc = sanitizeHtmlDocument(
        '<img src="a.png" onclick="steal()" onerror="boom()">',
      );
      final img = doc.querySelector('img')!;
      expect(img.attributes.containsKey('onclick'), isFalse);
      expect(img.attributes.containsKey('onerror'), isFalse);
      expect(img.attributes['src'], 'a.png');
    });

    test('removes javascript urls', () {
      final doc = sanitizeHtmlDocument(
        '<a href="javascript:alert(1)">x</a>',
      );
      expect(doc.querySelector('a')!.attributes.containsKey('href'), isFalse);
    });

    test('keeps benign markup intact', () {
      final doc = sanitizeHtmlDocument(
        '<details><summary>t</summary><b>b</b></details>',
      );
      expect(doc.querySelectorAll('details'), hasLength(1));
      expect(doc.querySelectorAll('summary'), hasLength(1));
      expect(doc.querySelector('b')!.text, 'b');
    });

    test('removes script-only input that the parser places in head', () {
      final doc = sanitizeHtmlDocument('<script>alert(1)</script>');
      expect(doc.querySelectorAll('script'), isEmpty);
    });

    test('removes scripts in head while keeping body content', () {
      final doc = sanitizeHtmlDocument(
        '<head><script>evil</script></head><body><p>ok</p></body>',
      );
      expect(doc.querySelectorAll('script'), isEmpty);
      expect(doc.querySelector('p')!.text, 'ok');
    });

    test('strips event handlers on the html documentElement', () {
      final doc = sanitizeHtmlDocument(
        '<html onclick="x"><body><p>ok</p></body></html>',
      );
      expect(
        doc.documentElement!.attributes.containsKey('onclick'),
        isFalse,
      );
      expect(doc.querySelector('p')!.text, 'ok');
    });
  });

  group('htmlPlainText', () {
    test('extracts concatenated text', () {
      expect(htmlPlainText('<div>hello <b>world</b></div>'), 'hello world');
    });
  });
}
