import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter/material.dart';

/// Host-injected resolvers for task / ask-user / workflow tool chrome.
@immutable
class AiSpecialToolActions {
  const AiSpecialToolActions({
    this.taskResolver = const _NoopTaskResolver(),
    this.askUserResolver = const _NoopAskUserResolver(),
    this.workflowResolver = const _NoopWorkflowResolver(),
  });

  final AiTaskToolResolver taskResolver;
  final AiAskUserResolver askUserResolver;
  final AiWorkflowResolver workflowResolver;

  static const fallback = AiSpecialToolActions();

  static AiSpecialToolActions of(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<_AiSpecialToolActionsScope>()
            ?.actions ??
        fallback;
  }
}

class _NoopTaskResolver implements AiTaskToolResolver {
  const _NoopTaskResolver();

  @override
  AiTaskToolTarget? resolve(AiToolCallPart part) => null;
}

class _NoopAskUserResolver implements AiAskUserResolver {
  const _NoopAskUserResolver();

  @override
  AiAskUserTarget? resolve(AiToolCallPart part) => null;
}

class _NoopWorkflowResolver implements AiWorkflowResolver {
  const _NoopWorkflowResolver();

  @override
  AiWorkflowTarget? resolve(AiToolCallPart part) => null;
}

class AiSpecialToolActionsScope extends StatelessWidget {
  const AiSpecialToolActionsScope({
    required this.actions,
    required this.child,
    super.key,
  });

  final AiSpecialToolActions actions;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return _AiSpecialToolActionsScope(actions: actions, child: child);
  }
}

class _AiSpecialToolActionsScope extends InheritedWidget {
  const _AiSpecialToolActionsScope({
    required this.actions,
    required super.child,
  });

  final AiSpecialToolActions actions;

  @override
  bool updateShouldNotify(_AiSpecialToolActionsScope oldWidget) =>
      !identical(actions, oldWidget.actions);
}
