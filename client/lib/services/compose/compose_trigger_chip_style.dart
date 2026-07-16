import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../inline_token/inline_token_palette.dart';

export '../inline_token/inline_token_palette.dart';

/// Compose-specific alias for [defaultInlineTokenPattern].
final RegExp composeInlineTokenPattern = defaultInlineTokenPattern;

const double composeTokenPillLeftBleed = tpTokenPillLeftBleed;
const double composeTokenPillHorizontalPadding = tpTokenPillHorizontalPadding;

double composeTokenPillWidth(double layoutWidth) =>
    tpTokenPillWidth(layoutWidth);

List<InlineSpan> buildComposeMirrorLayoutSpans({
  required String text,
  required TextStyle baseStyle,
}) {
  return buildTpTokenMirrorLayoutSpans(
    text: text,
    baseStyle: baseStyle,
    tokenPattern: composeInlineTokenPattern,
  );
}

/// Compose alias for [TpTokenChipMirror].
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
    return TpTokenChipMirror(
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
