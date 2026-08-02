import 'package:flutter/material.dart';

import '../ir/markdown_document.dart';
import '../registry/markdown_resolvers.dart';
import '../tokens/markdown_tokens.dart';
import 'inline_spans.dart';

Widget buildImageBlock(
  ImageBlock block,
  MarkdownTokens tokens,
  MarkdownResolvers resolvers,
) {
  return buildMarkdownImage(
    src: block.src,
    alt: block.alt,
    tokens: tokens,
    resolvers: resolvers,
  );
}

Widget buildRawLiteralBlock(RawLiteralBlock block, MarkdownTokens tokens) {
  return SelectableText(
    block.rawMarkdown,
    style: tokens.codeBlock,
    strutStyle: forcedStrut(tokens.codeBlock),
  );
}

/// Shared image widget for block and inline markdown images.
Widget buildMarkdownImage({
  required String src,
  required String? alt,
  required MarkdownTokens tokens,
  required MarkdownResolvers resolvers,
  bool inline = false,
}) {
  final provider = resolvers.resolveImage?.call(src);
  if (provider != null) {
    if (inline) {
      final height = (tokens.body.fontSize ?? 14) * (tokens.body.height ?? 1.4);
      return Image(image: provider, height: height, fit: BoxFit.contain);
    }
    // Block images: cap to available width (README screenshots), keep intrinsic
    // size when smaller so tiny assets are not upscaled.
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth;
        return ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: maxW.isFinite ? maxW : double.infinity,
          ),
          child: Image(image: provider, fit: BoxFit.contain),
        );
      },
    );
  }
  return _imagePlaceholder(alt ?? src, tokens);
}

Widget _imagePlaceholder(String label, MarkdownTokens tokens) {
  final fontSize = tokens.body.fontSize ?? 14;
  return Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(
        Icons.image_outlined,
        size: fontSize + 2,
        color: tokens.body.color?.withValues(alpha: 0.7),
      ),
      const SizedBox(width: 6),
      Flexible(
        child: Text(
          label,
          style: tokens.body.copyWith(fontStyle: FontStyle.italic),
          strutStyle: forcedStrut(tokens.body),
        ),
      ),
    ],
  );
}
