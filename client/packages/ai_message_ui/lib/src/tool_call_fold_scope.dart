import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter/widgets.dart';

typedef AiToolCallFoldPredicate = bool Function(AiToolCallPart part);

/// Host-injected fold policy for chain-of-thought grouping. Null predicate
/// (scope absent) folds every tool call — the historical default.
class AiToolCallFoldScope extends InheritedWidget {
  const AiToolCallFoldScope({
    required this.shouldFold,
    required super.child,
    super.key,
  });

  final AiToolCallFoldPredicate shouldFold;

  static AiToolCallFoldScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AiToolCallFoldScope>();

  @override
  bool updateShouldNotify(AiToolCallFoldScope oldWidget) =>
      shouldFold != oldWidget.shouldFold;
}
