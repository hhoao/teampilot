# Markdown HTML Block Rendering Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Render raw HTML regions in markdown (chat AI messages + workbench preview) via a new `HtmlBlock` IR node rendered by flutter_html, styled from `MarkdownTokens`.

**Architecture:** `tp_markdown` compiles GFM → style-free IR (`MarkdownDocument`) → kind-based widgets. Three compiler demotion paths that today emit `RawLiteralBlock` (monospace source text) will emit the new `HtmlBlock`, rendered by an `Html(fromDom:)` widget registered in `BlockWidgetRegistry.builtIn()`. Demotion paths whose fallback reconstruction injects GFM syntax (tables, headings) keep `RawLiteralBlock` because the html engine cannot parse reconstructed GFM. Zero app-side changes: all `MarkdownView` / `VirtualMarkdownView` construction sites use the default registry.

**Tech Stack:** Flutter, Dart `markdown` ^7.3.0, `flutter_html` **3.0.0** (pinned — API verified against this exact version), `html` ^0.15.5.

**Spec:** `docs/superpowers/specs/2026-08-26-markdown-html-block-rendering-design.md`

## Global Constraints

- All work inside `client/packages/tp_markdown/`; no `client/lib` changes required or allowed.
- Package dependencies must stay exactly: `flutter`, `markdown: ^7.3.0`, `flutter_html: 3.0.0`, `html: ^0.15.5`.
- flutter_html is pinned to exact `3.0.0`; its verified API surface used here:
  - `Html.fromDom({required dom.Document? document, Map<String, Style> style, List<HtmlExtension> extensions, OnTap? onLinkTap})`
  - `typedef OnTap = void Function(String? url, Map<String, String> attributes, dom.Element? element)`
  - `Style` fields: `fontSize: FontSize?` (`FontSize(px)` positional), `lineHeight: LineHeight?` (`const LineHeight(size, units:)`), `color`, `backgroundColor`, `fontFamily`, `fontWeight`
  - Custom images: subclass `HtmlExtension` (extensions run before built-ins; unmatched tags fall through to `ImageBuiltIn` which handles http(s)/data URIs)
  - Sanitizer uses `Html.fromDom` — never serialize DOM back to string
- Sanitization is mandatory before any render: strip `script`/`iframe`/`object`/`embed` elements, `on*` attributes, `javascript:`/`vbscript:` URLs.
- Compile rule from spec: only non-GFM-injecting demotion paths become `HtmlBlock`.
- Task-list `<input type=checkbox>` exemption in `_hasUnsupportedInline` / `_compileListItem` must keep working.
- Test commands run from `client/packages/tp_markdown/`: `flutter test <file>` and full `flutter test`. Final gate from repo root: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && dart run tool/run_tests.dart`.
- Follow package code style: `final class`, exhaustive `switch` expressions, doc comments on public members.
- Commit after every task; message prefix `feat(tp_markdown):` / `test(tp_markdown):`.

## Verified file map (current line numbers)

| File | Role | Key anchors |
|---|---|---|
| `lib/src/ir/markdown_block_kind.dart` | kind enum | append `html` |
| `lib/src/ir/markdown_document.dart` | IR classes | `RawLiteralBlock` at :224 |
| `lib/src/compile/content_compiler.dart` | demotion paths | :70-72 top-level text, :102-105 p, :93-95 heading (keep), :169-173 li>p, :181-186 li child, :220-222 table (keep) |
| `lib/src/tokens/markdown_tokens.dart` | tokens | `marginOf` exhaustive switch :193-209 |
| `lib/src/search/markdown_search_index.dart` | search projection | skip case :164, `search()` API :191 |
| `lib/src/compile/content_truncate.dart` | truncation estimate | `_estimateBlockChars` RawLiteral case :174 |
| `lib/src/registry/block_widget_registry.dart` | built-in builders | `register<RawLiteralBlock>` :125 |
| `lib/tp_markdown.dart` | exports | export list |

---

### Task 1: Dependencies + `HtmlBlock` IR node

**Files:**
- Modify: `client/packages/tp_markdown/pubspec.yaml`
- Modify: `client/packages/tp_markdown/lib/src/ir/markdown_block_kind.dart`
- Modify: `client/packages/tp_markdown/lib/src/ir/markdown_document.dart` (after `RawLiteralBlock`, :239)
- Modify: `client/packages/tp_markdown/lib/src/tokens/markdown_tokens.dart:208` (marginOf switch)
- Test: create `client/packages/tp_markdown/test/html_ir_test.dart`

**Interfaces:**
- Consumes: existing `MarkdownBlock` sealed class, `MarkdownBlockKind`.
- Produces: `final class HtmlBlock extends MarkdownBlock { const HtmlBlock({required String rawHtml}); final String rawHtml; MarkdownBlockKind get kind => MarkdownBlockKind.html; }` — later tasks construct `HtmlBlock(rawHtml: …)` and match `MarkdownBlockKind.html`.

- [ ] **Step 1: Write the failing test**

Create `client/packages/tp_markdown/test/html_ir_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:tp_markdown/tp_markdown.dart';

