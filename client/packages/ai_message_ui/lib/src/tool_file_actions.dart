import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter/material.dart';

import 'default_tool_resolvers.dart';
import 'edit/edit_line_highlighter.dart';

/// Host-injected resolvers + open handler for tool-call targets.
@immutable
class AiToolFileActions {
  const AiToolFileActions({
    required this.fileResolver,
    required this.editResolver,
    required this.shellResolver,
    this.onOpenFile,
    this.lineHighlighter = const PlainEditLineHighlighter(),
  });

  final AiToolFileTargetResolver fileResolver;
  final AiEditToolTargetResolver editResolver;
  final AiShellToolTargetResolver shellResolver;
  final Future<void> Function(AiToolFileTarget target)? onOpenFile;
  final AiEditLineHighlighter lineHighlighter;

  /// Without a scope the package falls back to its built-in file resolver so
  /// read/write summary chrome still renders; edit and shell targets stay
  /// host-owned.
  static const _fallback = AiToolFileActions(
    fileResolver: DefaultAiToolFileTargetResolver(),
    editResolver: NoopEditToolTargetResolver(),
    shellResolver: DefaultAiShellToolTargetResolver(),
  );

  static AiToolFileActions of(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<_AiToolFileActionsScope>()
            ?.actions ??
        _fallback;
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
