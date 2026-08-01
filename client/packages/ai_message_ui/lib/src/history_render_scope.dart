import 'package:flutter/widgets.dart';

import 'package:tp_markdown/tp_markdown.dart';

/// History-review render policy (Claude Code webview-aligned).
///
/// Live chat leaves this scope absent so bodies render fully.
class AiHistoryRenderScope extends InheritedWidget {
  const AiHistoryRenderScope({
    required super.child,
    this.contentBudget = ContentCollapseBudget.claudeAligned,
    super.key,
  });

  /// IR budget while markdown is collapsed (≈ Claude `oYe` maxHeight 250).
  final ContentCollapseBudget contentBudget;

  static AiHistoryRenderScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<AiHistoryRenderScope>();
  }

  @override
  bool updateShouldNotify(AiHistoryRenderScope oldWidget) =>
      contentBudget.maxBlocks != oldWidget.contentBudget.maxBlocks ||
      contentBudget.maxTableRows != oldWidget.contentBudget.maxTableRows ||
      contentBudget.maxChars != oldWidget.contentBudget.maxChars;
}
