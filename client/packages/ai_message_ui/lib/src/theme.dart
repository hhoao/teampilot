import 'package:flutter/material.dart';

/// Theme tokens for AI message UI. Thin stub — expand in later tasks.
@immutable
class AiMessageTheme extends ThemeExtension<AiMessageTheme> {
  const AiMessageTheme({
    this.userBubbleColor,
    this.assistantBubbleColor,
    this.messageSpacing = 12,
    this.threadPadding = const EdgeInsets.symmetric(horizontal: 16),
  });

  final Color? userBubbleColor;
  final Color? assistantBubbleColor;
  final double messageSpacing;
  final EdgeInsets threadPadding;

  @override
  AiMessageTheme copyWith({
    Color? userBubbleColor,
    Color? assistantBubbleColor,
    double? messageSpacing,
    EdgeInsets? threadPadding,
  }) {
    return AiMessageTheme(
      userBubbleColor: userBubbleColor ?? this.userBubbleColor,
      assistantBubbleColor: assistantBubbleColor ?? this.assistantBubbleColor,
      messageSpacing: messageSpacing ?? this.messageSpacing,
      threadPadding: threadPadding ?? this.threadPadding,
    );
  }

  @override
  AiMessageTheme lerp(ThemeExtension<AiMessageTheme>? other, double t) {
    if (other is! AiMessageTheme) return this;
    return AiMessageTheme(
      userBubbleColor: Color.lerp(userBubbleColor, other.userBubbleColor, t),
      assistantBubbleColor: Color.lerp(
        assistantBubbleColor,
        other.assistantBubbleColor,
        t,
      ),
      messageSpacing: messageSpacing + (other.messageSpacing - messageSpacing) * t,
      threadPadding: EdgeInsets.lerp(threadPadding, other.threadPadding, t)!,
    );
  }
}
