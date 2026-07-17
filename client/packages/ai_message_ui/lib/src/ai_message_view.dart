import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter/foundation.dart';
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
    this.actionBarHoverEnabled,
    super.key,
  });

  final AiMessage message;
  final AiPartRegistry registry;
  final bool showActionBar;
  final AiActionBarReveal actionBarReveal;

  /// When `false`, ignore pointer-enter for hover ActionBars (history fling).
  /// Defaults to always enabled when null.
  final ValueListenable<bool>? actionBarHoverEnabled;

  @override
  State<AiMessageView> createState() => _AiMessageViewState();
}

class _AiMessageViewState extends State<AiMessageView> {
  /// Hover is isolated from message body rebuilds (markdown / tools).
  final ValueNotifier<bool> _hovered = ValueNotifier(false);

  @override
  void initState() {
    super.initState();
    widget.actionBarHoverEnabled?.addListener(_onHoverEnabledChanged);
  }

  @override
  void didUpdateWidget(covariant AiMessageView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.actionBarHoverEnabled != widget.actionBarHoverEnabled) {
      oldWidget.actionBarHoverEnabled?.removeListener(_onHoverEnabledChanged);
      widget.actionBarHoverEnabled?.addListener(_onHoverEnabledChanged);
    }
  }

  @override
  void dispose() {
    widget.actionBarHoverEnabled?.removeListener(_onHoverEnabledChanged);
    _hovered.dispose();
    super.dispose();
  }

  bool get _hoverAllowed => widget.actionBarHoverEnabled?.value ?? true;

  void _onHoverEnabledChanged() {
    if (!_hoverAllowed && _hovered.value) {
      _hovered.value = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final aiTheme = AiMessageTheme.of(context);
    final scheme = Theme.of(context).colorScheme;
    final parts = AiMessageParts(
      parts: widget.message.parts,
      registry: widget.registry,
    );
    final trackHover = widget.showActionBar &&
        widget.actionBarReveal == AiActionBarReveal.hover;

    final body = Padding(
      padding: EdgeInsets.only(bottom: aiTheme.messageSpacing),
      child: RepaintBoundary(
        child: switch (widget.message.role) {
          AiRole.user => _UserBubble(
            scheme: scheme,
            aiTheme: aiTheme,
            parts: parts,
            message: widget.message,
            showActionBar: widget.showActionBar,
            actionBarReveal: widget.actionBarReveal,
            hoverListenable: trackHover ? _hovered : null,
          ),
          AiRole.assistant => _AssistantBlock(
            scheme: scheme,
            aiTheme: aiTheme,
            parts: parts,
            message: widget.message,
            showActionBar: widget.showActionBar,
            actionBarReveal: widget.actionBarReveal,
            hoverListenable: trackHover ? _hovered : null,
          ),
          AiRole.system => Align(
            alignment: Alignment.center,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: aiTheme.resolveMutedSurface(scheme),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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

    if (!trackHover) return body;

    // Keep MouseRegion mounted always — swapping it via ListenableBuilder when
    // the scroll gate flips remounts hit-targets under the cursor and jitters
    // scroll metrics. Gate only ignores enter; exit/clear still via listener.
    return MouseRegion(
      onEnter: (_) {
        if (!_hoverAllowed) return;
        _hovered.value = true;
      },
      onExit: (_) => _hovered.value = false,
      child: body,
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
    this.hoverListenable,
  });

  final ColorScheme scheme;
  final AiMessageTheme aiTheme;
  final Widget parts;
  final AiMessage message;
  final bool showActionBar;
  final AiActionBarReveal actionBarReveal;
  final ValueListenable<bool>? hoverListenable;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Reserve action-bar chrome so Row never overflows the thread width.
          const actionBarReserve = 80.0;
          final threadMax = constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : 480.0;
          final bubbleMax = (threadMax * 0.85).clamp(
            0.0,
            showActionBar ? threadMax - actionBarReserve : threadMax,
          );
          return Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (showActionBar)
                _HoverScopedActionBar(
                  message: message,
                  reveal: actionBarReveal,
                  hoverListenable: hoverListenable,
                ),
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: bubbleMax),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: aiTheme.resolveUserBubble(scheme),
                    borderRadius:
                        BorderRadius.circular(aiTheme.userBubbleRadius),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
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
    this.hoverListenable,
  });

  final ColorScheme scheme;
  final AiMessageTheme aiTheme;
  final Widget parts;
  final AiMessage message;
  final bool showActionBar;
  final AiActionBarReveal actionBarReveal;
  final ValueListenable<bool>? hoverListenable;

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
                child: _HoverScopedActionBar(
                  message: message,
                  reveal: actionBarReveal,
                  hoverListenable: hoverListenable,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Passes hover visibility into the action bar without rebuilding message body.
class _HoverScopedActionBar extends StatelessWidget {
  const _HoverScopedActionBar({
    required this.message,
    required this.reveal,
    this.hoverListenable,
  });

  final AiMessage message;
  final AiActionBarReveal reveal;
  final ValueListenable<bool>? hoverListenable;

  @override
  Widget build(BuildContext context) {
    return AiMessageActionBar(
      message: message,
      reveal: reveal,
      forceVisibleListenable: hoverListenable,
    );
  }
}
