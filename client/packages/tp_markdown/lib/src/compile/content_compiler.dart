import 'package:flutter/foundation.dart';
import 'package:markdown/markdown.dart' as md;

import '../ir/markdown_document.dart';
import 'streaming_markdown.dart';

const int _kMessageContentCacheMax = 256;

/// LRU cache of compiled docs keyed by [prepareStreamingMarkdown] output.
final Map<String, MarkdownDocument> _messageContentCache =
    <String, MarkdownDocument>{};

@visibleForTesting
int messageContentCacheHits = 0;

@visibleForTesting
int get messageContentCacheLength => _messageContentCache.length;

@visibleForTesting
void clearMessageContentCache() {
  _messageContentCache.clear();
  messageContentCacheHits = 0;
}

/// Compiles GFM markdown into a style-free [MarkdownDocument].
///
/// Images compile to [ImageBlock] / [ImageRun]. Raw HTML regions become
/// [HtmlBlock] so an html engine can render them. Demotion paths whose
/// reconstruction injects GFM syntax (headings, tables) keep [RawLiteralBlock].
/// Task-list checkboxes are recognized and do not count as unsupported HTML.
///
/// Results are cached (LRU, max 256) by the prepared markdown string. Cache hits
/// return the identical [MarkdownDocument] instance.
MarkdownDocument compileMarkdown(String markdown) {
  final prepared = prepareStreamingMarkdown(markdown);
  final cached = _messageContentCache.remove(prepared);
  if (cached != null) {
    messageContentCacheHits++;
    _messageContentCache[prepared] = cached;
    return cached;
  }
  final document = md.Document(
    extensionSet: md.ExtensionSet.gitHubFlavored,
    encodeHtml: false,
  );
  final nodes = document.parse(prepared);
  final compiled = MarkdownDocument(
    blocks: [
      for (final node in nodes) ..._compileTopLevelBlocks(node),
    ],
  );
  if (_messageContentCache.length >= _kMessageContentCacheMax) {
    _messageContentCache.remove(_messageContentCache.keys.first);
  }
  _messageContentCache[prepared] = compiled;
  return compiled;
}

/// Expands image-only paragraphs (one or more `<img>`s) into [ImageBlock]s.
List<MarkdownBlock> _compileTopLevelBlocks(md.Node node) {
  if (node is md.Element && node.tag == 'p') {
    final images = _tryCompileStandaloneImages(node);
    if (images != null) return images;
  }
  return [_compileTopLevelNode(node)];
}

MarkdownBlock _compileTopLevelNode(md.Node node) {
  if (node is md.Text) {
    final text = node.textContent;
    if (_looksLikeHtml(text)) {
      return HtmlBlock(rawHtml: text);
    }
    if (text.trim().isEmpty) {
      return const ParagraphBlock(runs: []);
    }
    return ParagraphBlock(runs: [TextRun(text)]);
  }
  if (node is! md.Element) {
    return RawLiteralBlock(rawMarkdown: node.textContent);
  }
  return _compileElement(node);
}

MarkdownBlock _compileElement(md.Element element) {
  final tag = element.tag;
  switch (tag) {
    case 'h1':
    case 'h2':
    case 'h3':
    case 'h4':
    case 'h5':
    case 'h6':
      if (_hasUnsupportedInline(element.children)) {
        // Reconstruction injects '#'-prefix GFM syntax the html engine cannot
        // parse — keep source-text rendering.
        return RawLiteralBlock(rawMarkdown: _reconstructUnsupported(element));
      }
      return HeadingBlock(
        level: int.parse(tag.substring(1)),
        runs: _compileInlines(element.children),
      );
    case 'p':
      // Image-only paragraphs are expanded in [_compileTopLevelBlocks].
      if (_hasUnsupportedInline(element.children)) {
        return HtmlBlock(rawHtml: _reconstructUnsupported(element));
      }
      return ParagraphBlock(runs: _compileInlines(element.children));
    case 'pre':
      return _compileCodeBlock(element);
    case 'blockquote':
      return BlockquoteBlock(
        blocks: [
          for (final child in element.children ?? const <md.Node>[])
            ..._compileTopLevelBlocks(child),
        ],
      );
    case 'hr':
      return const HorizontalRuleBlock();
    case 'ul':
    case 'ol':
      return _compileList(element, ordered: tag == 'ol');
    case 'table':
      return _compileTable(element);
    default:
      return RawLiteralBlock(rawMarkdown: _reconstructUnsupported(element));
  }
}

