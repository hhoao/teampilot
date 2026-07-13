import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter/material.dart';

import 'ai_message_parts.dart';
import 'message_action_bar.dart';
import 'part_registry.dart';
import 'strings.dart';
import 'theme.dart';

/// Role layout aligned with assistant-ui UserMessage / AssistantMessage.
class AiMessageView extends StatefulWidget {
  const AiMessageView({
    required this.message,
    this.registry = AiPartRegistry.defaults,
    this.showActionBar = true,
    this.actionBarReveal = AiActionBarReveal.always,
    super.key,
  });

  final AiMessage message;
  final AiPartRegistry registry;
  final bool showActionBar;
  final AiActionBarReveal actionBarReveal;

  @override
  State<AiMessageView> createState() => _AiMessageViewState();
}

class _AiMessageViewState extends State<AiMessageView> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final aiTheme = AiMessageTheme.of(context);
    final scheme = Theme.of(context).colorScheme;
    final parts = AiMessageParts(
      parts: widget.message.parts,
      registry: widget.registry,
    );

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Padding(
        padding: EdgeInsets.only(bottom: aiTheme.messageSpacing),
        child: switch (widget.message.role) {
          AiRole.user => _UserBubble(
            scheme: scheme,
            aiTheme: aiTheme,
            parts: parts,
            message: widget.message,
            showActionBar: widget.showActionBar,
            actionBarReveal: widget.actionBarReveal,
            hovered: _hovered,
          ),
          AiRole.assistant => _AssistantBlock(
            scheme: scheme,
            aiTheme: aiTheme,
            parts: parts,
            message: widget.message,
            showActionBar: widget.showActionBar,
            actionBarReveal: widget.actionBarReveal,
            hovered: _hovered,
          ),
          AiRole.system => Align(
            alignment: Alignment.center,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: aiTheme.resolveMutedSurface(scheme),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: DefaultTextStyle.merge(
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                  child: parts,
                ),
              ),
            ),
          ),
        },
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.message});

  final AiMessage message;

  @override
  Widget build(BuildContext context) {
    if (message.status == AiMessageStatus.complete) {
      return const SizedBox.shrink();
    }
    final strings = AiMessageStrings.of(context);
    final scheme = Theme.of(context).colorScheme;
    final label = message.status == AiMessageStatus.cancelled
        ? strings.messageCancelled
        : strings.messageIncomplete;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.errorContainer.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: scheme.error.withValues(alpha: 0.35)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: scheme.onErrorContainer,
            ),
          ),
        ),
      ),
    );
  }
}

class _UserBubble extends StatelessWidget {
  const _UserBubble({
    required this.scheme,
    required this.aiTheme,
    required this.parts,
    required this.message,
    required this.showActionBar,
    required this.actionBarReveal,
    required this.hovered,
  });

  final ColorScheme scheme;
  final AiMessageTheme aiTheme;
  final Widget parts;
  final AiMessage message;
  final bool showActionBar;
  final AiActionBarReveal actionBarReveal;
  final bool hovered;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final bubbleMax = constraints.maxWidth.isFinite
              ? constraints.maxWidth * 0.85
              : 480.0;
          return ConstrainedBox(
            constraints: BoxConstraints(maxWidth: bubbleMax),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (showActionBar)
                  AiMessageActionBar(
                    message: message,
                    reveal: actionBarReveal,
                    forceVisible: hovered,
                  ),
                Flexible(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: aiTheme.resolveUserBubble(scheme),
                      borderRadius:
                          BorderRadius.circular(aiTheme.userBubbleRadius),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: DefaultTextStyle.merge(
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: aiTheme.resolveUserForeground(scheme),
                          height: 1.5,
                        ),
                        child: parts,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _AssistantBlock extends StatelessWidget {
  const _AssistantBlock({
    required this.scheme,
    required this.aiTheme,
    required this.parts,
    required this.message,
    required this.showActionBar,
    required this.actionBarReveal,
    required this.hovered,
  });

  final ColorScheme scheme;
  final AiMessageTheme aiTheme;
  final Widget parts;
  final AiMessage message;
  final bool showActionBar;
  final AiActionBarReveal actionBarReveal;
  final bool hovered;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _StatusBanner(message: message),
            DefaultTextStyle.merge(
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: scheme.onSurface,
                height: 1.625,
              ),
              child: parts,
            ),
            if (showActionBar)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: AiMessageActionBar(
                  message: message,
                  reveal: actionBarReveal,
                  forceVisible: hovered,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