void main() {
  test('HtmlBlock kind and equality', () {
    const block = HtmlBlock(rawHtml: '<div>hi</div>');
    expect(block.kind, MarkdownBlockKind.html);
    expect(block, const HtmlBlock(rawHtml: '<div>hi</div>'));
    expect(block.hashCode, const HtmlBlock(rawHtml: '<div>hi</div>').hashCode);
    expect(block, isNot(const HtmlBlock(rawHtml: '<b>x</b>')));
  });

  test('html block margins follow paragraph rhythm', () {
    final tokens = MarkdownTokens.test();
    expect(
      tokens.marginOf(MarkdownBlockKind.html),
      tokens.marginOf(MarkdownBlockKind.paragraph),
    );
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client/packages/tp_markdown && flutter test test/html_ir_test.dart`
Expected: FAIL — compile errors "HtmlBlock isn't defined" and/or enum value `html` missing.

- [ ] **Step 3: Add dependencies**

Edit `client/packages/tp_markdown/pubspec.yaml` dependencies section to exactly:

```yaml
dependencies:
  flutter:
    sdk: flutter
  markdown: ^7.3.0
  flutter_html: 3.0.0
  html: ^0.15.5
```

Then run: `cd client/packages/tp_markdown && flutter pub get`
Expected: resolves successfully (flutter_html 3.0.0 + html 0.15.x are on the configured mirror). If pub get fails offline, STOP and report — everything else depends on this.

- [ ] **Step 4: Add enum value + IR class + marginOf case**

`markdown_block_kind.dart` — append `html` as the last value:

```dart
enum MarkdownBlockKind {
  paragraph,
  heading1,
  heading2,
  heading3,
  heading4,
  heading5,
  heading6,
  list,
  blockquote,
  code,
  table,
  horizontalRule,
  image,
  rawLiteral,
  html,
}
```

`markdown_document.dart` — append after `RawLiteralBlock` (before `InlineDocument`):

```dart
/// Raw HTML region rendered by an embedded html engine (flutter_html).
///
/// Produced for demotion paths that carry verbatim markup (see
/// `content_compiler.dart`); paths whose fallback reconstruction injects GFM
/// syntax stay [RawLiteralBlock].
final class HtmlBlock extends MarkdownBlock {
  const HtmlBlock({required this.rawHtml});

  final String rawHtml;

  @override
  MarkdownBlockKind get kind => MarkdownBlockKind.html;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HtmlBlock && rawHtml == other.rawHtml;

  @override
  int get hashCode => rawHtml.hashCode;
}
```

`markdown_tokens.dart` `marginOf` — add the case after `rawLiteral => rawLiteralMargin,`:

```dart
      MarkdownBlockKind.rawLiteral => rawLiteralMargin,
      // HTML blocks inherit the paragraph rhythm so surrounding gaps match.
      MarkdownBlockKind.html => paragraphMargin,
```

- [ ] **Step 5: Run analyzer + tests**

Run: `cd client/packages/tp_markdown && flutter analyze && flutter test`
Expected: analyze clean (if any other exhaustive switch over `MarkdownBlockKind` surfaces an error, add `MarkdownBlockKind.html => <paragraph-equivalent case>` there too); all tests PASS including new `html_ir_test`.

- [ ] **Step 6: Commit**

```bash
git add client/packages/tp_markdown/pubspec.yaml client/packages/tp_markdown/pubspec.lock \
  client/packages/tp_markdown/lib/src/ir/markdown_block_kind.dart \
  client/packages/tp_markdown/lib/src/ir/markdown_document.dart \
  client/packages/tp_markdown/lib/src/tokens/markdown_tokens.dart \
  client/packages/tp_markdown/test/html_ir_test.dart
git commit -m "feat(tp_markdown): add HtmlBlock IR node and html block kind"
```

---

### Task 2: Compiler routes HTML demotion paths to HtmlBlock

**Files:**
- Modify: `client/packages/tp_markdown/lib/src/compile/content_compiler.dart` (4 sites)
- Modify: `client/packages/tp_markdown/test/content_compiler_test.dart:173-177` (existing raw-HTML expectation)
- Test: create `client/packages/tp_markdown/test/html_compile_test.dart`

**Interfaces:**
- Consumes: `HtmlBlock` from Task 1.
- Produces: compile behavior — top-level bare HTML text, `<p>` inline demotion, list-item inline demotion (both the direct-child and the leading-`<p>` sites) yield `HtmlBlock(rawHtml: _reconstructUnsupported(...))`; heading/table demotion unchanged (`RawLiteralBlock`). `_reconstructUnsupported` signature unchanged.

- [ ] **Step 1: Write the failing tests**

Create `client/packages/tp_markdown/test/html_compile_test.dart`:

```dart
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
```

Also update the last test in `content_compiler_test.dart` ('raw HTML becomes unsupported') — behavior intentionally changed:

```dart
  test('raw HTML becomes HtmlBlock', () {
    final doc = compileMarkdown('<div>hi</div>\n');
    expect(doc.blocks, isNotEmpty);
    expect(doc.blocks.any((b) => b is HtmlBlock), isTrue);
  });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd client/packages/tp_markdown && flutter test test/html_compile_test.dart test/content_compiler_test.dart`
Expected: FAIL — first four new tests fail (blocks are `RawLiteralBlock` today); the two "stays RawLiteralBlock" tests already pass; updated content_compiler_test fails until Step 3.

- [ ] **Step 3: Route the four demotion sites**

In `content_compiler.dart`:

1. Top-level text branch (`_compileTopLevelNode`, ~:70-72):

```dart
    if (_looksLikeHtml(text)) {
      return HtmlBlock(rawHtml: text);
    }
```

2. `<p>` demotion (`_compileElement` 'p' case, ~:102-105):

```dart
    case 'p':
      // Image-only paragraphs are expanded in [_compileTopLevelBlocks].
      if (_hasUnsupportedInline(element.children)) {
        return HtmlBlock(rawHtml: _reconstructUnsupported(element));
      }
```

3. Heading demotion (~:93-95) — KEEP `RawLiteralBlock`, add reason comment:

```dart
      if (_hasUnsupportedInline(element.children)) {
        // Reconstruction injects '#'-prefix GFM syntax the html engine cannot
        // parse — keep source-text rendering.
        return RawLiteralBlock(rawMarkdown: _reconstructUnsupported(element));
      }
```

4. Table demotion (~:220-222) — KEEP `RawLiteralBlock`, same comment style about injected `| --- |` rows.

5. `_compileListItem` — both sites become `HtmlBlock`:

```dart
        if (_hasUnsupportedInline(child.children)) {
          children.add(
            HtmlBlock(rawHtml: _reconstructUnsupported(child)),
          );
        } else {
          runs.addAll(_compileInlines(child.children));
        }
        continue;
      }
      children.addAll(_compileTopLevelBlocks(child));
      continue;
    }
    if (_hasUnsupportedInline([child])) {
      children.add(
        HtmlBlock(rawHtml: _reconstructUnsupported(child)),
      );
      continue;
    }
```

(Only change `RawLiteralBlock(` → `HtmlBlock(rawHtml:` at those two spots; leave surrounding structure untouched.)

- [ ] **Step 4: Run package tests**

Run: `cd client/packages/tp_markdown && flutter test`
Expected: ALL PASS. If `markdown_corpus_gate_test.dart` fails, inspect the failing fixture: it counts `RawLiteralBlock` as unsupported, so counts can only drop; adjust any fixture's expected count downward only when its diff is exactly raw-HTML regions now compiling to `HtmlBlock`.

- [ ] **Step 5: Commit**

```bash
git add client/packages/tp_markdown/lib/src/compile/content_compiler.dart \
  client/packages/tp_markdown/test/html_compile_test.dart \
  client/packages/tp_markdown/test/content_compiler_test.dart
# include corpus fixture changes if any were required
git commit -m "feat(tp_markdown): compile raw HTML regions to HtmlBlock"
```

---

### Task 3: HTML sanitizer (DOM scrub + plain text)

**Files:**
- Create: `client/packages/tp_markdown/lib/src/render/html_sanitizer.dart`
- Test: create `client/packages/tp_markdown/test/html_sanitizer_test.dart`

**Interfaces:**
- Consumes: `package:html` parser (added in Task 1).
- Produces (used by Tasks 4–5):
  - `dom.Document sanitizeHtmlDocument(String rawHtml)` — parses and strips dangerous markup, returns DOM document (parser wraps input in html/body).
  - `String htmlPlainText(String rawHtml)` — plain text of parsed HTML (for search indexing).

- [ ] **Step 1: Write the failing tests**

Create `client/packages/tp_markdown/test/html_sanitizer_test.dart`:

```dart
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
  });

  group('htmlPlainText', () {
    test('extracts concatenated text', () {
      expect(htmlPlainText('<div>hello <b>world</b></div>'), 'hello world');
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd client/packages/tp_markdown && flutter test test/html_sanitizer_test.dart`
Expected: FAIL — `html_sanitizer.dart` does not exist.

- [ ] **Step 3: Implement sanitizer**

Create `client/packages/tp_markdown/lib/src/render/html_sanitizer.dart`:

```dart
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

/// Elements removed outright before rendering untrusted HTML.
const Set<String> _removedElements = {'script', 'iframe', 'object', 'embed'};

/// URL schemes never allowed to reach a renderer.
const Set<String> _dangerousSchemes = {'javascript:', 'vbscript:'};

/// Parses [rawHtml] and strips dangerous markup before rendering:
/// script/iframe/object/embed elements, `on*` event handler attributes,
/// `srcdoc`, and javascript/vbscript URLs.
///
/// Defense in depth: flutter_html executes no script, but sanitized input
/// keeps hostile markup out of the widget tree entirely. Returns the parsed
/// DOM document (the parser wraps input in html/body).
dom.Document sanitizeHtmlDocument(String rawHtml) {
  final document = html_parser.parse(rawHtml);
  final root = document.body ?? document.documentElement;
  if (root != null) _scrub(root);
  return document;
}

/// Plain text of [rawHtml] (search indexing; sanitization not required here).
String htmlPlainText(String rawHtml) =>
    html_parser.parse(rawHtml).documentElement?.text ?? '';

void _scrub(dom.Element element) {
  element.attributes.removeWhere((name, _) => name.toLowerCase().startsWith('on'));
  element.attributes.remove('srcdoc');

  for (final attrName in const ['href', 'src', 'action', 'data']) {
    final value = element.attributes[attrName];
    if (value != null && _isDangerousUrl(value)) {
      element.attributes.remove(attrName);
    }
  }

  final doomed = element.nodes
      .whereType<dom.Element>()
      .where(
        (child) => _removedElements.contains(
          child.localName?.toLowerCase(),
        ),
      )
      .toList();
  for (final child in doomed) {
    child.remove();
  }

  final survivors = element.nodes.whereType<dom.Element>().toList();
  for (final child in survivors) {
    _scrub(child);
  }
}

bool _isDangerousUrl(String url) {
  // Collapse whitespace/control chars that browsers ignore in schemes.
  final normalized = url.trim().toLowerCase().replaceAll(
        RegExp(r'[\s\x00-\x1f]'),
        '',
      );
  return _dangerousSchemes.any(normalized.startsWith);
}
```

- [ ] **Step 4: Run tests**

Run: `cd client/packages/tp_markdown && flutter test test/html_sanitizer_test.dart`
Expected: PASS (all 6 tests).

Note: `querySelectorAll`/`querySelector` come from `package:html`'s DOM implementation. If a selector helper is unavailable in this version, replace assertions with recursive walks over `doc.body!.nodes`.

- [ ] **Step 5: Commit**

```bash
git add client/packages/tp_markdown/lib/src/render/html_sanitizer.dart \
  client/packages/tp_markdown/test/html_sanitizer_test.dart
git commit -m "feat(tp_markdown): add HTML sanitizer for untrusted markup"
```

---

### Task 4: Renderer — buildHtmlBlock + registry registration

**Files:**
- Create: `client/packages/tp_markdown/lib/src/render/html_block.dart`
- Modify: `client/packages/tp_markdown/lib/src/registry/block_widget_registry.dart` (after `register<RawLiteralBlock>`)
- Modify: `client/packages/tp_markdown/lib/tp_markdown.dart` (exports)
- Test: create `client/packages/tp_markdown/test/markdown_view_html_block_test.dart`

**Interfaces:**
- Consumes: `HtmlBlock` (Task 1), `sanitizeHtmlDocument`/`htmlPlainText` (Task 3), `MarkdownTokens`, `MarkdownResolvers`, `buildRawLiteralBlock` (existing, `image_raw_blocks.dart:21`).
- Produces: `Widget buildHtmlBlock(HtmlBlock block, MarkdownTokens tokens, MarkdownResolvers resolvers)` — exported from `package:tp_markdown/tp_markdown.dart`; registered for `HtmlBlock` in `BlockWidgetRegistry.builtIn()`.

- [ ] **Step 1: Write the failing widget tests**

Create `client/packages/tp_markdown/test/markdown_view_html_block_test.dart`:

```dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart' show Html;
import 'package:flutter_test/flutter_test.dart';
import 'package:tp_markdown/tp_markdown.dart';

RichText _richTextOf(WidgetTester tester) =>
    tester.widget<RichText>(find.byType(RichText).first);

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
    await tester.pumpWidget(harness(const MarkdownView(
      document: MarkdownDocument(
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

    await tester.tap(find.byType(RichText).first);
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

  testWidgets('script content never reaches the widget tree', (tester) async {
    await tester.pumpWidget(harness(const MarkdownView(
      document: MarkdownDocument(
        blocks: [HtmlBlock(rawHtml: '<p>ok</p><script>alert(1)</script>')],
      ),
      tokens: MarkdownTokens.test(),
    )));

    expect(_plainText(tester), contains('ok'));
    expect(_plainText(tester), isNot(contains('alert')));
  });

  testWidgets('sanitized-empty block collapses to nothing', (tester) async {
    await tester.pumpWidget(harness(const MarkdownView(
      document: MarkdownDocument(
        blocks: [HtmlBlock(rawHtml: '<script>x</script>')],
      ),
      tokens: MarkdownTokens.test(),
    )));

    expect(find.byType(Html), findsNothing);
  });

  testWidgets('VirtualMarkdownView renders HtmlBlock lazily', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: VirtualMarkdownView(
          document: const MarkdownDocument(
            blocks: [HtmlBlock(rawHtml: '<p>virtual html</p>')],
          ),
          tokens: MarkdownTokens.test(),
          flatten: true,
        ),
      ),
    ));

    expect(_plainText(tester), contains('virtual html'));
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd client/packages/tp_markdown && flutter test test/markdown_view_html_block_test.dart`
Expected: FAIL — `buildHtmlBlock` doesn't exist; unregistered `HtmlBlock` renders `Text("HtmlBlock")` via the registry fallback.

- [ ] **Step 3: Implement renderer**

Create `client/packages/tp_markdown/lib/src/render/html_block.dart` (single source of truth for this file — do not improvise alternatives):

```dart
import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart' as fh;
import 'package:html/dom.dart' as dom;

import '../ir/markdown_document.dart';
import '../registry/markdown_resolvers.dart';
import '../tokens/markdown_tokens.dart';
import 'html_sanitizer.dart';
import 'image_raw_blocks.dart';

/// Renders [HtmlBlock] with flutter_html, styled from [MarkdownTokens] so the
/// block blends into surrounding markdown typography. Untrusted markup is
/// sanitized first ([sanitizeHtmlDocument]); link taps route through
/// [MarkdownResolvers.onLinkTap], images resolve through
/// [MarkdownResolvers.resolveImage] when provided.
Widget buildHtmlBlock(
  HtmlBlock block,
  MarkdownTokens tokens,
  MarkdownResolvers resolvers,
) {
  final document = sanitizeHtmlDocument(block.rawHtml);
  if (_isEmpty(document)) return const SizedBox.shrink();

  try {
    return fh.Html.fromDom(
      document: document,
      style: _styleFor(tokens),
      onLinkTap: resolvers.onLinkTap == null
          ? null
          : (url, attributes, element) => resolvers.onLinkTap!(url ?? ''),
      extensions: [_ResolvedImageExtension(tokens, resolvers)],
    );
  } catch (_) {
    // The tolerant parser should never throw; degrade to source text.
    return buildRawLiteralBlock(
      RawLiteralBlock(rawMarkdown: block.rawHtml),
      tokens,
    );
  }
}

/// True when nothing visible remains after sanitization (e.g. script-only
/// input) — such blocks collapse instead of leaving stray spacing.
bool _isEmpty(dom.Document document) {
  final root = document.body ?? document.documentElement;
  if (root == null) return true;
  if (root.text.trim().isNotEmpty) return false;
  return root.nodes.whereType<dom.Element>().isEmpty;
}

Map<String, fh.Style> _styleFor(MarkdownTokens tokens) {
  fh.Style fromText(TextStyle s, {FontWeight? weight}) => fh.Style(
        fontSize: s.fontSize == null ? null : fh.FontSize(s.fontSize!),
        lineHeight:
            s.height == null ? null : fh.LineHeight(s.height!, units: 'number'),
        color: s.color,
        fontFamily: s.fontFamily,
        fontWeight: weight,
      );

  return {
    'body': fromText(tokens.body),
    'a': fh.Style(color: tokens.link.color),
    'code': fh.Style(
      fontFamily: tokens.inlineCode.fontFamily ?? 'monospace',
      backgroundColor: tokens.inlineCode.backgroundColor,
    ),
    'pre': fh.Style(
      fontFamily: tokens.codeBlock.fontFamily ?? 'monospace',
      color: tokens.codeBlock.color,
      backgroundColor: tokens.mutedSurface,
    ),
    for (var level = 1; level <= 6; level++)
      'h$level': fromText(tokens.headingStyle(level)),
    'blockquote': fh.Style(color: tokens.blockquote.color),
    'th': fh.Style(fontWeight: FontWeight.w600),
  };
}

/// Renders `<img>` whose src resolves via [MarkdownResolvers.resolveImage]
/// (workspace-relative assets etc.). Non-matching imgs fall through to
/// flutter_html's built-in network/data-uri handling.
class _ResolvedImageExtension extends fh.HtmlExtension {
  _ResolvedImageExtension(this.tokens, this.resolvers);

  final MarkdownTokens tokens;
  final MarkdownResolvers resolvers;

  @override
  Set<String> get supportedTags => {'img'};

  ImageProvider<Object>? _provider(fh.ExtensionContext context) {
    final src = context.attributes['src'];
    if (src == null || src.isEmpty) return null;
    return resolvers.resolveImage?.call(src);
  }

  @override
  bool matches(fh.ExtensionContext context) =>
      context.elementName == 'img' && _provider(context) != null;

  @override
  InlineSpan build(fh.ExtensionContext context) {
    final provider = _provider(context)!;
    // Inline-image sizing parity with buildMarkdownImage(inline: true).
    final lineHeight =
        (tokens.body.fontSize ?? 14) * (tokens.body.height ?? 1.4);
    return WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: Image(
        image: provider,
        height: lineHeight,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => Icon(
          Icons.image_outlined,
          size: lineHeight,
          color: tokens.body.color,
        ),
      ),
    );
  }
}
```

Note: `ImageProvider` is Flutter's type (`package:flutter/material.dart`, already imported) — not a flutter_html symbol; do not prefix it with `fh.`.

Register in `block_widget_registry.dart` right after the `register<RawLiteralBlock>(...)` call:

```dart
    registry.register<HtmlBlock>((block, tokens, resolvers, _, __, ___, ____) {
      return buildHtmlBlock(block as HtmlBlock, tokens, resolvers);
    });
```

Add import to `block_widget_registry.dart`:

```dart
import '../render/html_block.dart';
```

Export from `tp_markdown.dart` (after `export 'src/render/highlight_context.dart';`):

```dart
export 'src/render/html_block.dart';
export 'src/render/html_sanitizer.dart';
```

- [ ] **Step 4: Run analyzer + tests**

Run: `cd client/packages/tp_markdown && flutter analyze && flutter test test/markdown_view_html_block_test.dart`
Expected: analyze clean; all 6 widget tests PASS.

Adjustment notes (expected minor friction, fix forward):
- If `fh.HtmlExtension` needs `prepare` overridden because default StyledElement loses img attrs, mirror `OnImageTapExtension`'s pattern: override `matches` to check `context.currentStep` (`CurrentStep.preparing` → elementName+provider; `CurrentStep.building` → prepared element type) and wrap in a custom StyledElement subclass. Keep it minimal.
- If `tester.tap` misses the link span, tap `find.byType(RichText).last` or locate via `find.textContaining('go')`.

- [ ] **Step 5: Run full package suite**

Run: `cd client/packages/tp_markdown && flutter test`
Expected: ALL PASS (existing suites unaffected — default registry now renders previously-RawLiteral fixtures as Html).

- [ ] **Step 6: Commit**

```bash
git add client/packages/tp_markdown/lib/src/render/html_block.dart \
  client/packages/tp_markdown/lib/src/registry/block_widget_registry.dart \
  client/packages/tp_markdown/lib/tp_markdown.dart \
  client/packages/tp_markdown/test/markdown_view_html_block_test.dart
git commit -m "feat(tp_markdown): render HtmlBlock via flutter_html with token styling"
```

---

### Task 5: Search index + truncation adaptation

**Files:**
- Modify: `client/packages/tp_markdown/lib/src/search/markdown_search_index.dart` (:160-165 area)
- Modify: `client/packages/tp_markdown/lib/src/compile/content_truncate.dart` (:174 area)
- Test: create `client/packages/tp_markdown/test/html_search_truncate_test.dart`

**Interfaces:**
- Consumes: `HtmlBlock` (Task 1), `htmlPlainText` (Task 3), existing `MarkdownSearchIndex.of(document).search(query)`, `_estimateBlockChars`.
- Produces: search hits inside HTML blocks; truncation accounting for HTML blocks.

- [ ] **Step 1: Write the failing tests**

Create `client/packages/tp_markdown/test/html_search_truncate_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:tp_markdown/tp_markdown.dart';

void main() {
  setUp(clearMessageContentCache);

  test('search finds plain text inside HtmlBlock', () {
    final doc = compileMarkdown('before\n\n<div>needle text</div>\n');
    final index = MarkdownSearchIndex.of(doc);
    final hits = index.search(const MarkdownSearchQuery(pattern: 'needle'));
    expect(hits, hasLength(1));
    expect(hits.single.blockIndex, 1);
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
```

API reference (verified): `truncateMessageContent(MarkdownDocument full, {ContentCollapseBudget budget = ContentCollapseBudget.claudeAligned}) → TruncatedMessageContent{document, wasTruncated}`; `ContentCollapseBudget({maxBlocks = 8, maxTableRows = 6, maxChars = 1200})`. Both exported from the package barrel.

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd client/packages/tp_markdown && flutter test test/html_search_truncate_test.dart`
Expected: FAIL — search returns no hits (HtmlBlock skipped today); truncate test fails or mis-estimates (HtmlBlock unhandled in estimate switch → compile error actually: exhaustive switch).

- [ ] **Step 3: Implement both adaptations**

`markdown_search_index.dart` — insert a case before the skip case (~:164) and add import:

```dart
import '../render/html_sanitizer.dart';
```

```dart
    case HtmlBlock(:final rawHtml):
      final text = htmlPlainText(rawHtml);
      if (text.trim().isNotEmpty) {
        containers.add(
          MarkdownSearchContainer(
            blockIndex: blockIndex,
            path: List.unmodifiable(basePath),
            plainText: text,
          ),
        );
      }
    case ImageBlock() || RawLiteralBlock() || HorizontalRuleBlock():
      break;
```

`content_truncate.dart` — extend `_estimateBlockChars`:

```dart
    RawLiteralBlock(:final rawMarkdown) => rawMarkdown.length,
    HtmlBlock(:final rawHtml) => rawHtml.length,
```

- [ ] **Step 4: Run tests**

Run: `cd client/packages/tp_markdown && flutter test`
Expected: ALL PASS.

- [ ] **Step 5: Commit**

```bash
git add client/packages/tp_markdown/lib/src/search/markdown_search_index.dart \
  client/packages/tp_markdown/lib/src/compile/content_truncate.dart \
  client/packages/tp_markdown/test/html_search_truncate_test.dart
git commit -m "feat(tp_markdown): index and account for HtmlBlock in search/truncate"
```

---

### Task 6: Version bump, docs, full regression gate

**Files:**
- Modify: `client/packages/tp_markdown/pubspec.yaml` (version)
- Modify: `client/packages/tp_markdown/CHANGELOG.md`
- Modify: `client/packages/tp_markdown/README.md`

**Interfaces:**
- Consumes: everything shipped in Tasks 1–5.
- Produces: release-ready package state; no further code.

- [ ] **Step 1: Bump version + changelog**

`pubspec.yaml`: `version: 0.1.0` → `version: 0.2.0`.

Prepend to `CHANGELOG.md` (match its existing entry format):

```markdown
## 0.2.0
- Raw HTML regions compile to HtmlBlock and render via flutter_html (sanitized;
  styles derive from MarkdownTokens). Tables/headings containing raw HTML still
  render as source text.
- Search indexing includes HtmlBlock plain text.
```

`README.md` — update the pipeline description sentence to mention: raw HTML → sanitized `HtmlBlock` → flutter_html (theme-mapped), keeping RawLiteralBlock for GFM-reconstructing demotions.

- [ ] **Step 2: Full package suite**

Run: `cd client/packages/tp_markdown && flutter test`
Expected: ALL PASS.

- [ ] **Step 3: Project gate**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && dart run tool/run_tests.dart`
Expected: clean analyze, all client tests pass (app consumes tp_markdown via path dependency; no app-side changes expected — chat messages and markdown preview pick up HTML rendering automatically).

Manual smoke (optional but recommended): launch the app, send a prompt that makes the agent output `<u>underline</u>` / `<sub>x</sub>` / `<kbd>Ctrl</kbd>`, confirm rendered styling in chat; open a README containing `<img>`/`<details>` in workbench preview.

- [ ] **Step 4: Commit**

```bash
git add client/packages/tp_markdown/pubspec.yaml \
  client/packages/tp_markdown/CHANGELOG.md \
  client/packages/tp_markdown/README.md
git commit -m "chore(tp_markdown): bump to 0.2.0 with HTML block rendering"
```
