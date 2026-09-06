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
///
/// `<img>`s carrying sizing hints (`width`, `style="width:…"`) are hoisted out
/// of the html flow into sibling block figures: flutter_html's inline scaling
/// layer clamps WidgetSpan children to the text line box, which collapses
/// sized images to zero height.
Widget buildHtmlBlock(
  HtmlBlock block,
  MarkdownTokens tokens,
  MarkdownResolvers resolvers,
) {
  final document = sanitizeHtmlDocument(block.rawHtml);
  if (document.documentElement == null) {
    return buildRawLiteralBlock(
      RawLiteralBlock(rawMarkdown: block.rawHtml),
      tokens,
    );
  }
  if (_isEmpty(document)) return const SizedBox.shrink();

  final root = document.body ?? document.documentElement!;
  // Hoist sized imgs out of the html flow as grouped rows: sibling imgs of
  // one parent (GitHub renders them inline on a shared line, e.g.
  // `width: 70%` + `width: 19%` pairs in READMEs).
  final figures = <Widget>[];
  _hoistImageRows(root, tokens, resolvers, figures);
  // Drop badge-only leftovers (`<div><br></div>`) so they do not sit as empty
  // line boxes between remaining html (nav links) and the hoisted figures.
  _pruneIgnorableShells(root);
  // Center badge rows: flutter_html ignores the `align` attribute, so convert
  // `align="center"` blocks to `text-align: center` inline CSS it does parse.
  _injectCenterAlign(root);


  final Widget htmlWidget;
  try {
    htmlWidget = fh.Html.fromDom(
      document: document,
      style: _styleFor(tokens),
      onLinkTap: resolvers.onLinkTap == null
          ? null
          : (url, attributes, element) => resolvers.onLinkTap!(url ?? ''),
      extensions: [
        _ResolvedImageExtension(tokens, resolvers),
        const _UnknownTagPassthroughExtension(),
      ],
    );
  } on Exception catch (_) {
    // HtmlParser is tolerant; this is defensive for fromDom construction.
    // Parse/build runs later in HtmlParser State, so this does not catch
    // layout-time failures.
    return buildRawLiteralBlock(
      RawLiteralBlock(rawMarkdown: block.rawHtml),
      tokens,
    );
  }
  if (figures.isEmpty) return htmlWidget;

  // Badge-only blocks leave an empty html shell after hoist; skip it so
  // figure rows are not preceded by blank line boxes.
  final figurePads = [
    for (var i = 0; i < figures.length; i++)
      Padding(
        // Avoid a trailing pad under the last badge row (reads as "space below
        // is too large" next to the next markdown block's own margin).
        padding: EdgeInsets.only(bottom: i == figures.length - 1 ? 0 : 4),
        child: figures[i],
      ),
  ];
  if (_isVisuallyEmpty(document)) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: figurePads,
    );
  }
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    // Modest separation between leftover html (e.g. nav links) and badge rows.
    children: [
      htmlWidget,
      if (figurePads.isNotEmpty) const SizedBox(height: 12),
      ...figurePads,
    ],
  );
}

