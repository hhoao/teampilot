import 'package:flutter/material.dart';

import '../ir/markdown_document.dart';
import '../registry/markdown_resolvers.dart';
import '../tokens/markdown_tokens.dart';
import 'highlight_context.dart';
import 'inline_spans.dart';

typedef MarkdownNestedViewBuilder = Widget Function(
  MarkdownDocument document,
  List<MarkdownPathStep> basePath,
);

Widget buildBlockquote(
  BlockquoteBlock block,
  MarkdownTokens tokens, {
  required MarkdownNestedViewBuilder nestedView,
  MarkdownHighlightContext? highlights,
  int blockIndex = 0,
  List<MarkdownPathStep> basePath = const [],
}) {
  // One nested view per child, each carrying the child's fully-extended
  // container base ([basePath, ChildStep(c)]) so highlight lookups inside
  // stay aligned with MarkdownSearchIndex's projection. Inter-child gaps
  // mirror MarkdownView's kind-based rhythm.
  return DecoratedBox(
    decoration: BoxDecoration(
      border: Border(
        left: BorderSide(color: tokens.borderColor, width: 3),
      ),
    ),
    child: Padding(
      padding: const EdgeInsets.only(left: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var c = 0; c < block.blocks.length; c++) ...[
            if (c > 0)
              SizedBox(
                height: gapBetween(
                  block.blocks[c - 1].kind,
                  block.blocks[c].kind,
                  tokens,
                ),
              ),
            nestedView(
              MarkdownDocument(blocks: [block.blocks[c]]),
              [...basePath, ChildStep(c)],
            ),
          ],
        ],
      ),
    ),
  );
}

Widget buildList(
  ListBlock block,
  MarkdownTokens tokens,
  MarkdownResolvers resolvers, {
  required MarkdownNestedViewBuilder nestedView,
  MarkdownHighlightContext? highlights,
  int blockIndex = 0,
  List<MarkdownPathStep> basePath = const [],
  int depth = 0,
}) {
  return _MarkdownList(
    ordered: block.ordered,
    items: block.items,
    tokens: tokens,
    resolvers: resolvers,
    nestedView: nestedView,
    highlights: highlights,
    blockIndex: blockIndex,
    basePath: basePath,
    depth: depth,
  );
}

class _MarkdownList extends StatelessWidget {
  const _MarkdownList({
    required this.ordered,
    required this.items,
    required this.tokens,
    required this.resolvers,
    required this.nestedView,
    required this.highlights,
    required this.blockIndex,
    required this.basePath,
    required this.depth,
  });

  final bool ordered;
  final List<ContentListItem> items;
  final MarkdownTokens tokens;
  final MarkdownResolvers resolvers;
  final MarkdownNestedViewBuilder nestedView;
  final MarkdownHighlightContext? highlights;
  final int blockIndex;
  final List<MarkdownPathStep> basePath;
  final int depth;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0 && tokens.listItemGap > 0)
            SizedBox(height: tokens.listItemGap),
          _buildItem(items[i], i),
        ],
      ],
    );
  }

  Widget _buildItem(ContentListItem item, int index) {
    final marker = _marker(item, index);
    final itemPath = [...basePath, ListItemStep(index)];
    final content = Text.rich(
      TextSpan(
        style: tokens.body,
        children: inlineSpans(item.runs, tokens, tokens.body, resolvers,
            highlights: highlights?.forContainer(blockIndex, itemPath)),
      ),
      strutStyle: forcedStrut(tokens.body),
    );

    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SelectionContainer.disabled(
          child: SizedBox(
            width: tokens.listIndent,
            child: Text(
              marker,
              style: tokens.listBullet,
              strutStyle: forcedStrut(tokens.listBullet),
            ),
          ),
        ),
        Expanded(child: content),
      ],
    );

    if (item.children.isEmpty) {
      return Padding(
        padding: EdgeInsets.only(left: depth * tokens.listIndent),
        child: row,
      );
    }

    final childRows = <Widget>[];
    var childIndex = 0;
    for (final child in item.children) {
      switch (child) {
        case ListBlock(:final ordered, :final items):
          childRows.add(
            buildList(
              ListBlock(ordered: ordered, items: items),
              tokens,
              resolvers,
              nestedView: nestedView,
              highlights: highlights,
              blockIndex: blockIndex,
              basePath: [...itemPath, ChildStep(childIndex)],
              depth: depth + 1,
            ),
          );
        default:
          childRows.add(
            Padding(
              padding: EdgeInsets.only(left: tokens.listIndent),
              child: nestedView(
                MarkdownDocument(blocks: [child]),
                [...itemPath, ChildStep(childIndex)],
              ),
            ),
          );
      }
      childIndex++;
    }

    return Padding(
      padding: EdgeInsets.only(left: depth * tokens.listIndent),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          row,
          if (tokens.listItemGap > 0) SizedBox(height: tokens.listItemGap),
          ...childRows,
        ],
      ),
    );
  }

  String _marker(ContentListItem item, int index) {
    if (item.isTaskChecked != null) {
      return item.isTaskChecked! ? '☑' : '☐';
    }
    if (ordered) return '${index + 1}.';
    return '•';
  }
}
