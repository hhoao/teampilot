import 'package:markdown/markdown.dart' as md;

import 'content_ir.dart';
import 'streaming_markdown.dart';

export 'streaming_markdown.dart';

/// Compiles GFM markdown into a style-free [MessageContentDocument].
///
/// Images and raw HTML become [UnsupportedBlock] slices. Task-list checkboxes
/// are recognized and do not count as unsupported HTML.
MessageContentDocument compileMessageContent(String markdown) {
  final prepared = prepareStreamingMarkdown(markdown);
  final document = md.Document(
    extensionSet: md.ExtensionSet.gitHubFlavored,
    encodeHtml: false,
  );
  final nodes = document.parse(prepared);
  return MessageContentDocument(
    blocks: [for (final node in nodes) _compileTopLevel(node)],
  );
}

ContentBlock _compileTopLevel(md.Node node) {
  if (node is md.Text) {
    final text = node.textContent;
    if (_looksLikeHtml(text)) {
      return UnsupportedBlock(rawMarkdown: text);
    }
    if (text.trim().isEmpty) {
      return const ParagraphBlock(runs: []);
    }
    return ParagraphBlock(runs: [TextRun(text)]);
  }
  if (node is! md.Element) {
    return UnsupportedBlock(rawMarkdown: node.textContent);
  }
  return _compileElement(node);
}

ContentBlock _compileElement(md.Element element) {
  final tag = element.tag;
  switch (tag) {
    case 'h1':
    case 'h2':
    case 'h3':
    case 'h4':
    case 'h5':
    case 'h6':
      return HeadingBlock(
        level: int.parse(tag.substring(1)),
        runs: _compileInlines(element.children),
      );
    case 'p':
      if (_hasUnsupportedInline(element.children)) {
        return UnsupportedBlock(rawMarkdown: _reconstructUnsupported(element));
      }
      return ParagraphBlock(runs: _compileInlines(element.children));
    case 'pre':
      return _compileCodeBlock(element);
    case 'blockquote':
      return BlockquoteBlock(
        blocks: [
          for (final child in element.children ?? const <md.Node>[])
            _compileTopLevel(child),
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
      return UnsupportedBlock(rawMarkdown: _reconstructUnsupported(element));
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
  final children = <ContentBlock>[];

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
            UnsupportedBlock(rawMarkdown: _reconstructUnsupported(child)),
          );
        } else {
          runs.addAll(_compileInlines(child.children));
        }
        continue;
      }
      children.add(_compileTopLevel(child));
      continue;
    }
    if (_hasUnsupportedInline([child])) {
      children.add(
        UnsupportedBlock(rawMarkdown: _reconstructUnsupported(child)),
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

TableBlock _compileTable(md.Element table) {
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
      return const [];
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
      if (node.tag == 'img') return true;
      if (node.tag == 'input' && node.attributes['type'] == 'checkbox') {
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
    case 'input':
      return true;
    default:
      return false;
  }
}

bool _looksLikeHtml(String text) {
  final trimmed = text.trimLeft();
  return trimmed.startsWith('<') && trimmed.contains('>');
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
  if (node is md.Text) {
    return node.textContent;
  }
  if (node is md.Element) {
    // Best-effort: prefer textContent for MarkdownBody fallback.
    final text = node.textContent;
    if (text.isNotEmpty) return text;
    return '<${node.tag}>';
  }
  return node.textContent;
}
