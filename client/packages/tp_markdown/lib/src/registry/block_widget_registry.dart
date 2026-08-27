import 'package:flutter/material.dart';

import '../ir/markdown_document.dart';
import '../render/highlight_context.dart';
import '../render/html_block.dart';
import '../render/image_raw_blocks.dart';
import '../render/inline_spans.dart';
import '../render/list_blockquote_blocks.dart';
import '../render/markdown_view.dart';
import '../render/table_code_hr_blocks.dart';
import '../strings.dart';
import '../tokens/markdown_tokens.dart';
import 'markdown_resolvers.dart';

typedef BlockWidgetBuilder = Widget Function(
  MarkdownBlock block,
  MarkdownTokens tokens,
  MarkdownResolvers resolvers,
  MarkdownStrings strings,
  MarkdownHighlightContext? highlights,
  int blockIndex,
  List<MarkdownPathStep> basePath,
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
    MarkdownStrings strings, {
    MarkdownHighlightContext? highlights,
    int blockIndex = 0,
    List<MarkdownPathStep> basePath = const [],
  }) {
    final builder = _builders[block.runtimeType];
    if (builder != null) {
      return builder(
          block, tokens, resolvers, strings, highlights, blockIndex, basePath);
    }
    return Text(block.runtimeType.toString());
  }

  factory BlockWidgetRegistry.builtIn() {
    final registry = BlockWidgetRegistry._();

    registry.register<ParagraphBlock>(
      (block, tokens, resolvers, _, hl, bi, p) => buildParagraph(
          block as ParagraphBlock, tokens, resolvers,
          highlights: hl?.forContainer(bi, p)),
    );

    registry.register<HeadingBlock>(
      (block, tokens, resolvers, _, hl, bi, p) => buildHeading(
          block as HeadingBlock, tokens, resolvers,
          highlights: hl?.forContainer(bi, p)),
    );

    registry.register<ListBlock>((block, tokens, resolvers, strings, hl, bi, p) {
      return buildList(
        block as ListBlock,
        tokens,
        resolvers,
        highlights: hl,
        blockIndex: bi,
        basePath: p,
        nestedView: (document, nestedBase) => MarkdownView(
          document: document,
          tokens: tokens,
          resolvers: resolvers,
          strings: strings,
          registry: registry,
          highlights: hl,
          blockIndex: bi,
          basePath: nestedBase,
        ),
      );
    });

    registry.register<BlockquoteBlock>(
        (block, tokens, resolvers, strings, hl, bi, p) {
      return buildBlockquote(
        block as BlockquoteBlock,
        tokens,
        highlights: hl,
        blockIndex: bi,
        basePath: p,
        nestedView: (document, nestedBase) => MarkdownView(
          document: document,
          tokens: tokens,
          resolvers: resolvers,
          strings: strings,
          registry: registry,
          highlights: hl,
          blockIndex: bi,
          basePath: nestedBase,
        ),
      );
    });

    registry
        .register<HorizontalRuleBlock>((_, tokens, __, ___, ____, _____, ______) {
      return buildHorizontalRule(tokens);
    });

    registry.register<CodeBlock>((block, tokens, _, __, hl, bi, p) =>
        buildCodeBlock(block as CodeBlock, tokens,
            highlights: hl, blockIndex: bi, basePath: p));

    registry.register<TableBlock>((block, tokens, resolvers, _, hl, bi, p) =>
        buildTable(block as TableBlock, tokens, resolvers,
            highlights: hl, blockIndex: bi, basePath: p));

    registry.register<ImageBlock>((block, tokens, resolvers, _, __, ___, ____) {
      return buildImageBlock(block as ImageBlock, tokens, resolvers);
    });

    registry.register<RawLiteralBlock>((block, tokens, _, __, ___, ____, _____) {
      return buildRawLiteralBlock(block as RawLiteralBlock, tokens);
    });

    registry.register<HtmlBlock>((block, tokens, resolvers, _, __, ___, ____) {
      return buildHtmlBlock(block as HtmlBlock, tokens, resolvers);
    });

    return registry;
  }
}
