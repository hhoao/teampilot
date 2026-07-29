import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter/material.dart';

import 'edit/edit_line_highlighter.dart';

/// Host-injected resolver + open handler for tool-call file targets.
@immutable
class AiToolFileActions {
  const AiToolFileActions({
    this.resolver = const DefaultAiToolFileTargetResolver(),
    this.onOpenFile,
    this.enrichEditContext,
    this.lineHighlighter = const PlainEditLineHighlighter(),
  });

  final AiToolFileTargetResolver resolver;
  final Future<void> Function(AiToolFileTarget target)? onOpenFile;
  final Future<AiEditHunk> Function(AiEditHunk hunk)? enrichEditContext;
  final AiEditLineHighlighter lineHighlighter;

  static AiToolFileActions of(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<_AiToolFileActionsScope>()
            ?.actions ??
        const AiToolFileActions();
  }
}

class AiToolFileActionsScope extends StatelessWidget {
  const AiToolFileActionsScope({
    required this.actions,
    required this.child,
    super.key,
  });

  final AiToolFileActions actions;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return _AiToolFileActionsScope(actions: actions, child: child);
  }
}

class _AiToolFileActionsScope extends InheritedWidget {
  const _AiToolFileActionsScope({
    required this.actions,
    required super.child,
  });

  final AiToolFileActions actions;

  @override
  bool updateShouldNotify(_AiToolFileActionsScope oldWidget) =>
      !identical(actions, oldWidget.actions);
}