/// Hoists `<img>`s out of the html flow into [Wrap] rows appended to
/// [figures].
///
/// flutter_html's inline scaling layer clamps WidgetSpan children to the
/// text line box — sized images collapse to zero height, and multi-badge
/// rows that soft-wrap clip every badge after the first line ("one corner"
/// rendering). A pure-Flutter [Wrap] row has neither problem.
///
/// Block containers (`p`/`div`/`center`/`figure`) collect **sibling** imgs —
/// including those wrapped only in `<a>` (GitHub README badges) — into one
/// Wrap per `<br>`-separated run. Non-block parents still hoist their direct
/// img children.
///
/// Skip imgs no resolver claims whose src flutter_html handles itself
/// (http/asset/data URIs) — the built-in network path must keep working.
///
/// Ancestor `<a href>` wraps each image with the same tap behavior the html
/// flow would have had (routed through [MarkdownResolvers.onLinkTap]).
void _hoistImageRows(
  dom.Element root,
  MarkdownTokens tokens,
  MarkdownResolvers resolvers,
  List<Widget> figures,
) {
  final tag = root.localName?.toLowerCase();
  if (_isHoistBlock(tag)) {
    for (final imgs in _inlineImageRows(root, tokens, resolvers)) {
      _appendImageRow(imgs, tokens, resolvers, figures);
      for (final img in imgs) {
        _detachHoistedImage(img);
      }
    }
  } else {
    final imgs =
        _directImgs(root)
            .where((img) => _shouldHoist(img, tokens, resolvers))
            .toList();
    if (imgs.isNotEmpty) {
      _appendImageRow(imgs, tokens, resolvers, figures);
      for (final img in imgs) {
        _detachHoistedImage(img);
      }
    }
  }
  // Snapshot children: detach may remove empty <a> wrappers mid-iteration.
  for (final child in List<dom.Element>.from(root.children)) {
    if (child.localName == 'img') continue;
    _hoistImageRows(child, tokens, resolvers, figures);
  }
}

bool _isHoistBlock(String? tag) =>
    tag == 'p' || tag == 'div' || tag == 'center' || tag == 'figure';

/// Sibling hoistable imgs under [block], split into rows on `<br>`.
///
/// README badges are typically `<a href>…<img>…</a>` siblings — treat a
/// link that wraps a single hoistable img as one badge unit so they share
/// a Wrap instead of stacking one Wrap per `<a>`.
List<List<dom.Element>> _inlineImageRows(
  dom.Element block,
  MarkdownTokens tokens,
  MarkdownResolvers resolvers,
) {
  final rows = <List<dom.Element>>[];
  var current = <dom.Element>[];

  void flush() {
    if (current.isEmpty) return;
    rows.add(current);
    current = <dom.Element>[];
  }

  for (final node in block.nodes) {
    if (node is! dom.Element) continue;
    final name = node.localName?.toLowerCase();
    if (name == 'br') {
      flush();
      continue;
    }
    if (name == 'img' && _shouldHoist(node, tokens, resolvers)) {
      current.add(node);
      continue;
    }
    if (name == 'a') {
      final wrapped = _singleHoistableImg(node, tokens, resolvers);
      if (wrapped != null) {
        current.add(wrapped);
        continue;
      }
    }
    // Nested block / other markup: close the current badge run.
    flush();
  }
  flush();
  return rows;
}

/// An `<a>` that wraps exactly one hoistable `<img>` (optional whitespace).
dom.Element? _singleHoistableImg(
  dom.Element anchor,
  MarkdownTokens tokens,
  MarkdownResolvers resolvers,
) {
  dom.Element? img;
  for (final node in anchor.nodes) {
    if (node is dom.Text && node.text.trim().isEmpty) continue;
    if (node is dom.Element && node.localName == 'img') {
      if (img != null) return null;
      img = node;
      continue;
    }
    return null;
  }
  if (img == null || !_shouldHoist(img, tokens, resolvers)) return null;
  return img;
}

void _appendImageRow(
  List<dom.Element> imgs,
  MarkdownTokens tokens,
  MarkdownResolvers resolvers,
  List<Widget> figures,
) {
  if (imgs.isEmpty) return;
  final centered = _hasCenteredAncestorBlock(imgs.first);
  figures.add(
    Wrap(
      alignment: centered ? WrapAlignment.center : WrapAlignment.start,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 4,
      runSpacing: 4,
      children: [
        for (final img in imgs)
          _wrapWithLink(
            img,
            resolvers,
            _buildHoistedImage(img, tokens, resolvers),
          ),
      ],
    ),
  );
}

/// Removes a hoisted `<img>` and collapses an empty wrapping `<a>`.
///
/// Do **not** leave U+FFFC: flutter_html paints it as a boxed "OBJ" glyph.
void _detachHoistedImage(dom.Element img) {
  final parent = img.parent;
  img.remove();
  if (parent == null || parent.localName != 'a') return;
  final leftover = parent.nodes.where((node) {
    if (node is dom.Text) return node.text.trim().isNotEmpty;
    return true;
  });
  if (leftover.isEmpty) parent.remove();
}

