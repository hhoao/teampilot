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
  MarkdownImageSizing? sizing,
}) {
  final height = (tokens.body.fontSize ?? 14) * (tokens.body.height ?? 1.4);
  final widgetImage = resolvers.buildImageWidget?.call(
    src,
    inline: inline,
    inlineHeight: height,
  );
  if (widgetImage != null) {
    if (inline) return widgetImage;
    return _blockSized(widgetImage, sizing);
  }
  final provider = resolvers.resolveImage?.call(src);
  if (provider != null) {
    if (inline) {
      return Image(image: provider, height: height, fit: BoxFit.contain);
    }
    // Raster block images need the width hint on the Image widget itself:
    // a SizedBox-wrapped Image under unbounded height renders square
    // (RenderImage fills maxWidth when no intrinsic size is set), while the
    // width parameter makes contain honor the image's aspect ratio.
    if (sizing?.percentWidth != null || sizing?.pixelWidth != null) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final maxW = constraints.maxWidth;
          final double? width =
              sizing?.percentWidth != null && maxW.isFinite
              ? maxW * sizing!.percentWidth!
              : sizing!.pixelWidth;
          // No per-image Center here: an unconstrained Center expands to the
          // full block width, which inside a Wrap forces single-item runs
          // (row centering belongs to the Wrap's alignment).
          return ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: maxW.isFinite ? maxW : double.infinity,
            ),
            child: Image(
              image: provider,
              width: width,
              height: sizing.pixelHeight,
              fit: BoxFit.contain,
            ),
          );
        },
      );
    }
    return _blockSized(Image(image: provider, fit: BoxFit.contain), sizing);
  }
  return _imagePlaceholder(alt ?? src, tokens);
}

/// Block images: cap to available width (README screenshots), keep intrinsic
/// size when smaller, and honor explicit sizing hints (HTML `width`/`style`)
/// plus centering like browser `max-width: 100%` semantics.
Widget _blockSized(Widget child, MarkdownImageSizing? sizing) {
  return LayoutBuilder(
    builder: (context, constraints) {
      final maxW = constraints.maxWidth;
      final finiteMax = maxW.isFinite ? maxW : double.infinity;
      Widget result = child;
      double? width;
      if (sizing?.percentWidth != null && maxW.isFinite) {
        width = maxW * sizing!.percentWidth!;
      } else if (sizing?.pixelWidth != null) {
        width = sizing!.pixelWidth;
      }
      if (width != null) result = SizedBox(width: width, child: result);
      if (sizing?.pixelHeight != null) {
        result = SizedBox(height: sizing!.pixelHeight, child: result);
      }
      if (sizing?.center ?? false) result = Center(child: result);
      return ConstrainedBox(
        constraints: BoxConstraints(maxWidth: finiteMax),
        child: result,
      );
    },
  );
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
          style: tokens.emphasisStyle(tokens.body),
          strutStyle: forcedStrut(tokens.body),
        ),
      ),
    ],
  );
}
