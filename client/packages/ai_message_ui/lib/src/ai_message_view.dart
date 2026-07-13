import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter/material.dart';

import 'ai_message_parts.dart';
import 'theme.dart';

/// Role-based message layout: user end/right, assistant start/left.
class AiMessageView extends StatelessWidget {
  const AiMessageView({
    required this.message,
    this.partBuilders,
    super.key,
  });

  final AiMessage message;
  final Map<Type, Widget Function(BuildContext context, AiMessagePart part)>?
      partBuilders;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final aiTheme = theme.extension<AiMessageTheme>();
    final spacing = aiTheme?.messageSpacing ?? 12.0;
    final scheme = theme.colorScheme;

    final parts = AiMessageParts(
      parts: message.parts,
      partBuilders: partBuilders,
    );

    return Padding(
      padding: EdgeInsets.only(bottom: spacing),
      child: switch (message.role) {
        AiRole.user => Align(
          alignment: Alignment.centerRight,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(context).width * 0.82,
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: aiTheme?.userBubbleColor ??
                    scheme.primaryContainer.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: parts,
              ),
            ),
          ),
        ),
        AiRole.assistant => Align(
          alignment: Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(context).width * 0.96,
            ),
            child: parts,
          ),
        ),
        AiRole.system => Align(
          alignment: Alignment.center,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: aiTheme?.assistantBubbleColor ??
                  scheme.surfaceContainerHighest.withValues(alpha: 0.65),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: parts,
            ),
          ),
        ),
      },
    );
  }
}