CodeBlock _compileCodeBlock(md.Element pre) {
  String? language;
  var text = '';
  for (final child in pre.children ?? const <md.Node>[]) {
    if (child is md.Element && child.tag == 'code') {
      final className = child.attributes['class'];
      if (className != null && className.startsWith('language-')) {
        language = className.substring('language-'.length);
      }
      text = child.textContent;
      break;
    }
  }
  return CodeBlock(language: language, text: text);
}

ListBlock _compileList(md.Element list, {required bool ordered}) {
  final items = <ContentListItem>[];
  for (final child in list.children ?? const <md.Node>[]) {
    if (child is! md.Element || child.tag != 'li') continue;
    items.add(_compileListItem(child));
  }
  return ListBlock(ordered: ordered, items: items);
}

ContentListItem _compileListItem(md.Element li) {
  final isTask = li.attributes['class'] == 'task-list-item';
  bool? isTaskChecked;
  final runs = <InlineRun>[];
  final children = <MarkdownBlock>[];

  // Unsupported inlines (raw HTML) follow the paragraph policy: emit an
  // [HtmlBlock] for that item region instead of silently dropping content.
  for (final child in li.children ?? const <md.Node>[]) {
    if (child is md.Element &&
        child.tag == 'input' &&
        child.attributes['type'] == 'checkbox') {
      isTaskChecked = child.attributes.containsKey('checked');
      continue;
    }
    if (_isBlockChild(child)) {
      if (child is md.Element && child.tag == 'p' && runs.isEmpty) {
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
    runs.addAll(_compileInlines([child]));
  }

  return ContentListItem(
    runs: runs,
    children: children,
    isTaskChecked: isTask ? (isTaskChecked ?? false) : null,
  );
}

bool _isBlockChild(md.Node node) {
  if (node is! md.Element) return false;
  switch (node.tag) {
    case 'p':
    case 'ul':
    case 'ol':
    case 'pre':
    case 'blockquote':
    case 'table':
    case 'hr':
    case 'h1':
    case 'h2':
    case 'h3':
    case 'h4':
    case 'h5':
    case 'h6':
      return true;
    default:
      return false;
  }
}

MarkdownBlock _compileTable(md.Element table) {
  if (_tableHasUnsupportedInline(table)) {
    // Reconstruction injects `| --- |` GFM rows the html engine cannot parse
    // as a table — keep source-text rendering.
    return RawLiteralBlock(rawMarkdown: _reconstructUnsupported(table));
  }

  final headers = <InlineDocument>[];
  final rows = <List<InlineDocument>>[];

  for (final section in table.children ?? const <md.Node>[]) {
    if (section is! md.Element) continue;
    if (section.tag == 'thead') {
      for (final row in section.children ?? const <md.Node>[]) {
        if (row is! md.Element || row.tag != 'tr') continue;
        headers.addAll(_compileTableRow(row, header: true));
      }
    } else if (section.tag == 'tbody') {
      for (final row in section.children ?? const <md.Node>[]) {
        if (row is! md.Element || row.tag != 'tr') continue;
        rows.add(_compileTableRow(row, header: false));
      }
    }
  }

  return TableBlock(headers: headers, rows: rows);
}

List<InlineDocument> _compileTableRow(md.Element row, {required bool header}) {
  final cells = <InlineDocument>[];
  final expectedTag = header ? 'th' : 'td';
  for (final cell in row.children ?? const <md.Node>[]) {
    if (cell is! md.Element || cell.tag != expectedTag) continue;
    cells.add(InlineDocument(runs: _compileInlines(cell.children)));
  }
  return cells;
}

bool _tableHasUnsupportedInline(md.Element table) {
  for (final section in table.children ?? const <md.Node>[]) {
    if (section is! md.Element) continue;
    if (section.tag != 'thead' && section.tag != 'tbody') continue;
    for (final row in section.children ?? const <md.Node>[]) {
      if (row is! md.Element || row.tag != 'tr') continue;
      for (final cell in row.children ?? const <md.Node>[]) {
        if (cell is! md.Element) continue;
        if (cell.tag != 'th' && cell.tag != 'td') continue;
        if (_hasUnsupportedInline(cell.children)) return true;
      }
    }
  }
  return false;
}

List<InlineRun> _compileInlines(List<md.Node>? nodes) {
  if (nodes == null || nodes.isEmpty) return const [];
  final runs = <InlineRun>[];
  for (final node in nodes) {
    runs.addAll(_compileInlineNode(node));
  }
  return runs;
}

List<InlineRun> _compileInlineNode(md.Node node) {
  if (node is md.Text) {
    return [TextRun(node.textContent)];
  }
  if (node is! md.Element) {
    return [TextRun(node.textContent)];
  }

  switch (node.tag) {
    case 'strong':
      return [StrongRun(children: _compileInlines(node.children))];
    case 'em':
      return [EmphasisRun(children: _compileInlines(node.children))];
    case 'del':
      return [StrikeRun(children: _compileInlines(node.children))];
    case 'code':
      return [CodeRun(node.textContent)];
    case 'a':
      return [
        LinkRun(
          url: node.attributes['href'] ?? '',
          title: node.attributes['title'],
          children: _compileInlines(node.children),
        ),
      ];
    case 'br':
      return [const TextRun('\n')];
    case 'input':
      // Task-list checkbox — ignored here; handled by list-item compiler.
      return const [];
    case 'img':
      return [_imageRunFromElement(node)];
    default:
      // Unknown inline wrapper: flatten children.
      return _compileInlines(node.children);
  }
}

bool _hasUnsupportedInline(List<md.Node>? nodes) {
  if (nodes == null) return false;
  for (final node in nodes) {
    if (node is md.Text && _looksLikeHtml(node.textContent)) {
      return true;
    }
    if (node is md.Element) {
      if (node.tag == 'input' && node.attributes['type'] == 'checkbox') {
        continue;
      }
      // Inline code is opaque literal text — do not treat `<…>` inside
      // backticks as raw HTML (that wrongly demoted whole GFM tables).
      if (node.tag == 'code') {
        continue;
      }
      // Raw HTML elements other than known markdown tags.
      if (!_isSupportedInlineTag(node.tag)) return true;
      if (_hasUnsupportedInline(node.children)) return true;
    }
  }
  return false;
}

bool _isSupportedInlineTag(String tag) {
  switch (tag) {
    case 'strong':
    case 'em':
    case 'del':
    case 'code':
    case 'a':
    case 'br':
    case 'img':
    case 'input':
      return true;
    default:
      return false;
  }
}

/// Image-only `<p>` (one or more `<img>`, ignoring whitespace/`<br>`) → blocks.
///
/// GFM merges adjacent image lines without a blank line into one paragraph;
/// those must stay [ImageBlock]s so preview does not shrink them to inline
/// line-height thumbnails.
List<ImageBlock>? _tryCompileStandaloneImages(md.Element paragraph) {
  if (paragraph.tag != 'p') return null;
  final images = <md.Element>[];
  for (final child in paragraph.children ?? const <md.Node>[]) {
    if (child is md.Text && child.textContent.trim().isEmpty) continue;
    if (child is md.Element && child.tag == 'br') continue;
    if (child is md.Element && child.tag == 'img') {
      images.add(child);
      continue;
    }
    return null;
  }
  if (images.isEmpty) return null;
  return [for (final img in images) _imageBlockFromElement(img)];
}

ImageBlock _imageBlockFromElement(md.Element img) {
  return ImageBlock(
    src: img.attributes['src'] ?? '',
    alt: _optionalAttr(img.attributes['alt']),
  );
}

ImageRun _imageRunFromElement(md.Element img) {
  return ImageRun(
    src: img.attributes['src'] ?? '',
    alt: _optionalAttr(img.attributes['alt']),
  );
}

String? _optionalAttr(String? value) {
  if (value == null || value.isEmpty) return null;
  return value;
}

/// Raw HTML tag shape (`<div>`, `</div>`, `<br/>`, `<!-- c -->`) as it appears
/// inside literal text nodes — the markdown parser leaves inline tags as plain
/// text instead of producing [md.Element]s.
final RegExp _htmlTagPattern = RegExp(r'</?[a-zA-Z][^>]*>');

/// Whether [text] carries raw HTML markup: a leading tag region or any
/// embedded `<tag>` region.
bool _looksLikeHtml(String text) {
  final trimmed = text.trimLeft();
  return trimmed.startsWith('<') && trimmed.contains('>') ||
      _htmlTagPattern.hasMatch(trimmed);
}

String _reconstructUnsupported(md.Node node) {
  if (node is md.Element && node.tag == 'img') {
    final alt = node.attributes['alt'] ?? '';
    final src = node.attributes['src'] ?? '';
    return '![$alt]($src)';
  }
  if (node is md.Element && node.tag == 'p') {
    final parts = <String>[];
    for (final child in node.children ?? const <md.Node>[]) {
      parts.add(_reconstructUnsupported(child));
    }
    return parts.join();
  }
  if (node is md.Element && node.tag.startsWith('h')) {
    final level = int.tryParse(node.tag.substring(1));
    if (level != null && level >= 1 && level <= 6) {
      final parts = <String>[];
      for (final child in node.children ?? const <md.Node>[]) {
        parts.add(_reconstructUnsupported(child));
      }
      return '${'#' * level} ${parts.join()}';
    }
  }
  if (node is md.Element && (node.tag == 'td' || node.tag == 'th')) {
    final parts = <String>[];
    for (final child in node.children ?? const <md.Node>[]) {
      parts.add(_reconstructUnsupported(child));
    }
    return parts.join();
  }
  if (node is md.Element && node.tag == 'tr') {
    final cells = <String>[];
    for (final child in node.children ?? const <md.Node>[]) {
      if (child is md.Element && (child.tag == 'td' || child.tag == 'th')) {
        cells.add(_reconstructUnsupported(child));
      }
    }
    return '| ${cells.join(' | ')} |';
  }
  if (node is md.Element && node.tag == 'table') {
    final lines = <String>[];
    var headerCellCount = 0;
    for (final section in node.children ?? const <md.Node>[]) {
      if (section is! md.Element) continue;
      final isHeader = section.tag == 'thead';
      for (final row in section.children ?? const <md.Node>[]) {
        if (row is! md.Element || row.tag != 'tr') continue;
        lines.add(_reconstructUnsupported(row));
        if (isHeader && headerCellCount == 0) {
          headerCellCount = row.children
                  ?.where(
                    (child) =>
                        child is md.Element &&
                        (child.tag == 'td' || child.tag == 'th'),
                  )
                  .length ??
              0;
        }
      }
    }
    if (headerCellCount > 0) {
      lines.insert(
        1,
        '| ${List.filled(headerCellCount, '---').join(' | ')} |',
      );
    }
    return lines.join('\n');
  }
  if (node is md.Text) {
    return node.textContent;
  }
  if (node is md.Element) {
    // Best-effort: prefer textContent for raw-literal fallback.
    final text = node.textContent;
    if (text.isNotEmpty) return text;
    return '<${node.tag}>';
  }
  return node.textContent;
}
