import 'package:flutter/material.dart';

import '../ir/markdown_document.dart';
import '../render/image_raw_blocks.dart';
import '../render/inline_spans.dart';
import '../render/list_blockquote_blocks.dart';
import '../render/markdown_view.dart';
import '../render/table_code_hr_blocks.dart';
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

    registry.register<HorizontalRuleBlock>((_, tokens, __) {
      return buildHorizontalRule(tokens);
    });

    registry.register<CodeBlock>((block, tokens, _) {
      return buildCodeBlock(block as CodeBlock, tokens);
    });

    registry.register<TableBlock>((block, tokens, resolvers) {
      return buildTable(block as TableBlock, tokens, resolvers);
    });

    registry.register<ImageBlock>((block, tokens, resolvers) {
      return buildImageBlock(block as ImageBlock, tokens, resolvers);
    });

    registry.register<RawLiteralBlock>((block, tokens, _) {
      return buildRawLiteralBlock(block as RawLiteralBlock, tokens);
    });

    return registry;
  }
}
