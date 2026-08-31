import 'package:flutter/material.dart';

/// Host-injected open handler for Agent/Task tool-call rows.
@immutable
class AiToolSubagentActions {
  const AiToolSubagentActions({
    this.onOpenSubagent,
    this.isSubagentTool,
  });

  /// Union of every built-in CLI's `subagentToolNames` (Claude, Codex, Cursor,
  /// FlashskyAI, OpenCode). Used when the host does not inject a predicate so
  /// subagent chrome still matches cross-CLI tool names by default.
  static const defaultSubagentToolNames = {
    'agent',
    'task',
    'workflow',
    'spawn_agent',
  };

  final Future<void> Function(String toolCallId)? onOpenSubagent;
  final bool Function(String toolName)? isSubagentTool;

  static AiToolSubagentActions of(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<_AiToolSubagentActionsScope>()
            ?.actions ??
        const AiToolSubagentActions();
  }
}

class AiToolSubagentActionsScope extends StatelessWidget {
  const AiToolSubagentActionsScope({
    required this.actions,
    required this.child,
    super.key,
  });

  final AiToolSubagentActions actions;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return _AiToolSubagentActionsScope(actions: actions, child: child);
  }
}

class _AiToolSubagentActionsScope extends InheritedWidget {
  const _AiToolSubagentActionsScope({
    required this.actions,
    required super.child,
  });

  final AiToolSubagentActions actions;

  @override
  bool updateShouldNotify(_AiToolSubagentActionsScope oldWidget) =>
      !identical(actions, oldWidget.actions);
}
