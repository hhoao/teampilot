import 'package:flutter/foundation.dart';

/// Style-free compiled markdown document (cacheable IR).
@immutable
class MessageContentDocument {
  const MessageContentDocument({required this.blocks});

  final List<ContentBlock> blocks;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MessageContentDocument && listEquals(blocks, other.blocks);

  @override
  int get hashCode => Object.hashAll(blocks);
}

/// Top-level block in a [MessageContentDocument].
sealed class ContentBlock {
  const ContentBlock();
}

final class ParagraphBlock extends ContentBlock {
  const ParagraphBlock({required this.runs});

  final List<InlineRun> runs;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ParagraphBlock && listEquals(runs, other.runs);

  @override
  int get hashCode => Object.hashAll(runs);
}

final class HeadingBlock extends ContentBlock {
  const HeadingBlock({required this.level, required this.runs});

  final int level;
  final List<InlineRun> runs;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HeadingBlock &&
          level == other.level &&
          listEquals(runs, other.runs);

  @override
  int get hashCode => Object.hash(level, Object.hashAll(runs));
}

final class ListBlock extends ContentBlock {
  const ListBlock({required this.ordered, required this.items});

  final bool ordered;
  final List<ContentListItem> items;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ListBlock &&
          ordered == other.ordered &&
          listEquals(items, other.items);

  @override
  int get hashCode => Object.hash(ordered, Object.hashAll(items));
}

@immutable
class ContentListItem {
  const ContentListItem({
    required this.runs,
    this.children = const [],
    this.isTaskChecked,
  });

  final List<InlineRun> runs;
  final List<ContentBlock> children;

  /// `null` when the item is not a task-list entry.
  final bool? isTaskChecked;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ContentListItem &&
          listEquals(runs, other.runs) &&
          listEquals(children, other.children) &&
          isTaskChecked == other.isTaskChecked;

  @override
  int get hashCode => Object.hash(
        Object.hashAll(runs),
        Object.hashAll(children),
        isTaskChecked,
      );
}

final class BlockquoteBlock extends ContentBlock {
  const BlockquoteBlock({required this.blocks});

  final List<ContentBlock> blocks;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BlockquoteBlock && listEquals(blocks, other.blocks);

  @override
  int get hashCode => Object.hashAll(blocks);
}

final class HorizontalRuleBlock extends ContentBlock {
  const HorizontalRuleBlock();

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is HorizontalRuleBlock;

  @override
  int get hashCode => runtimeType.hashCode;
}

final class CodeBlock extends ContentBlock {
  const CodeBlock({this.language, required this.text});

  final String? language;
  final String text;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CodeBlock && language == other.language && text == other.text;

  @override
  int get hashCode => Object.hash(language, text);
}

final class TableBlock extends ContentBlock {
  const TableBlock({required this.headers, required this.rows});

  final List<InlineDocument> headers;
  final List<List<InlineDocument>> rows;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! TableBlock) return false;
    if (!listEquals(headers, other.headers)) return false;
    if (rows.length != other.rows.length) return false;
    for (var i = 0; i < rows.length; i++) {
      if (!listEquals(rows[i], other.rows[i])) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(Object.hashAll(headers), Object.hashAll(rows));
}

final class UnsupportedBlock extends ContentBlock {
  const UnsupportedBlock({required this.rawMarkdown});

  final String rawMarkdown;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UnsupportedBlock && rawMarkdown == other.rawMarkdown;

  @override
  int get hashCode => rawMarkdown.hashCode;
}

/// Inline-run document for table cells (no nested blocks).
@immutable
class InlineDocument {
  const InlineDocument({required this.runs});

  final List<InlineRun> runs;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InlineDocument && listEquals(runs, other.runs);

  @override
  int get hashCode => Object.hashAll(runs);
}

/// Inline span inside a paragraph, heading, or table cell.
sealed class InlineRun {
  const InlineRun();
}

final class TextRun extends InlineRun {
  const TextRun(this.text);

  final String text;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is TextRun && text == other.text;

  @override
  int get hashCode => text.hashCode;
}

final class StrongRun extends InlineRun {
  const StrongRun({required this.children});

  final List<InlineRun> children;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StrongRun && listEquals(children, other.children);

  @override
  int get hashCode => Object.hashAll(children);
}

final class EmphasisRun extends InlineRun {
  const EmphasisRun({required this.children});

  final List<InlineRun> children;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EmphasisRun && listEquals(children, other.children);

  @override
  int get hashCode => Object.hashAll(children);
}

final class StrikeRun extends InlineRun {
  const StrikeRun({required this.children});

  final List<InlineRun> children;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StrikeRun && listEquals(children, other.children);

  @override
  int get hashCode => Object.hashAll(children);
}

final class CodeRun extends InlineRun {
  const CodeRun(this.text);

  final String text;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is CodeRun && text == other.text;

  @override
  int get hashCode => text.hashCode;
}

final class LinkRun extends InlineRun {
  const LinkRun({required this.url, this.title, required this.children});

  final String url;
  final String? title;
  final List<InlineRun> children;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LinkRun &&
          url == other.url &&
          title == other.title &&
          listEquals(children, other.children);

  @override
  int get hashCode => Object.hash(url, title, Object.hashAll(children));
}
