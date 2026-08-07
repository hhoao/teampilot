import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter/widgets.dart';

typedef AiToolCallBubbleBuilder = Widget Function(
  BuildContext context,
  AiToolCallPart part,
);

/// Name-keyed custom bubbles for tool calls, consulted by [AiToolCallPartView]
/// before any generic chrome. Builders are keyed by lowercase tool name; a
/// match short-circuits the generic trigger row.
///
/// [updateShouldNotify] is deliberately false: the registry is static per host
/// for the widget's lifetime, so dependents never need a scope-driven rebuild.
class AiToolCallBubbleScope extends InheritedWidget {
  const AiToolCallBubbleScope({
    required this.builders,
    required super.child,
    super.key,
  });

  final Map<String, AiToolCallBubbleBuilder> builders;

  static AiToolCallBubbleScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<AiToolCallBubbleScope>();
  }

  @override
  bool updateShouldNotify(AiToolCallBubbleScope oldWidget) => false;
}
