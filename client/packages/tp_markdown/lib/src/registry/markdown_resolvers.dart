import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Link and image resolution hooks for [MarkdownView].
@immutable
class MarkdownResolvers {
  const MarkdownResolvers({
    this.onLinkTap,
    this.resolveImage,
    this.createLinkRecognizer,
  });

  final void Function(String href)? onLinkTap;
  final ImageProvider? Function(String src)? resolveImage;

  /// Owns [TapGestureRecognizer]s for link spans. Set by [MarkdownView] so
  /// recognizers are disposed across rebuilds.
  final GestureRecognizer? Function(String href)? createLinkRecognizer;
}
