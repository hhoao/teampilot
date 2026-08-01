import 'package:flutter/material.dart';

/// Link and image resolution hooks for [MarkdownView].
@immutable
class MarkdownResolvers {
  const MarkdownResolvers({
    this.onLinkTap,
    this.resolveImage,
  });

  final void Function(String href)? onLinkTap;
  final ImageProvider? Function(String src)? resolveImage;
}
