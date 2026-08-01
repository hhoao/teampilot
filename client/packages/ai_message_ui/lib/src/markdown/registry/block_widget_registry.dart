import 'package:flutter/material.dart';

import '../ir/markdown_document.dart';
import '../render/inline_spans.dart';
import '../render/list_blockquote_blocks.dart';
import '../render/markdown_view.dart';
import '../tokens/markdown_tokens.dart';
import 'markdown_resolvers.dart';

typedef BlockWidgetBuilder = Widget Function(
  MarkdownBlock block,
  MarkdownTokens tokens,
  MarkdownResolvers resolvers,
);

/// Maps block types to widget builders for [MarkdownView].
class BlockWidgetRegistry {
  BlockWidgetRegistry._();

  final Map<Type, BlockWidgetBuilder> _builders = {};

  void register<T extends MarkdownBlock>(BlockWidgetBuilder builder) {
    _builders[T] = builder;
  }

  Widget build(
    MarkdownBlock block,
    MarkdownTokens tokens,
    MarkdownResolvers resolvers,
  ) {
    final builder = _builders[block.runtimeType];
    if (builder != null) {
      return builder(block, tokens, resolvers);
    }
    return Text(block.runtimeType.toString());
  }

  factory BlockWidgetRegistry.builtIn() {
    final registry = BlockWidgetRegistry._();

    Widget buildNestedView(
      MarkdownDocument document,
      MarkdownTokens tokens,
      MarkdownResolvers resolvers,
    ) {
      return MarkdownView(
        document: document,
        tokens: tokens,
        resolvers: resolvers,
        registry: registry,
      );
    }

    registry.register<ParagraphBlock>((block, tokens, resolvers) {
      return buildParagraph(block as ParagraphBlock, tokens, resolvers);
    });

    registry.register<HeadingBlock>((block, tokens, resolvers) {
      return buildHeading(block as HeadingBlock, tokens, resolvers);
    });

    registry.register<ListBlock>((block, tokens, resolvers) {
      return buildList(
        block as ListBlock,
        tokens,
        resolvers,
        nestedView: (document) => buildNestedView(document, tokens, resolvers),
      );
    });

    registry.register<BlockquoteBlock>((block, tokens, resolvers) {
      return buildBlockquote(
        block as BlockquoteBlock,
        tokens,
        nestedView: (document) => buildNestedView(document, tokens, resolvers),
      );
    });

    registry.register<HorizontalRuleBlock>((_, __, ___) {
      return const Text('HorizontalRuleBlock');
    });

    registry.register<CodeBlock>((block, tokens, _) {
      final b = block as CodeBlock;
      return Text(b.text, style: tokens.codeBlock);
    });

    registry.register<TableBlock>((_, __, ___) {
      return const Text('TableBlock');
    });

    registry.register<ImageBlock>((block, _, __) {
      final b = block as ImageBlock;
      return Text(b.alt ?? b.src);
    });

    registry.register<RawLiteralBlock>((block, _, __) {
      final b = block as RawLiteralBlock;
      return Text(b.rawMarkdown);
    });

    return registry;
  }
}
