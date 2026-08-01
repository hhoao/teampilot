import 'package:flutter/material.dart';

import '../ir/markdown_document.dart';
import '../registry/markdown_resolvers.dart';
import '../tokens/markdown_tokens.dart';
import 'inline_spans.dart';

typedef MarkdownNestedViewBuilder = Widget Function(MarkdownDocument document);

Widget buildBlockquote(
  BlockquoteBlock block,
  MarkdownTokens tokens, {
  required MarkdownNestedViewBuilder nestedView,
}) {
  return DecoratedBox(
    decoration: BoxDecoration(
      border: Border(
        left: BorderSide(color: tokens.borderColor, width: 3),
      ),
    ),
    child: Padding(
      padding: const EdgeInsets.only(left: 12),
      child: nestedView(MarkdownDocument(blocks: block.blocks)),
    ),
  );
}

Widget buildList(
  ListBlock block,
  MarkdownTokens tokens,
  MarkdownResolvers resolvers, {
  required MarkdownNestedViewBuilder nestedView,
  int depth = 0,
}) {
  return _MarkdownList(
    ordered: block.ordered,
    items: block.items,
    tokens: tokens,
    resolvers: resolvers,
    nestedView: nestedView,
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
    required this.depth,
  });

  final bool ordered;
  final List<ContentListItem> items;
  final MarkdownTokens tokens;
  final MarkdownResolvers resolvers;
  final MarkdownNestedViewBuilder nestedView;
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
    final content = Text.rich(
      TextSpan(
        style: tokens.body,
        children: inlineSpans(item.runs, tokens, tokens.body, resolvers),
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

    return Padding(
      padding: EdgeInsets.only(left: depth * tokens.listIndent),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          row,
          if (tokens.listItemGap > 0) SizedBox(height: tokens.listItemGap),
          for (final child in item.children)
            switch (child) {
              ListBlock(:final ordered, :final items) => buildList(
                  ListBlock(ordered: ordered, items: items),
                  tokens,
                  resolvers,
                  nestedView: nestedView,
                  depth: depth + 1,
                ),
              _ => Padding(
                  padding: EdgeInsets.only(left: tokens.listIndent),
                  child: nestedView(MarkdownDocument(blocks: [child])),
                ),
            },
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
