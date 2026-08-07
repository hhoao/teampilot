import 'package:flutter/widgets.dart';

/// How oversized content renders inside the parent scroll.
enum ContentDisplayMode {
  /// Collapse to a mask; expand into a fixed-height scroll shell (today).
  foldFixedHeight,
  /// Collapse to a mask; expand to full natural height in the flow.
  foldExpandFull,
  /// Always full natural height in the flow (no mask).
  flatten,
}

/// Carries per-surface display modes down to markdown renderers.
class MarkdownDisplayModeScope extends InheritedWidget {
  const MarkdownDisplayModeScope({
    super.key,
    this.userMessageMode = ContentDisplayMode.foldFixedHeight,
    this.codeBlockMode = ContentDisplayMode.foldFixedHeight,
    required super.child,
  });

  final ContentDisplayMode userMessageMode;
  final ContentDisplayMode codeBlockMode;

  static MarkdownDisplayModeScope? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<MarkdownDisplayModeScope>();
  }

  static ContentDisplayMode userMessageOf(BuildContext context) =>
      maybeOf(context)?.userMessageMode ?? ContentDisplayMode.foldFixedHeight;

  static ContentDisplayMode codeBlockOf(BuildContext context) =>
      maybeOf(context)?.codeBlockMode ?? ContentDisplayMode.foldFixedHeight;

  @override
  bool updateShouldNotify(MarkdownDisplayModeScope oldWidget) =>
      userMessageMode != oldWidget.userMessageMode ||
      codeBlockMode != oldWidget.codeBlockMode;
}
