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
  if (document.documentElement == null) {
    return buildRawLiteralBlock(
      RawLiteralBlock(rawMarkdown: block.rawHtml),
      tokens,
    );
  }
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
  } on Exception catch (_) {
    // HtmlParser is tolerant; this is defensive for fromDom construction.
    // Parse/build runs later in HtmlParser State, so this does not catch
    // layout-time failures.
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

/// Renders `<img>` via [buildMarkdownImage]: resolved providers keep the
/// inline [Image], unresolved relative/empty srcs show the existing
/// placeholder. http(s)/data/asset srcs with no provider fall through to
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
    final src = context.attributes['src'] ?? '';
    if (_isBuiltinHandledSrc(src)) return false;
    return true;
  }

  @override
  InlineSpan build(fh.ExtensionContext context) {
    final src = context.attributes['src'] ?? '';
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
