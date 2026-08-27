import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart' show Html;
import 'package:flutter_test/flutter_test.dart';
import 'package:tp_markdown/tp_markdown.dart';

String _plainText(WidgetTester tester) => tester
    .widgetList<RichText>(find.byType(RichText))
    .map((r) => r.text.toPlainText())
    .join();

void main() {
  final testImage = MemoryImage(
    base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
    ),
  );

  Widget harness(Widget child) =>
      MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child)));

  bool hasSpanWithWeight(List<InlineSpan> spans, FontWeight weight) =>
      spans.any((span) {
        if (span is! TextSpan) return false;
        if (span.style?.fontWeight == weight) return true;
        return hasSpanWithWeight(span.children ?? const [], weight);
      });

  testWidgets('renders inline tags as styled spans', (tester) async {
    await tester.pumpWidget(harness(MarkdownView(
      document: const MarkdownDocument(
        blocks: [HtmlBlock(rawHtml: '<p>hi <b>bold</b> ok</p>')],
      ),
      tokens: MarkdownTokens.test(),
    )));

    expect(_plainText(tester), contains('bold'));
    final richTexts = tester.widgetList<RichText>(find.byType(RichText));
    expect(
      richTexts.any((r) => hasSpanWithWeight([r.text], FontWeight.w700)),
      isTrue,
      reason: 'the <b> span must carry strongWeight from tokens',
    );
  });

  testWidgets('link tap routes through resolvers.onLinkTap', (tester) async {
    String? tapped;
    await tester.pumpWidget(harness(MarkdownView(
      document: const MarkdownDocument(
        blocks: [HtmlBlock(rawHtml: '<a href="https://example.dev">go</a>')],
      ),
      tokens: MarkdownTokens.test(),
      resolvers: MarkdownResolvers(onLinkTap: (href) => tapped = href),
    )));

    await tester.tapOnText(find.textRange.ofSubstring('go'));
    await tester.pumpAndSettle();
    expect(tapped, 'https://example.dev');
  });

  testWidgets('img resolves through resolvers.resolveImage', (tester) async {
    await tester.pumpWidget(harness(MarkdownView(
      document: const MarkdownDocument(
        blocks: [HtmlBlock(rawHtml: '<img src="pic.png">')],
      ),
      tokens: MarkdownTokens.test(),
      resolvers: MarkdownResolvers(
        resolveImage: (src) => src == 'pic.png' ? testImage : null,
      ),
    )));

    expect(find.byType(Image), findsOneWidget);
    expect(tester.widget<Image>(find.byType(Image)).image, testImage);
  });

  testWidgets('relative img without resolveImage shows the placeholder',
      (tester) async {
    await tester.pumpWidget(harness(MarkdownView(
      document: const MarkdownDocument(
        blocks: [HtmlBlock(rawHtml: '<img src="docs/pic.png">')],
      ),
      tokens: MarkdownTokens.test(),
    )));

    expect(find.byIcon(Icons.image_outlined), findsOneWidget);
    expect(_plainText(tester), contains('docs/pic.png'));
  });

  testWidgets('https img without resolveImage falls through to flutter_html',
      (tester) async {
    await tester.pumpWidget(harness(MarkdownView(
      document: const MarkdownDocument(
        blocks: [HtmlBlock(rawHtml: '<img src="https://example.dev/a.png">')],
      ),
      tokens: MarkdownTokens.test(),
    )));

    expect(find.byType(Html), findsOneWidget);
    expect(find.byIcon(Icons.image_outlined), findsNothing);
  });

  testWidgets('malformed HTML still renders without throwing', (tester) async {
    await tester.pumpWidget(harness(MarkdownView(
      document: const MarkdownDocument(
        blocks: [HtmlBlock(rawHtml: '<p>unclosed <b>x')],
      ),
      tokens: MarkdownTokens.test(),
    )));

    expect(_plainText(tester), contains('x'));
  });

  testWidgets('script content never reaches the widget tree', (tester) async {
    await tester.pumpWidget(harness(MarkdownView(
      document: const MarkdownDocument(
        blocks: [HtmlBlock(rawHtml: '<p>ok</p><script>alert(1)</script>')],
      ),
      tokens: MarkdownTokens.test(),
    )));

    expect(_plainText(tester), contains('ok'));
    expect(_plainText(tester), isNot(contains('alert')));
  });

  testWidgets('sanitized-empty block collapses to nothing', (tester) async {
    await tester.pumpWidget(harness(MarkdownView(
      document: const MarkdownDocument(
        blocks: [HtmlBlock(rawHtml: '<script>x</script>')],
      ),
      tokens: MarkdownTokens.test(),
    )));

    expect(find.byType(Html), findsNothing);
  });

  testWidgets('unknown wrapping tag keeps inner text', (tester) async {
    await tester.pumpWidget(harness(MarkdownView(
      document: const MarkdownDocument(
        blocks: [HtmlBlock(rawHtml: '<think>keep this text</think>')],
      ),
      tokens: MarkdownTokens.test(),
    )));

    expect(_plainText(tester), contains('keep this text'));
  });

  testWidgets('unknown inline tag keeps surrounding text', (tester) async {
    await tester.pumpWidget(harness(MarkdownView(
      document: const MarkdownDocument(
        blocks: [HtmlBlock(rawHtml: 'hello <foo>bar</foo> world')],
      ),
      tokens: MarkdownTokens.test(),
    )));

    final text = _plainText(tester);
    expect(text, contains('hello'));
    expect(text, contains('bar'));
    expect(text, contains('world'));
  });

  testWidgets('VirtualMarkdownView renders HtmlBlock lazily', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: VirtualMarkdownView(
            document: const MarkdownDocument(
              blocks: [HtmlBlock(rawHtml: '<p>virtual html</p>')],
            ),
            tokens: MarkdownTokens.test(),
            flatten: true,
          ),
        ),
      ),
    ));

    expect(_plainText(tester), contains('virtual html'));
  });
}
