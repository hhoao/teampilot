import 'package:flutter/material.dart';

import '../ir/markdown_document.dart';
import '../registry/block_widget_registry.dart';
import '../registry/markdown_resolvers.dart';
import '../strings.dart';
import '../tokens/markdown_tokens.dart';
import 'inline_spans.dart';

/// Semantic markdown renderer: Column layout with kind-based inter-block gaps.
class MarkdownView extends StatelessWidget {
  const MarkdownView({
    super.key,
    required this.document,
    required this.tokens,
    this.resolvers = const MarkdownResolvers(),
    this.strings = MarkdownStrings.english,
    this.registry,
  });

  final MarkdownDocument document;
  final MarkdownTokens tokens;
  final MarkdownResolvers resolvers;
  final MarkdownStrings strings;
  final BlockWidgetRegistry? registry;

  @override
  Widget build(BuildContext context) {
    final blocks = document.blocks;
    if (blocks.isEmpty) return const SizedBox.shrink();

    final reg = registry ?? BlockWidgetRegistry.builtIn();
    final children = <Widget>[];
    MarkdownBlock? previous;
    var i = 0;

    while (i < blocks.length) {
      final block = blocks[i];

      if (block is ParagraphBlock) {
        var end = i + 1;
        while (end < blocks.length && blocks[end] is ParagraphBlock) {
          end++;
        }
        final run = blocks.sublist(i, end).cast<ParagraphBlock>();

        _addGapIfNeeded(children, previous, block, tokens);
        children.add(
          run.length == 1
              ? buildParagraph(run.first, tokens, resolvers)
              : buildMergedParagraphs(run, tokens, resolvers),
        );
        previous = run.last;
        i = end;
        continue;
      }

      _addGapIfNeeded(children, previous, block, tokens);
      children.add(reg.build(block, tokens, resolvers, strings));
      previous = block;
      i++;
    }

    return MarkdownStringsScope(
      strings: strings,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  void _addGapIfNeeded(
    List<Widget> children,
    MarkdownBlock? previous,
    MarkdownBlock next,
    MarkdownTokens tokens,
  ) {
    if (previous == null) return;
    final gap = gapBetween(previous.kind, next.kind, tokens);
    if (gap > 0) {
      children.add(SizedBox(height: gap));
    }
  }
}
