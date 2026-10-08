import 'package:flutter/material.dart';

/// Overlay-local top-left for a compose trigger menu anchored at the caret.
Offset? composeTriggerMenuAnchor({
  required BuildContext context,
  required RenderBox fieldBox,
  required TextEditingValue value,
  required TextStyle textStyle,
  required double maxWidth,
  int maxLines = 6,
  double gapBelowCaret = 4,
}) {
  final overlayBox =
      Overlay.of(context).context.findRenderObject() as RenderBox?;
  if (overlayBox == null) return null;

  final text = value.text;
  final cursor = value.selection.isValid
      ? value.selection.baseOffset
      : text.length;
  final caretOffset = cursor.clamp(0, text.length);

  final painter = TextPainter(
    text: TextSpan(text: text.substring(0, caretOffset), style: textStyle),
    textDirection: Directionality.of(context),
    maxLines: maxLines,
  )..layout(maxWidth: maxWidth);

  final caret = painter.getOffsetForCaret(
    TextPosition(offset: caretOffset),
    Rect.zero,
  );
  final lineHeight = painter.preferredLineHeight;
  final caretBottomGlobal = fieldBox.localToGlobal(
    caret + Offset(0, lineHeight),
  );
  final fieldTopLeft = overlayBox.globalToLocal(
    fieldBox.localToGlobal(Offset.zero),
  );
  final caretBottom = overlayBox.globalToLocal(caretBottomGlobal);

  return Offset(fieldTopLeft.dx, caretBottom.dy + gapBelowCaret);
}
