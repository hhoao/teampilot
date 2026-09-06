import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart' show Html;
import 'package:flutter_test/flutter_test.dart';
import 'package:tp_markdown/tp_markdown.dart';

/// Stand-in widget for widget-level image resolvers (e.g. flutter_svg).
class _MarkerImage extends StatelessWidget {
  const _MarkerImage({this.id = ''});

  final String id;

  @override
  Widget build(BuildContext context) => SizedBox(
        key: ValueKey<String>('marker-$id'),
        width: 20,
        height: 20,
      );
}

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

  testWidgets('img with buildImageWidget renders the widget not Image', (
    tester,
  ) async {
    await tester.pumpWidget(harness(MarkdownView(
      document: const MarkdownDocument(
        blocks: [HtmlBlock(rawHtml: '<img src="https://example.dev/a.svg">')],
      ),
      tokens: MarkdownTokens.test(),
      resolvers: MarkdownResolvers(
        buildImageWidget: (src, {required inline, required inlineHeight}) =>
            src == 'https://example.dev/a.svg' ? const _MarkerImage() : null,
      ),
    )));

    expect(find.byType(_MarkerImage), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('img with width attribute renders block-sized', (tester) async {
    await tester.pumpWidget(harness(MarkdownView(
      document: const MarkdownDocument(
        blocks: [HtmlBlock(rawHtml: '<p><img src="pic.png" width="300"></p>')],
      ),
      tokens: MarkdownTokens.test(),
      resolvers: MarkdownResolvers(
        resolveImage: (src) => src == 'pic.png' ? testImage : null,
      ),
    )));
    await tester.pumpAndSettle();

    // Hoisted block figure: width hint lands on the Image widget itself
    // (aspect-ratio-correct under unbounded height) and the img is not
    // clamped to the ~19.6px inline line box.
    final img = tester.widget<Image>(find.byType(Image));
    expect(img.width, 300);
    expect(tester.getSize(find.byType(Image)).height, greaterThan(19.6 + 0.1));
  });

  testWidgets('img with style width percentage scales to column', (
    tester,
  ) async {
    await tester.pumpWidget(harness(MarkdownView(
      document: const MarkdownDocument(
        blocks: [
          HtmlBlock(rawHtml: '<p><img src="pic.png" style="width: 70%"></p>'),
        ],
      ),
      tokens: MarkdownTokens.test(),
      resolvers: MarkdownResolvers(
        resolveImage: (src) => src == 'pic.png' ? testImage : null,
      ),
    )));
    await tester.pumpAndSettle();

    // 70% of the full markdown column (hoisted out of the html <p> flow).
    final img = tester.widget<Image>(find.byType(Image));
    expect(img.width, closeTo(560, 2));
  });

  testWidgets('img in p[align=center] is centered', (tester) async {
    await tester.pumpWidget(harness(MarkdownView(
      document: const MarkdownDocument(
        blocks: [
          HtmlBlock(rawHtml: '<p align="center"><img src="pic.png" width="100"></p>'),
        ],
      ),
      tokens: MarkdownTokens.test(),
      resolvers: MarkdownResolvers(
        resolveImage: (src) => src == 'pic.png' ? testImage : null,
      ),
    )));
    await tester.pumpAndSettle();

    // Hoisted row centers via Wrap alignment.
    final wrap = tester.widget<Wrap>(
      find.descendant(
        of: find.byType(MarkdownView),
        matching: find.byType(Wrap),
      ),
    );
    expect(wrap.alignment, WrapAlignment.center);
    final img = tester.widgetList<Image>(find.byType(Image)).first;
    expect(img.width, 100);
  });

  testWidgets('widget-hook img with sizing is not line-clamped', (
    tester,
  ) async {
    bool? sawInline;
    await tester.pumpWidget(harness(MarkdownView(
      document: const MarkdownDocument(
        blocks: [HtmlBlock(rawHtml: '<img src="a.svg" width="120">')],
      ),
      tokens: MarkdownTokens.test(),
      resolvers: MarkdownResolvers(
        buildImageWidget: (src, {required inline, required inlineHeight}) {
          sawInline = inline;
          return const _MarkerImage();
        },
      ),
    )));
    await tester.pumpAndSettle();

    expect(sawInline, isFalse);
    final ctx = tester.element(find.byType(_MarkerImage));
    final box = ctx.findAncestorWidgetOfExactType<SizedBox>();
    expect(box?.width, 120);
    // Unclamped height: the marker keeps its 20px, not a 19.6 line box.
    expect(tester.getSize(find.byType(_MarkerImage)).height, 20);
  });

  testWidgets('unsized badge imgs stay inline (line-height)', (tester) async {
    await tester.pumpWidget(harness(MarkdownView(
      document: const MarkdownDocument(
        blocks: [
          HtmlBlock(
            rawHtml:
                '<div align="center"><a href="https://e.dev"><img src="https://e.dev/b.svg"></a></div>',
          ),
        ],
      ),
      tokens: MarkdownTokens.test(),
      resolvers: MarkdownResolvers(
        resolveImage: (src) => src == 'https://e.dev/b.svg' ? testImage : null,
      ),
    )));
    await tester.pumpAndSettle();

    final size = tester.getSize(find.byType(Image));
    expect(size.height, closeTo(14 * 1.4, 0.1));
  });

  testWidgets('unsized local cover img stays block-sized', (tester) async {
    // README covers: <p align=center><img src="assets/cover.png"></p> with no
    // width hint — must not be crushed to the ~20px badge line box.
    await tester.pumpWidget(harness(MarkdownView(
      document: const MarkdownDocument(
        blocks: [
          HtmlBlock(
            rawHtml: '<p align="center"><img src="assets/cover.png" alt="cover"></p>',
          ),
        ],
      ),
      tokens: MarkdownTokens.test(),
      resolvers: MarkdownResolvers(
        resolveImage: (src) => src == 'assets/cover.png' ? testImage : null,
      ),
    )));
    await tester.pump();

    // Block path: Image has no explicit height (inline badges get a SizedBox
    // line-height clamp).
    final img = tester.widget<Image>(find.byType(Image));
    expect(img.height, isNull);
    final sized = find.ancestor(
      of: find.byType(Image),
      matching: find.byWidgetPredicate(
        (w) => w is SizedBox && w.height != null && w.height! < 22,
      ),
    );
    expect(sized, findsNothing, reason: 'must not wrap in a line-height SizedBox');
  });

  testWidgets('sibling imgs with width hints render on one row', (
    tester,
  ) async {
    await tester.pumpWidget(harness(MarkdownView(
      document: const MarkdownDocument(
        blocks: [
          HtmlBlock(
            rawHtml:
                '<p align="center"><img src="a.png" style="width: 70%">'
                '<img src="b.png" style="width: 19%"></p>',
          ),
        ],
      ),
      tokens: MarkdownTokens.test(),
      resolvers: MarkdownResolvers(
        resolveImage: (src) => testImage,
      ),
    )));
    await tester.pumpAndSettle();

    // Both imgs share one Wrap row (GitHub-like inline pairing), each with
    // its own width hint.
    final wrap = find.descendant(
      of: find.byType(MarkdownView),
      matching: find.byType(Wrap),
    );
    expect(wrap, findsOneWidget);
    final images = tester.widgetList<Image>(find.byType(Image)).toList();
    expect(images.length, 2);
    // Same Wrap run: B sits right of A (cross-axis centered between the
    // differing heights), not below it.
    final a = tester.getTopLeft(find.byWidget(images.first));
    final b = tester.getTopLeft(find.byWidget(images.last));
    expect(b.dx, greaterThan(a.dx), reason: 'both imgs on the same row');
    expect(b.dy, lessThan(a.dy + tester.getSize(find.byWidget(images.first)).height),
        reason: 'b vertically within the row extent');

    expect(images.first.width, closeTo(560, 2));
    expect(images.last.width, closeTo(800 * 0.19, 2));
  });

  testWidgets('linked badge siblings share centered Wrap rows', (
    tester,
  ) async {
    // README pattern: each badge is <a><img></a>, not a bare <img> child.
    // <br> starts a second run (GitHub badge rows).
    await tester.pumpWidget(harness(MarkdownView(
      document: const MarkdownDocument(
        blocks: [
          HtmlBlock(
            rawHtml: '''
<div align="center">
  <a href="https://e.dev/1"><img src="https://e.dev/a.svg" alt="A"></a>
  <a href="https://e.dev/2"><img src="https://e.dev/b.svg" alt="B"></a>
  <br>
  <a href="https://e.dev/3"><img src="https://e.dev/c.svg" alt="C"></a>
</div>
''',
          ),
        ],
      ),
      tokens: MarkdownTokens.test(),
      resolvers: MarkdownResolvers(
        buildImageWidget: (src, {required inline, required inlineHeight}) =>
            _MarkerImage(id: src),
      ),
    )));
    await tester.pumpAndSettle();

    final wraps = find.descendant(
      of: find.byType(MarkdownView),
      matching: find.byType(Wrap),
    );
    // Two Wrap rows from the <br>, not one Wrap per <a>.
    expect(wraps, findsNWidgets(2));
    expect(
      tester.widgetList<Wrap>(wraps).every((w) => w.alignment == WrapAlignment.center),
      isTrue,
    );
    expect(find.byType(_MarkerImage), findsNWidgets(3));

    final a = tester.getTopLeft(find.byKey(const ValueKey('marker-https://e.dev/a.svg')));
    final b = tester.getTopLeft(find.byKey(const ValueKey('marker-https://e.dev/b.svg')));
    final c = tester.getTopLeft(find.byKey(const ValueKey('marker-https://e.dev/c.svg')));
    expect(b.dx, greaterThan(a.dx), reason: 'first-row badges share a line');
    expect(c.dy, greaterThan(a.dy), reason: 'post-<br> badge is on the next row');
  });

  testWidgets('nav links then badge div keep a tight gap', (tester) async {
    // README pattern: one HtmlBlock contains both the centered nav <p> and the
    // badge <div>. After hoist the empty <div><br></div> must not leave a
    // multi-line hole under the links.
    await tester.pumpWidget(harness(MarkdownView(
      document: const MarkdownDocument(
        blocks: [
          HtmlBlock(
            rawHtml: '''
<p align="center">
  <a href="README.zh.md">简体中文</a> •
  <a href="#core-features">Core Features</a>
</p>
<div align="center">
  <a href="https://e.dev/1"><img src="https://e.dev/a.svg" alt="A"></a>
  <br>
  <a href="https://e.dev/2"><img src="https://e.dev/b.svg" alt="B"></a>
</div>
''',
          ),
        ],
      ),
      tokens: MarkdownTokens.test(),
      resolvers: MarkdownResolvers(
        buildImageWidget: (src, {required inline, required inlineHeight}) =>
            _MarkerImage(id: src),
      ),
    )));
    await tester.pumpAndSettle();

    expect(find.textContaining('简体中文'), findsOneWidget);
    expect(find.byType(_MarkerImage), findsNWidgets(2));

    final navBottom = tester.getBottomLeft(find.textContaining('简体中文')).dy;
    final badgeTop = tester
        .getTopLeft(find.byKey(const ValueKey('marker-https://e.dev/a.svg')))
        .dy;
    final gap = badgeTop - navBottom;
    expect(gap, greaterThanOrEqualTo(4));
    expect(gap, lessThan(24), reason: 'nav→badge gap was $gap (empty shell / p margin)');
  });

  testWidgets('hoisted imgs leave no object-replacement glyph', (tester) async {
    await tester.pumpWidget(harness(MarkdownView(
      document: const MarkdownDocument(
        blocks: [
          HtmlBlock(
            rawHtml:
                '<div align="center">'
                '<a href="https://e.dev"><img src="https://e.dev/a.svg"></a>'
                '<a href="https://e.dev"><img src="https://e.dev/b.svg"></a>'
                '</div>',
          ),
        ],
      ),
      tokens: MarkdownTokens.test(),
      resolvers: MarkdownResolvers(
        buildImageWidget: (src, {required inline, required inlineHeight}) =>
            const _MarkerImage(),
      ),
    )));
    await tester.pumpAndSettle();

    final text = _plainText(tester);
    // U+FFFC renders as a boxed "OBJ" glyph when left in the html flow.
    expect(text.contains('\u{FFFC}'), isFalse);
    expect(text.toUpperCase().contains('OBJ'), isFalse);
    expect(find.byType(_MarkerImage), findsNWidgets(2));
  });

  testWidgets('badge row in div[align=center] centers its Wrap', (
    tester,
  ) async {
    await tester.pumpWidget(harness(MarkdownView(
      document: const MarkdownDocument(
        blocks: [
          HtmlBlock(
            rawHtml:
                '<div align="center"><a href="https://e.dev"><img src="https://e.dev/b.svg"></a></div>',
          ),
        ],
      ),
      tokens: MarkdownTokens.test(),
      resolvers: MarkdownResolvers(
        resolveImage: (src) => src == 'https://e.dev/b.svg' ? testImage : null,
      ),
    )));
    await tester.pumpAndSettle();

    final wrap = tester.widget<Wrap>(
      find.descendant(
        of: find.byType(MarkdownView),
        matching: find.byType(Wrap),
      ),
    );
    expect(wrap.alignment, WrapAlignment.center);
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
