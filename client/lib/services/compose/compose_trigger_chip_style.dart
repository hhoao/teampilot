import 'package:flutter/material.dart';

import '../inline_token/inline_token_chip_mirror.dart';
import '../inline_token/inline_token_palette.dart';

export '../inline_token/inline_token_chip_mirror.dart';
export '../inline_token/inline_token_palette.dart';

/// Compose-specific alias for [defaultInlineTokenPattern].
final RegExp composeInlineTokenPattern = defaultInlineTokenPattern;

const double composeTokenPillLeftBleed = inlineTokenPillLeftBleed;
const double composeTokenPillHorizontalPadding = inlineTokenPillHorizontalPadding;

double composeTokenPillWidth(double layoutWidth) =>
    inlineTokenPillWidth(layoutWidth);

List<InlineSpan> buildComposeMirrorLayoutSpans({
  required String text,
  required TextStyle baseStyle,
}) {
  return buildInlineTokenMirrorLayoutSpans(
    text: text,
    baseStyle: baseStyle,
    tokenPattern: composeInlineTokenPattern,
  );
}

/// Compose alias for [InlineTokenChipMirror].
class ComposeTriggerStyledMirror extends StatelessWidget {
  const ComposeTriggerStyledMirror({
    required this.text,
    required this.baseStyle,
    required this.minLines,
    required this.maxLines,
    this.scrollOffset = 0,
    super.key,
  });

  final String text;
  final TextStyle baseStyle;
  final int minLines;
  final int maxLines;
  final double scrollOffset;

  @override
  Widget build(BuildContext context) {
    return InlineTokenChipMirror(
      text: text,
      baseStyle: baseStyle,
      minLines: minLines,
      maxLines: maxLines,
      scrollOffset: scrollOffset,
      tokenPattern: composeInlineTokenPattern,
      resolvePalette: resolveSlashAtTokenPalette,
    );
  }
}
