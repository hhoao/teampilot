import 'package:flutter/material.dart';

import '../ir/markdown_document.dart';
import '../registry/block_widget_registry.dart';
import '../registry/markdown_resolvers.dart';
import '../tokens/markdown_tokens.dart';

/// Semantic markdown renderer: Column layout with kind-based inter-block gaps.
class MarkdownView extends StatelessWidget {
  const MarkdownView({
    super.key,
    required this.document,
    required this.tokens,
    this.resolvers = const MarkdownResolvers(),
    this.registry,
  });

  final MarkdownDocument document;
  final MarkdownTokens tokens;
  final MarkdownResolvers resolvers;
  final BlockWidgetRegistry? registry;

  @override
  Widget build(BuildContext context) {
    final blocks = document.blocks;
    if (blocks.isEmpty) return const SizedBox.shrink();

    final reg = registry ?? BlockWidgetRegistry.builtIn();
    final children = <Widget>[];
    MarkdownBlock? previous;

    for (final block in blocks) {
      if (previous != null) {
        final gap = gapBetween(previous.kind, block.kind, tokens);
        if (gap > 0) {
          children.add(SizedBox(height: gap));
        }
      }
      children.add(reg.build(block, tokens, resolvers));
      previous = block;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }
}
