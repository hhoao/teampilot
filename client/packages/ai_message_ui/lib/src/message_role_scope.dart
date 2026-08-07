import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter/widgets.dart';

/// Propagates the current [AiMessage]'s role so text parts can apply
/// role-specific collapse policy (e.g. user messages collapse as whole pastes;
/// assistant prose renders fully).
class AiMessageRoleScope extends InheritedWidget {
  const AiMessageRoleScope({
    required this.role,
    required super.child,
    super.key,
  });

  final AiRole role;

  static AiRole of(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<AiMessageRoleScope>()
            ?.role ??
        AiRole.assistant;
  }

  @override
  bool updateShouldNotify(AiMessageRoleScope oldWidget) =>
      role != oldWidget.role;
}
