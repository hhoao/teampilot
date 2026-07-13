import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter/material.dart';

import 'ai_message_parts.dart';
import 'message_action_bar.dart';
import 'part_registry.dart';
import 'theme.dart';

/// Role layout aligned with assistant-ui UserMessage / AssistantMessage.
///
/// User: muted rounded bubble, end-aligned, action bar on hover.
/// Assistant: no bubble, prose + grouped parts, action bar under content.
/// System: centered muted pill.
class AiMessageView extends StatefulWidget {
  const AiMessageView({
    required this.message,
    this.registry = AiPartRegistry.defaults,
    this.showActionBar = true,
    super.key,
  });

  final AiMessage message;
  final AiPartRegistry registry;
  final bool showActionBar;

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
            hovered: _hovered,
          ),
          AiRole.assistant => _AssistantBlock(
            scheme: scheme,
            parts: parts,
            message: widget.message,
            showActionBar: widget.showActionBar,
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

class _UserBubble extends StatelessWidget {
  const _UserBubble({
    required this.scheme,
    required this.aiTheme,
    required this.parts,
    required this.message,
    required this.showActionBar,
    required this.hovered,
  });

  final ColorScheme scheme;
  final AiMessageTheme aiTheme;
  final Widget parts;
  final AiMessage message;
  final bool showActionBar;
  final bool hovered;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.85,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (showActionBar)
              Opacity(
                opacity: hovered ? 1 : 0,
                child: AiMessageActionBar(
                  message: message,
                  alwaysVisible: hovered,
                ),
              ),
            Flexible(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: aiTheme.resolveUserBubble(scheme),
                  borderRadius:
                      BorderRadius.circular(aiTheme.userBubbleRadius),
                ),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
      ),
    );
  }
}

class _AssistantBlock extends StatelessWidget {
  const _AssistantBlock({
    required this.scheme,
    required this.parts,
    required this.message,
    required this.showActionBar,
    required this.hovered,
  });

  final ColorScheme scheme;
  final Widget parts;
  final AiMessage message;
  final bool showActionBar;
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
                child: Opacity(
                  opacity: hovered ? 1 : 0,
                  child: AiMessageActionBar(
                    message: message,
                    alwaysVisible: hovered,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
