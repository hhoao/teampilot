import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter/material.dart';

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

  /// True while this reasoning block is the live thinking target. The open
  /// body follows the streaming reasoning: the inner scroll view stays pinned
  /// to the newest line. Flipping to false (another block took over, or the
  /// turn stopped streaming) collapses the body to its trigger row so finished
  /// thinking does not bury the answer. Flipping from false to true opens the
  /// body again and re-arms the follow.
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

  /// Offset observed on the previous scroll notification. Stick release is a
  /// *drop* relative to this, never a property of a single metric snapshot:
  /// the box's own follow jump and the layout corrections that re-create the
  /// scroll position also dispatch notifications, and reading them as a user
  /// gesture either cancels the follow or yanks a reader back.
  double _lastPixels = 0;

  /// Initial metrics belong to the first layout, not to streamed growth.
  bool _firstMetrics = true;

  bool _scrollScheduled = false;

  @override
  void initState() {
    super.initState();
    // Mounted already following (the live thinking block of a streaming
    // turn): the body must open on the newest line, not on the first one.
    // Without this pin the box stays at offset 0 for the whole turn because
    // nothing else schedules the initial jump.
    if (_open && widget.autoFollow) _scheduleScrollToBottom();
  }

  @override
  void didUpdateWidget(covariant AiReasoningPartView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.autoFollow && !widget.autoFollow) {
      // No longer the live thinking target: fold the body back into its row.
      _open = false;
      _stickToBottom = true;
    } else if (!oldWidget.autoFollow && widget.autoFollow) {
      // Became the live thinking target (the turn started while this block was
      // already mounted, or the chain resumed after a tool call): open it and
      // follow the newest line.
      _open = true;
      _stickToBottom = true;
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
      _lastPixels = _scroll.position.pixels;
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
    final metrics = notification.metrics;
    final pixels = metrics.pixels;

    // Release only on an upward move that ends off the tip. Reading a single
    // notification cannot tell a user drag from the follow's own jump or a
    // layout correction (the scroll position is re-created whenever the chat
    // theme changes during a live turn, which dispatches ScrollStart /
    // Overscroll / ScrollEnd while the user does nothing). Comparing against
    // the previous offset — and sparing a drop that lands exactly on the tip,
    // a clamp after the content shrank — keeps the follow armed.
    if (_stickToBottom) {
      if (pixels < _lastPixels - _bottomEpsilon && !_isAtBottom(metrics)) {
        _stickToBottom = false;
      }
    } else if (_isAtBottom(metrics)) {
      // The reader came back to the newest line — resume following, like the
      // transcript's jump-to-bottom control.
      _stickToBottom = true;
    }
    _lastPixels = pixels;
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
    final label = strings.reasoningLabel(running: widget.autoFollow);

    return Padding(
      padding: EdgeInsets.only(bottom: aiTheme.partSpacing),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectionContainer.disabled(
            child: Semantics(
              button: true,
              expanded: _open,
              label: label,
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: _toggle,
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        _AiReasoningStatusIcon(live: widget.autoFollow),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: markdown.toolTrigger(triggerColor),
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
                      child: Scrollbar(
                        controller: _scroll,
                        thumbVisibility: true,
                        child: ScrollConfiguration(
                          behavior: ScrollConfiguration.of(context)
                              .copyWith(scrollbars: false),
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
              ),
            ),
        ],
      ),
    );
  }
}

class _AiReasoningStatusIcon extends StatelessWidget {
  const _AiReasoningStatusIcon({required this.live});

  final bool live;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final statusColor = live
        ? scheme.primary
        : AiMessageTheme.of(context).resolveToolSuccess(scheme);
    return SizedBox(
      key: const ValueKey('ai-reasoning-status-icon'),
      width: 16,
      height: 16,
      child: live
          ? CircularProgressIndicator(strokeWidth: 2, color: statusColor)
          : Icon(Icons.check_circle_outline, size: 16, color: statusColor),
    );
  }
}
