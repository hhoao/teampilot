import 'dart:math' as math;

import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../markdown/compiled_markdown_chrome.dart';
import '../strings.dart';
import '../theme.dart';
import 'text_part_view.dart';

/// Collapsible reasoning — assistant-ui ReasoningRoot (outline + markdown).
class AiReasoningPartView extends StatefulWidget {
  const AiReasoningPartView({
    required this.part,
    this.initiallyExpanded = false,
    this.autoFollow = false,
    super.key,
  });

  final AiReasoningPart part;
  final bool initiallyExpanded;

  /// While true, the open body follows the streaming reasoning: the inner
  /// scroll view stays pinned to the newest line. When this flips back to
  /// false (the turn stopped streaming), the body collapses to its trigger
  /// row so the final answer is not buried under a full thinking block.
  final bool autoFollow;

  @override
  State<AiReasoningPartView> createState() => _AiReasoningPartViewState();
}

class _AiReasoningPartViewState extends State<AiReasoningPartView> {
  static const double _bottomEpsilon = 4;

  late bool _open = widget.initiallyExpanded;
  final ScrollController _scroll = ScrollController();

  /// False once the user scrolls the inner body away from the newest line;
  /// re-armed when they return to the bottom.
  bool _stickToBottom = true;

  /// Initial metrics belong to the first layout, not to streamed growth.
  bool _firstMetrics = true;

  bool _scrollScheduled = false;

  @override
  void didUpdateWidget(covariant AiReasoningPartView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.autoFollow && !widget.autoFollow) {
      // The turn finished streaming: fold the body back into its row.
      _open = false;
      _stickToBottom = true;
    } else if (!oldWidget.autoFollow && widget.autoFollow && _open) {
      _scheduleScrollToBottom();
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _open = !_open);
    if (_open) _scheduleScrollToBottom();
  }

  void _scheduleScrollToBottom() {
    if (_scrollScheduled) return;
    _scrollScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollScheduled = false;
      if (!mounted || !_open || !_stickToBottom || !_scroll.hasClients) {
        return;
      }
      final position = _scroll.position;
      if (position.maxScrollExtent - position.pixels > 0.5) {
        _scroll.jumpTo(position.maxScrollExtent);
      }
    });
  }

  bool _onMetricsChanged(ScrollMetricsNotification notification) {
    if (!widget.autoFollow || !_open) return false;
    if (_firstMetrics) {
      _firstMetrics = false;
      return false;
    }
    if (_stickToBottom) _scheduleScrollToBottom();
    return false;
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification.depth != 0) return false;
    if (notification is UserScrollNotification) {
      if (notification.direction == ScrollDirection.idle) return false;
      _stickToBottom = _isAtBottom(notification.metrics);
    } else if (notification is OverscrollNotification) {
      _stickToBottom = false;
    }
    return false;
  }

  static bool _isAtBottom(ScrollMetrics metrics) =>
      metrics.maxScrollExtent - metrics.pixels <= _bottomEpsilon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final aiTheme = AiMessageTheme.of(context);
    final strings = AiMessageStrings.of(context);
    final markdown = aiTheme.markdown;
    final triggerColor = aiTheme.resolveToolTrigger(scheme);

    return Padding(
      padding: EdgeInsets.only(bottom: aiTheme.partSpacing),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectionContainer.disabled(
            child: Semantics(
              button: true,
              expanded: _open,
              label: strings.reasoning,
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: _toggle,
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Icon(
                          Icons.psychology_outlined,
                          size: 16,
                          color: triggerColor,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            strings.reasoning,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: markdown.toolTrigger(triggerColor),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Transform.rotate(
                          angle: _open ? 0 : -math.pi / 2,
                          child: Icon(
                            Icons.expand_more,
                            size: 16,
                            color: triggerColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (_open)
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
              alignment: Alignment.topLeft,
              child: Padding(
                padding: const EdgeInsets.only(left: 24, top: 4, bottom: 8),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 256),
                  child: NotificationListener<ScrollNotification>(
                    onNotification: _onScroll,
                    child: NotificationListener<ScrollMetricsNotification>(
                      onNotification: _onMetricsChanged,
                      child: SingleChildScrollView(
                        controller: _scroll,
                        child: DefaultTextStyle.merge(
                          style: markdown.reasoningBody(
                            scheme.onSurfaceVariant,
                          ),
                          child: AiTextPartView(text: widget.part.text),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
