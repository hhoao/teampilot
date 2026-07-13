import 'package:flutter/material.dart';

/// Theme tokens for AI message UI (bubbles, tool cards, spacing).
@immutable
class AiMessageTheme extends ThemeExtension<AiMessageTheme> {
  const AiMessageTheme({
    this.userBubbleColor,
    this.assistantBubbleColor,
    this.toolCardColor,
    this.toolCardBorderColor,
    this.messageSpacing = 12,
    this.threadPadding = const EdgeInsets.symmetric(horizontal: 16),
  });

  final Color? userBubbleColor;
  final Color? assistantBubbleColor;
  final Color? toolCardColor;
  final Color? toolCardBorderColor;
  final double messageSpacing;
  final EdgeInsets threadPadding;

  @override
  AiMessageTheme copyWith({
    Color? userBubbleColor,
    Color? assistantBubbleColor,
    Color? toolCardColor,
    Color? toolCardBorderColor,
    double? messageSpacing,
    EdgeInsets? threadPadding,
  }) {
    return AiMessageTheme(
      userBubbleColor: userBubbleColor ?? this.userBubbleColor,
      assistantBubbleColor: assistantBubbleColor ?? this.assistantBubbleColor,
      toolCardColor: toolCardColor ?? this.toolCardColor,
      toolCardBorderColor: toolCardBorderColor ?? this.toolCardBorderColor,
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
      toolCardColor: Color.lerp(toolCardColor, other.toolCardColor, t),
      toolCardBorderColor: Color.lerp(
        toolCardBorderColor,
        other.toolCardBorderColor,
        t,
      ),
      messageSpacing: messageSpacing + (other.messageSpacing - messageSpacing) * t,
      threadPadding: EdgeInsets.lerp(threadPadding, other.threadPadding, t)!,
    );
  }
}
