import 'package:tp_markdown/tp_markdown.dart';

import 'markdown_preview_link_handler.dart';

final _htmlImgSrc = RegExp(
  r'''<img\b[^>]*?\bsrc\s*=\s*(["'])(.*?)\1''',
  caseSensitive: false,
  dotAll: true,
);

/// Collect http(s) image URLs from a compiled markdown document for prefetch.
///
/// Applies the same [preferRasterBadgeUrl] rewrite used at render time so the
/// store key matches what [MarkdownNetworkImage] will request.
List<String> collectMarkdownHttpImageUrls(MarkdownDocument document) {
  final out = <String>{};
  for (final block in document.blocks) {
    _collectFromBlock(block, out);
  }
  return out.toList(growable: false);
}

void _collectFromBlock(MarkdownBlock block, Set<String> out) {
  switch (block) {
    case ImageBlock(:final src):
      _maybeAdd(src, out);
    case HtmlBlock(:final rawHtml):
      for (final match in _htmlImgSrc.allMatches(rawHtml)) {
        _maybeAdd(match.group(2) ?? '', out);
      }
    case ParagraphBlock(:final runs):
      _collectFromRuns(runs, out);
    case HeadingBlock(:final runs):
      _collectFromRuns(runs, out);
    case ListBlock(:final items):
      for (final item in items) {
        _collectFromRuns(item.runs, out);
        for (final child in item.children) {
          _collectFromBlock(child, out);
        }
      }
    case BlockquoteBlock(:final blocks):
      for (final child in blocks) {
        _collectFromBlock(child, out);
      }
    case TableBlock(:final headers, :final rows):
      for (final cell in headers) {
        _collectFromRuns(cell.runs, out);
      }
      for (final row in rows) {
        for (final cell in row) {
          _collectFromRuns(cell.runs, out);
        }
      }
    case CodeBlock() ||
          HorizontalRuleBlock() ||
          RawLiteralBlock():
      break;
  }
}

void _collectFromRuns(List<InlineRun> runs, Set<String> out) {
  for (final run in runs) {
    switch (run) {
      case ImageRun(:final src):
        _maybeAdd(src, out);
      case StrongRun(:final children) ||
            EmphasisRun(:final children) ||
            StrikeRun(:final children) ||
            LinkRun(:final children):
        _collectFromRuns(children, out);
      case TextRun() || CodeRun():
        break;
    }
  }
}

void _maybeAdd(String raw, Set<String> out) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return;
  final uri = Uri.tryParse(trimmed);
  if (uri == null) return;
  if (uri.scheme != 'http' && uri.scheme != 'https') return;
  if (uri.host.isEmpty) return;
  out.add(preferRasterBadgeUrl(uri).toString());
}
