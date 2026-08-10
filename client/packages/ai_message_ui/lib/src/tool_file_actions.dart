import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter/material.dart';

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

  static const _fallback = AiToolFileActions(
    fileResolver: _NoopFileResolver(),
    editResolver: _NoopEditResolver(),
    shellResolver: _NoopShellResolver(),
  );

  static AiToolFileActions of(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<_AiToolFileActionsScope>()
            ?.actions ??
        _fallback;
  }
}

class _NoopFileResolver implements AiToolFileTargetResolver {
  const _NoopFileResolver();

  @override
  AiToolFileTarget? resolve(AiToolCallPart part) => null;
}

class _NoopEditResolver implements AiEditToolTargetResolver {
  const _NoopEditResolver();

  @override
  AiEditToolTarget? resolve(AiToolCallPart part) => null;
}

class _NoopShellResolver implements AiShellToolTargetResolver {
  const _NoopShellResolver();

  @override
  AiShellToolTarget? resolve(AiToolCallPart part) => null;
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
