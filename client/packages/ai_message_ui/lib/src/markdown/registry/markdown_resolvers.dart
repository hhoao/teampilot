import 'package:flutter/material.dart';

/// Used by [AiTextPartView.onTapLink].
typedef MarkdownTapLinkCallback = void Function(
  String text,
  String? href,
  String title,
);

/// Link and image resolution hooks for the semantic markdown renderer.
@immutable
class MarkdownResolvers {
  const MarkdownResolvers({
    this.onLinkTap,
    this.resolveImage,
  });

  final void Function(String href)? onLinkTap;
  final ImageProvider? Function(String src)? resolveImage;
}