/// Whether [img] should leave the html flow: sized imgs always (the scaling
/// layer would collapse them), unsized ones only when a resolver claims them
/// (the app layer renders http badges itself; unclaimed http/img srcs stay
/// in the flow for flutter_html's built-in handling).
bool _shouldHoist(
  dom.Element img,
  MarkdownTokens tokens,
  MarkdownResolvers resolvers,
) {
  if (_imgSizing(img) != null) return true;
  final src = img.attributes['src'];
  if (src == null || src.isEmpty) return false;
  final height = (tokens.body.fontSize ?? 14) * (tokens.body.height ?? 1.4);
  final claimed =
      resolvers.resolveImage?.call(src) != null ||
      resolvers.buildImageWidget?.call(
            src,
            inline: true,
            inlineHeight: height,
          ) !=
          null;
  if (claimed) return true;
  final uri = Uri.tryParse(src);
  return !(uri != null &&
      (uri.scheme == 'http' ||
          uri.scheme == 'https' ||
          uri.scheme == 'data' ||
          uri.scheme == 'asset'));
}

/// One hoisted image: sized hints stay block-level; remote unsized imgs
/// (shields badges) render at line height; local/relative unsized imgs
/// (README covers) stay block so they keep intrinsic size.
Widget _buildHoistedImage(
  dom.Element img,
  MarkdownTokens tokens,
  MarkdownResolvers resolvers,
) {
  final sizing = _imgSizing(img);
  final src = img.attributes['src'] ?? '';
  final inline = sizing == null && _isRemoteImageSrc(src);
  return buildMarkdownImage(
    src: src,
    alt: img.attributes['alt'],
    tokens: tokens,
    resolvers: resolvers,
    inline: inline,
    // Row-level centering comes from Wrap.alignment; a per-image Center
    // would expand each item to full width and force single-image runs.
    sizing: sizing?.withoutCenter(),
  );
}

bool _isRemoteImageSrc(String src) {
  final uri = Uri.tryParse(src.trim());
  return uri != null &&
      (uri.scheme == 'http' || uri.scheme == 'https') &&
      uri.host.isNotEmpty;
}

/// Wraps [child] with a tap handler when the nearest `<a>` ancestor has an
/// href (hoisted imgs leave the html flow, so the link must be rebuilt).
Widget _wrapWithLink(
  dom.Element img,
  MarkdownResolvers resolvers,
  Widget child,
) {
  final onLinkTap = resolvers.onLinkTap;
  if (onLinkTap == null) return child;
  dom.Node? node = img.parent;
  while (node is dom.Element && node.localName == 'a') {
    final href = node.attributes['href'];
    if (href != null && href.isNotEmpty) {
      return MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onLinkTap(href),
          child: child,
        ),
      );
    }
    node = node.parent;
  }
  return child;
}

/// Direct `<img>` children of [root].
List<dom.Element> _directImgs(dom.Element root) {
  return root.children.where((c) => c.localName == 'img').toList();
}

/// Adds `text-align: center` to block elements carrying `align="center"`.
void _injectCenterAlign(dom.Element root) {
  final tag = root.localName?.toLowerCase();
  if (tag == 'p' || tag == 'div' || tag == 'center' || tag == 'figure') {
    final align = root.attributes['align']?.toLowerCase();
    if (tag == 'center' || align == 'center' || align == 'middle') {
      final style = root.attributes['style'];
      root.attributes['style'] = style == null || style.trim().isEmpty
          ? 'text-align: center'
          : '$style; text-align: center';
    }
  }
  for (final child in root.children) {
    _injectCenterAlign(child);
  }
}

