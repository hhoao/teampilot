import 'package:flutter/material.dart';

/// Host-injected markdown link tap handler.
@immutable
class AiMarkdownLinkActions {
  const AiMarkdownLinkActions({this.onLinkTap});

  final Future<void> Function(String href)? onLinkTap;

  static const _fallback = AiMarkdownLinkActions();

  static AiMarkdownLinkActions of(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<_AiMarkdownLinkActionsScope>()
            ?.actions ??
        _fallback;
  }
}

class AiMarkdownLinkActionsScope extends StatelessWidget {
  const AiMarkdownLinkActionsScope({
    required this.actions,
    required this.child,
    super.key,
  });

  final AiMarkdownLinkActions actions;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return _AiMarkdownLinkActionsScope(actions: actions, child: child);
  }
}

class _AiMarkdownLinkActionsScope extends InheritedWidget {
  const _AiMarkdownLinkActionsScope({
    required this.actions,
    required super.child,
  });

  final AiMarkdownLinkActions actions;

  @override
  bool updateShouldNotify(_AiMarkdownLinkActionsScope oldWidget) =>
      !identical(actions, oldWidget.actions);
}
