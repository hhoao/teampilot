import 'package:flutter/material.dart';

import 'markdown/compiled_markdown_style.dart';

/// Theme tokens aligned with assistant-ui Thread / Message / ToolFallback.
///
/// Hosts **must** supply [markdown] from their warmup-aligned typography
/// (TeamPilot: [buildAppCompiledMarkdownStyle]). Package tests use
/// [AiMessageTheme.test].
@immutable
class AiMessageTheme extends ThemeExtension<AiMessageTheme> {
  const AiMessageTheme({
    required this.markdown,
    this.userBubbleColor,
    this.userBubbleForeground,
    this.mutedSurface,
    this.toolTriggerColor,
    this.toolPanelColor,
    this.reasoningBorderColor,
    this.messageSpacing = 24,
    this.partSpacing = 8,
    this.userBubbleRadius = 12,
    this.panelRadius = 8,
    this.codeBlockRadius = 12,
    // assistant-ui: --thread-max-width 44rem ≈ 704
    this.threadMaxWidth = 704,
    this.threadHorizontalPadding = 16,
    this.cotExpandReasoningOnOpen = false,
    this.cotExpandToolsOnOpen = false,
  });

  /// Product / test fixture with [CompiledMarkdownStyle.test] typography.
  factory AiMessageTheme.test({
    ColorScheme? scheme,
    Color? userBubbleColor,
    Color? userBubbleForeground,
    Color? mutedSurface,
    Color? toolTriggerColor,
    Color? toolPanelColor,
    Color? reasoningBorderColor,
    double messageSpacing = 24,
    double partSpacing = 8,
    double userBubbleRadius = 12,
    double panelRadius = 8,
    double codeBlockRadius = 12,
    double threadMaxWidth = 704,
    double threadHorizontalPadding = 16,
    bool cotExpandReasoningOnOpen = false,
    bool cotExpandToolsOnOpen = false,
  }) {
    return AiMessageTheme(
      markdown: CompiledMarkdownStyle.test(
        scheme: scheme,
        codeBlockRadius: codeBlockRadius,
      ),
      userBubbleColor: userBubbleColor,
      userBubbleForeground: userBubbleForeground,
      mutedSurface: mutedSurface,
      toolTriggerColor: toolTriggerColor,
      toolPanelColor: toolPanelColor,
      reasoningBorderColor: reasoningBorderColor,
      messageSpacing: messageSpacing,
      partSpacing: partSpacing,
      userBubbleRadius: userBubbleRadius,
      panelRadius: panelRadius,
      codeBlockRadius: codeBlockRadius,
      threadMaxWidth: threadMaxWidth,
      threadHorizontalPadding: threadHorizontalPadding,
      cotExpandReasoningOnOpen: cotExpandReasoningOnOpen,
      cotExpandToolsOnOpen: cotExpandToolsOnOpen,
    );
  }

  /// Single source for compiled markdown + [MarkdownBody] fallback styles.
  final CompiledMarkdownStyle markdown;

  final Color? userBubbleColor;
  final Color? userBubbleForeground;
  final Color? mutedSurface;
  final Color? toolTriggerColor;
  final Color? toolPanelColor;
  final Color? reasoningBorderColor;

  final double messageSpacing;
  final double partSpacing;
  final double userBubbleRadius;
  final double panelRadius;
  final double codeBlockRadius;
  final double threadMaxWidth;
  final double threadHorizontalPadding;
  final bool cotExpandReasoningOnOpen;
  final bool cotExpandToolsOnOpen;

  static AiMessageTheme of(BuildContext context) {
    return Theme.of(context).extension<AiMessageTheme>() ??
        AiMessageTheme.test();
  }

  Color resolveUserBubble(ColorScheme scheme) =>
      userBubbleColor ?? scheme.surfaceContainerHighest;

  Color resolveUserForeground(ColorScheme scheme) =>
      userBubbleForeground ?? scheme.onSurface;

  Color resolveMutedSurface(ColorScheme scheme) =>
      mutedSurface ?? scheme.surfaceContainerHighest.withValues(alpha: 0.55);

  Color resolveToolTrigger(ColorScheme scheme) =>
      toolTriggerColor ?? scheme.onSurfaceVariant;

