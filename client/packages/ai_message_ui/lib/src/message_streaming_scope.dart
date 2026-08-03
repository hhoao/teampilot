import 'package:flutter/widgets.dart';

/// Propagates whether the current [AiMessage] is still streaming so text
/// parts can throttle markdown compile without delaying the final frame.
class AiMessageStreamingScope extends InheritedWidget {
  const AiMessageStreamingScope({
    required this.streaming,
    required super.child,
    super.key,
  });

  final bool streaming;

  static bool of(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<AiMessageStreamingScope>()
            ?.streaming ??
        false;
  }

  @override
  bool updateShouldNotify(AiMessageStreamingScope oldWidget) =>
      streaming != oldWidget.streaming;
}
