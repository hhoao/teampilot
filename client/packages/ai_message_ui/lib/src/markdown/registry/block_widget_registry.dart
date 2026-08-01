import 'package:flutter/material.dart';

import '../ir/markdown_document.dart';
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

    registry.register<ParagraphBlock>((block, tokens, _) {
      final b = block as ParagraphBlock;
      return Text(_plainText(b.runs), style: tokens.body);
    });

    registry.register<HeadingBlock>((block, tokens, _) {
      final b = block as HeadingBlock;
      return Text(_plainText(b.runs), style: _headingStyle(tokens, b.level));
    });

    registry.register<ListBlock>((block, tokens, _) {
      final b = block as ListBlock;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final item in b.items)
            Text(
              '• ${_plainText(item.runs)}',
              style: tokens.body,
            ),
        ],
      );
    });

    registry.register<BlockquoteBlock>((block, _, __) {
      return Text('BlockquoteBlock');
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

TextStyle _headingStyle(MarkdownTokens tokens, int level) {
  return switch (level) {
    1 => tokens.h1,
    2 => tokens.h2,
    3 => tokens.h3,
    4 => tokens.h4,
    5 => tokens.h5,
    _ => tokens.h6,
  };
}

String _plainText(List<InlineRun> runs) {
  final buffer = StringBuffer();
  for (final run in runs) {
    switch (run) {
      case TextRun(:final text):
        buffer.write(text);
      case StrongRun(:final children):
        buffer.write(_plainText(children));
      case EmphasisRun(:final children):
        buffer.write(_plainText(children));
      case StrikeRun(:final children):
        buffer.write(_plainText(children));
      case CodeRun(:final text):
        buffer.write(text);
      case LinkRun(:final children):
        buffer.write(_plainText(children));
      case ImageRun(:final alt):
        buffer.write(alt ?? '');
    }
  }
  return buffer.toString();
}