/// `width`/`height`/`style` sizing hints from an `<img>` dom element.
MarkdownImageSizing? _imgSizing(dom.Element element) {
  final attrs = element.attributes;
  double? percentWidth;
  double? pixelWidth;
  double? pixelHeight;

  void parseWidth(String? raw) {
    if (raw == null) return;
    if (raw.endsWith('%')) {
      final value = double.tryParse(raw.substring(0, raw.length - 1));
      if (value != null) percentWidth = value.clamp(0, 100) / 100;
    } else {
      pixelWidth ??= double.tryParse(raw);
    }
  }

  parseWidth(attrs['width']);
  final height = attrs['height'];
  if (height != null && !height.endsWith('%')) {
    pixelHeight = double.tryParse(height);
  }
  final style = attrs['style'];
  if (style != null) {
    final match = RegExp(
      r'width\s*:\s*([\d.]+)\s*(px|%)',
      caseSensitive: false,
    ).firstMatch(style);
    if (match != null) {
      final value = double.tryParse(match.group(1)!);
      if (value != null) {
        if (match.group(2) == '%') {
          percentWidth = value.clamp(0, 100) / 100;
        } else {
          pixelWidth = value;
        }
      }
    }
  }
  if (percentWidth == null && pixelWidth == null && pixelHeight == null) {
    return null;
  }
  return MarkdownImageSizing(
    percentWidth: percentWidth,
    pixelWidth: pixelWidth,
    pixelHeight: pixelHeight,
    center: _hasCenteredAncestorBlock(element),
  );
}

/// True when the nearest block ancestor (`p`/`div`/`center`/`figure`) asks
/// for centering via `align="center"` (GitHub-style README badge rows).
bool _hasCenteredAncestorBlock(dom.Element element) {
  dom.Node? node = element.parent;
  while (node != null) {
    if (node is dom.Element) {
      final tag = node.localName?.toLowerCase();
      if (tag == 'p' || tag == 'div' || tag == 'center' || tag == 'figure') {
        if (tag == 'center') return true;
        final align = node.attributes['align']?.toLowerCase();
        return align == 'center' || align == 'middle';
      }
    }
    node = node.parent;
  }
  return false;
}

/// True when nothing visible remains after sanitization (e.g. script-only
/// input) — such blocks collapse instead of leaving stray spacing.
bool _isEmpty(dom.Document document) {
  final root = document.body ?? document.documentElement;
  if (root == null) return true;
  if (root.text.trim().isNotEmpty) return false;
  return root.nodes.whereType<dom.Element>().isEmpty;
}

/// Like [_isEmpty], but ignores leftover `<br>` after badge rows are hoisted
/// (README `div` with only badges + line breaks).
bool _isVisuallyEmpty(dom.Document document) {
  final root = document.body ?? document.documentElement;
  if (root == null) return true;
  if (root.text.trim().isNotEmpty) return false;
  return root.nodes.whereType<dom.Element>().every(_isIgnorableShell);
}

/// Removes empty shells left after image hoist (`<br>`, empty `<div>`/`<p>`).
void _pruneIgnorableShells(dom.Element root) {
  for (final child in List<dom.Element>.from(root.children)) {
    _pruneIgnorableShells(child);
    if (_isIgnorableShell(child)) child.remove();
  }
}