  Color resolveToolPanel(ColorScheme scheme) =>
      toolPanelColor ?? resolveMutedSurface(scheme);

  Color resolveReasoningBorder(ColorScheme scheme) =>
      reasoningBorderColor ?? scheme.outlineVariant.withValues(alpha: 0.7);

  @override
  AiMessageTheme copyWith({
    CompiledMarkdownStyle? markdown,
    Color? userBubbleColor,
    Color? userBubbleForeground,
    Color? mutedSurface,
    Color? toolTriggerColor,
    Color? toolPanelColor,
    Color? reasoningBorderColor,
    double? messageSpacing,
    double? partSpacing,
    double? userBubbleRadius,
    double? panelRadius,
    double? codeBlockRadius,
    double? threadMaxWidth,
    double? threadHorizontalPadding,
    bool? cotExpandReasoningOnOpen,
    bool? cotExpandToolsOnOpen,
  }) {
    return AiMessageTheme(
      markdown: markdown ?? this.markdown,
      userBubbleColor: userBubbleColor ?? this.userBubbleColor,
      userBubbleForeground: userBubbleForeground ?? this.userBubbleForeground,
      mutedSurface: mutedSurface ?? this.mutedSurface,
      toolTriggerColor: toolTriggerColor ?? this.toolTriggerColor,
      toolPanelColor: toolPanelColor ?? this.toolPanelColor,
      reasoningBorderColor: reasoningBorderColor ?? this.reasoningBorderColor,
      messageSpacing: messageSpacing ?? this.messageSpacing,
      partSpacing: partSpacing ?? this.partSpacing,
      userBubbleRadius: userBubbleRadius ?? this.userBubbleRadius,
      panelRadius: panelRadius ?? this.panelRadius,
      codeBlockRadius: codeBlockRadius ?? this.codeBlockRadius,
      threadMaxWidth: threadMaxWidth ?? this.threadMaxWidth,
      threadHorizontalPadding:
          threadHorizontalPadding ?? this.threadHorizontalPadding,
      cotExpandReasoningOnOpen:
          cotExpandReasoningOnOpen ?? this.cotExpandReasoningOnOpen,
      cotExpandToolsOnOpen: cotExpandToolsOnOpen ?? this.cotExpandToolsOnOpen,
    );
  }

  @override
  AiMessageTheme lerp(ThemeExtension<AiMessageTheme>? other, double t) {
    if (other is! AiMessageTheme) return this;
    return AiMessageTheme(
      markdown: t < 0.5 ? markdown : other.markdown,
      userBubbleColor: Color.lerp(userBubbleColor, other.userBubbleColor, t),
      userBubbleForeground:
          Color.lerp(userBubbleForeground, other.userBubbleForeground, t),
      mutedSurface: Color.lerp(mutedSurface, other.mutedSurface, t),
      toolTriggerColor: Color.lerp(toolTriggerColor, other.toolTriggerColor, t),
      toolPanelColor: Color.lerp(toolPanelColor, other.toolPanelColor, t),
      reasoningBorderColor:
          Color.lerp(reasoningBorderColor, other.reasoningBorderColor, t),
      messageSpacing:
          messageSpacing + (other.messageSpacing - messageSpacing) * t,
      partSpacing: partSpacing + (other.partSpacing - partSpacing) * t,
      userBubbleRadius:
          userBubbleRadius + (other.userBubbleRadius - userBubbleRadius) * t,
      panelRadius: panelRadius + (other.panelRadius - panelRadius) * t,
      codeBlockRadius:
          codeBlockRadius + (other.codeBlockRadius - codeBlockRadius) * t,
      threadMaxWidth:
          threadMaxWidth + (other.threadMaxWidth - threadMaxWidth) * t,
      threadHorizontalPadding: threadHorizontalPadding +
          (other.threadHorizontalPadding - threadHorizontalPadding) * t,
      cotExpandReasoningOnOpen: t < 0.5
          ? cotExpandReasoningOnOpen
          : other.cotExpandReasoningOnOpen,
      cotExpandToolsOnOpen:
          t < 0.5 ? cotExpandToolsOnOpen : other.cotExpandToolsOnOpen,
    );
  }
}
