import 'package:flutter/material.dart';

/// Top contentPadding — slightly taller than sides so ascenders clear the border.
const double kAppTextareaTopPadding = 16;

/// Bottom contentPadding before the resize-grip inset.
const double kAppTextareaBottomPadding = 12;

/// Horizontal contentPadding (each side). Matches shadcn `px-3`.
const double kAppTextareaHorizontalPadding = 12;

/// Extra bottom inset so the last line clears the resize grip
/// (shadcn `scrollbarPadding: EdgeInsets.only(bottom: 10)`).
const double kAppTextareaBottomInset = 10;

/// Default multiline [InputDecoration.contentPadding] for [AppTextarea].
const EdgeInsets kAppTextareaContentPadding = EdgeInsets.only(
  left: kAppTextareaHorizontalPadding,
  right: kAppTextareaHorizontalPadding,
  top: kAppTextareaTopPadding,
  bottom: kAppTextareaBottomPadding + kAppTextareaBottomInset,
);

/// Outline border width budget for outer height (1px idle; 1.5px when focused).
///
/// Top + bottom are applied via `borderWidth * 2` in
/// [appTextareaHeightForLines] / [appTextareaVerticalChrome].
const double kAppTextareaBorderWidth = 1;

/// Total vertical chrome (padding + border) for the AppTextarea path.
///
/// Convention: [AppTextarea] `minHeight` / `maxHeight` are **outer** shell
/// heights including this chrome. Compose / borderless [AppTextareaShell]
/// children should keep using `lineHeight * n` (chrome = 0).
double appTextareaVerticalChrome({
  double topPadding = kAppTextareaTopPadding,
  double bottomPadding = kAppTextareaBottomPadding,
  double bottomInset = kAppTextareaBottomInset,
  double borderWidth = kAppTextareaBorderWidth,
}) =>
    topPadding + bottomPadding + bottomInset + borderWidth * 2;

/// Outer shell height for [lines] of [style], including AppTextarea chrome.
double appTextareaHeightForLines(
  TextStyle style, {
  required int lines,
  double topPadding = kAppTextareaTopPadding,
  double bottomPadding = kAppTextareaBottomPadding,
  double bottomInset = kAppTextareaBottomInset,
  double borderWidth = kAppTextareaBorderWidth,
}) {
  assert(lines >= 1);
  final fontSize = style.fontSize ?? 14;
  final heightFactor = style.height ?? 20 / 14;
  final lineHeight = fontSize * heightFactor;
  return lines * lineHeight +
      appTextareaVerticalChrome(
        topPadding: topPadding,
        bottomPadding: bottomPadding,
        bottomInset: bottomInset,
        borderWidth: borderWidth,
      );
}
