import 'package:flutter/material.dart';

import 'thinking_process_summary.dart';

/// Host-injected copy for ai_message_ui (package stays l10n-free).
@immutable
class AiMessageStrings {
  const AiMessageStrings({
    this.usedTool = 'Used tool',
    this.cancelledTool = 'Cancelled tool',
    this.formatToolsUsed = _defaultToolsUsed,
    this.reasoning = 'Reasoning',
    this.result = 'Result',
    this.copy = 'Copy',
    this.copied = 'Copied',
    this.exportMarkdown = 'Export Markdown',
    this.code = 'code',
    this.messageIncomplete = 'Message incomplete',
    this.messageCancelled = 'Message cancelled',
    this.scrollToBottom = 'Scroll to bottom',
    this.showMore = 'Show more',
    this.showLess = 'Show less',
    this.thinkingProcess = 'Thinking process',
    this.formatThinkingProcessSteps = _defaultThinkingProcessSteps,
    this.formatThinkingProcessSummary = defaultThinkingProcessSummaryLabel,
  });

  final String usedTool;
  final String cancelledTool;
  final String Function(Object count) formatToolsUsed;
  final String thinkingProcess;
  final String Function(Object count) formatThinkingProcessSteps;
  final AiThinkingProcessSummaryFormatter formatThinkingProcessSummary;
  final String reasoning;
  final String result;
  final String copy;
  final String copied;
  final String exportMarkdown;
  final String code;
  final String messageIncomplete;
  final String messageCancelled;
  final String scrollToBottom;
  final String showMore;
  final String showLess;

  String toolsUsedLabel(int count) => formatToolsUsed(count);

  static String _defaultToolsUsed(Object count) => 'Used $count tools';

  static String _defaultThinkingProcessSteps(Object count) =>
      'Thinking process · $count steps';

  static AiMessageStrings of(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<_AiMessageStringsScope>()
            ?.strings ??
        const AiMessageStrings();
  }
}

class AiMessageStringsScope extends StatelessWidget {
  const AiMessageStringsScope({
    required this.strings,
    required this.child,
    super.key,
  });

  final AiMessageStrings strings;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return _AiMessageStringsScope(strings: strings, child: child);
  }
}

class _AiMessageStringsScope extends InheritedWidget {
  const _AiMessageStringsScope({required this.strings, required super.child});

  final AiMessageStrings strings;

  @override
  bool updateShouldNotify(_AiMessageStringsScope oldWidget) =>
      !identical(strings, oldWidget.strings);
}
