import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Link and image resolution hooks for [MarkdownView].
///
/// Images resolve through two layers: [buildImageWidget] first (widget-level
/// resolvers like flutter_svg, which have no [ImageProvider]), then
/// [resolveImage] for raster [ImageProvider]s.
@immutable
class MarkdownResolvers {
  const MarkdownResolvers({
    this.onLinkTap,
    this.resolveImage,
    this.buildImageWidget,
    this.createLinkRecognizer,
  });

  final void Function(String href)? onLinkTap;
  final ImageProvider? Function(String src)? resolveImage;

  /// Widget-level image source. Return null to fall through to
  /// [resolveImage] / the placeholder.
  ///
  /// [inline] is true for inline images; [inlineHeight] is the line box the
  /// caller should fit into (matches the `Image` height in that case).
  final Widget? Function(
    String src, {
    required bool inline,
    required double inlineHeight,
  })? buildImageWidget;

  /// Owns [TapGestureRecognizer]s for link spans. Set by [MarkdownView] so
  /// recognizers are disposed across rebuilds.
  final GestureRecognizer? Function(String href)? createLinkRecognizer;
}

/// Explicit sizing hints for markdown images, sourced from HTML `<img>`
/// attributes (`width`, `height`, `style="width: 70%"`) and block-level
/// centering (`<p align="center">`). Mirrors browser `max-width: 100%`
/// semantics: intrinsic size unless hinted otherwise.
@immutable
class MarkdownImageSizing {
  const MarkdownImageSizing({
    this.percentWidth,
    this.pixelWidth,
    this.pixelHeight,
    this.center = false,
  });

  /// Fraction of the available width (0..1), from `width: 70%`.
  final double? percentWidth;

  /// Absolute width in logical pixels, from `width="100"` or `width: 100px`.
  final double? pixelWidth;

  /// Absolute height in logical pixels, from `height="220"`.
  final double? pixelHeight;

  /// Center horizontally within the containing block.
  final bool center;

  /// Copy without block-level centering (row centering handled by caller,
  /// e.g. a Wrap with WrapAlignment).
  MarkdownImageSizing withoutCenter() => MarkdownImageSizing(
        percentWidth: percentWidth,
        pixelWidth: pixelWidth,
        pixelHeight: pixelHeight,
      );
}