bool _isIgnorableShell(dom.Element element) {
  final tag = element.localName?.toLowerCase();
  if (tag == 'br') return true;
  if (element.text.trim().isNotEmpty) return false;
  final kids = element.nodes.whereType<dom.Element>();
  if (kids.isEmpty) {
    // Empty block containers (badge div after imgs were detached).
    return tag == 'p' ||
        tag == 'div' ||
        tag == 'center' ||
        tag == 'figure' ||
        tag == 'span' ||
        tag == 'a';
  }
  return kids.every(_isIgnorableShell);
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

  // Zero flutter_html defaults (body margin 8, p margin 1em) — inter-block
  // rhythm belongs to MarkdownTokens.marginOf / gapBetween, and in-block
  // figure gaps are explicit SizedBoxes in buildHtmlBlock.
  return {
    'body': fromText(tokens.body).copyWith(margin: fh.Margins.zero),
    'p': fh.Style(display: fh.Display.block, margin: fh.Margins.zero),
    'div': fh.Style(display: fh.Display.block, margin: fh.Margins.zero),
    'center': fh.Style(display: fh.Display.block, margin: fh.Margins.zero),
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

/// Renders unrecognized tags as transparent wrappers so inner text is kept.
///
/// flutter_html turns unmatched tags into [fh.EmptyContentElement], which
/// drops the whole subtree — a wrapping `<think>` / custom XML tag would
/// otherwise blank the block.
final class _UnknownTagPassthroughExtension extends fh.HtmlExtension {
  const _UnknownTagPassthroughExtension();

  static final Set<String> _builtinTags = {
    for (final builtin in fh.HtmlParser.builtIns) ...builtin.supportedTags,
  };

  @override
  Set<String> get supportedTags => const {};

  @override
  bool matches(fh.ExtensionContext context) {
    if (context.node is! dom.Element) return false;
    final name = context.elementName;
    if (name.isEmpty) return false;
    return !_builtinTags.contains(name);
  }

  @override
  InlineSpan build(fh.ExtensionContext context) {
    final children = context.inlineSpanChildren ?? const <InlineSpan>[];
    if (children.isEmpty) return const TextSpan();
    if (children.length == 1) return children.single;
    return TextSpan(children: children);
  }
}

/// Renders `<img>` via [buildMarkdownImage]: resolved providers keep the
/// inline [Image], unresolved relative/empty srcs show the existing
/// placeholder. http(s)/data/asset srcs with no provider fall through to
/// flutter_html's built-in network/data-uri handling.
class _ResolvedImageExtension extends fh.HtmlExtension {
  _ResolvedImageExtension(this.tokens, this.resolvers);

  final MarkdownTokens tokens;
  final MarkdownResolvers resolvers;

  static double _inlineHeight(MarkdownTokens tokens) =>
      (tokens.body.fontSize ?? 14) * (tokens.body.height ?? 1.4);

  @override
  Set<String> get supportedTags => {'img'};

  ImageProvider<Object>? _provider(fh.ExtensionContext context) {
    final src = context.attributes['src'];
    if (src == null || src.isEmpty) return null;
    return resolvers.resolveImage?.call(src);
  }

  /// True when flutter_html's built-in image handler can load [src] itself.
  bool _isBuiltinHandledSrc(String src) {
    final uri = Uri.tryParse(src);
    if (uri == null) return false;
    return uri.scheme == 'http' ||
        uri.scheme == 'https' ||
        uri.scheme == 'data' ||
        uri.scheme == 'asset';
  }

  @override
  bool matches(fh.ExtensionContext context) {
    if (context.elementName != 'img') return false;
    if (_provider(context) != null) return true;
    if (_widgetHandled(context)) return true;
    final src = context.attributes['src'] ?? '';
    if (_isBuiltinHandledSrc(src)) return false;
    return true;
  }

  /// True when the widget-level image hook claims this src (e.g. flutter_svg
  /// for SVG badges, which have no raster [ImageProvider]).
  bool _widgetHandled(fh.ExtensionContext context) {
    if (resolvers.buildImageWidget == null) return false;
    final src = context.attributes['src'];
    if (src == null || src.isEmpty) return false;
    // Cheap same-assumption probe: widget hooks are src-keyed, not
    // constraint-aware, so inline (true) matches the html img build below.
    return resolvers.buildImageWidget!(
      src,
      inline: true,
      inlineHeight: _inlineHeight(tokens),
    ) !=
        null;
  }

  @override
  InlineSpan build(fh.ExtensionContext context) {
    final src = context.attributes['src'] ?? '';
    // Sized imgs are hoisted out of the flow by buildHtmlBlock before
    // flutter_html parses; only inline badge glyphs (no sizing hints) reach
    // this span.
    return WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: buildMarkdownImage(
        src: src,
        alt: context.attributes['alt'],
        tokens: tokens,
        resolvers: resolvers,
        inline: true,
      ),
    );
  }
}

