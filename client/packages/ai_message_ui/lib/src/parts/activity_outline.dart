import 'package:flutter/material.dart';

import '../theme.dart';
import 'collapsible_body.dart';

const double kAiActivityOutlineMaxHeight = 384;
const double _aiActivityChevronSize = 24;
const double _aiActivityChevronGap = 8;
const double _aiActivityIndent = _aiActivityChevronSize + _aiActivityChevronGap;

class AiActivityOutline extends StatefulWidget {
  const AiActivityOutline({
    required this.header,
    required this.children,
    this.followLatest = false,
    super.key,
  });

  final Widget header;
  final List<Widget> children;
  final bool followLatest;

  @override
  State<AiActivityOutline> createState() => _AiActivityOutlineState();
}

class _AiActivityOutlineState extends State<AiActivityOutline> {
  static const double _bottomEpsilon = 4;

  final ScrollController _scroll = ScrollController();
  bool _stickToBottom = true;
  bool _scrollScheduled = false;
  bool _firstMetrics = true;
  double _lastPixels = 0;

  @override
  void initState() {
    super.initState();
    if (widget.followLatest) _scheduleScroll(toBottom: true);
  }

  @override
  void didUpdateWidget(covariant AiActivityOutline oldWidget) {
    super.didUpdateWidget(oldWidget);
    final opened = oldWidget.children.isEmpty && widget.children.isNotEmpty;
    if (!widget.followLatest) _stickToBottom = true;
    if (opened ||
        (!oldWidget.followLatest && widget.followLatest) ||
        widget.followLatest) {
      _scheduleScroll(toBottom: widget.followLatest);
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _scheduleScroll({required bool toBottom}) {
    if (_scrollScheduled) return;
    _scrollScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollScheduled = false;
      if (!mounted ||
          widget.children.isEmpty ||
          !_scroll.hasClients ||
          (toBottom && !_stickToBottom)) {
        return;
      }
      final position = _scroll.position;
      final target = toBottom ? position.maxScrollExtent : 0.0;
      if ((position.pixels - target).abs() > 0.5) {
        _scroll.jumpTo(target);
      }
      _lastPixels = position.pixels;
    });
  }

  bool _onMetricsChanged(ScrollMetricsNotification notification) {
    if (notification.depth != 0 || !widget.followLatest) return false;
    if (_firstMetrics) {
      _firstMetrics = false;
      return false;
    }
    if (_stickToBottom) _scheduleScroll(toBottom: true);
    return false;
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification.depth != 0) return false;
    final metrics = notification.metrics;
    final pixels = metrics.pixels;
    final atBottom = metrics.maxScrollExtent - pixels <= _bottomEpsilon;
    if (_stickToBottom) {
      if (pixels < _lastPixels - _bottomEpsilon && !atBottom) {
        _stickToBottom = false;
      }
    } else if (atBottom) {
      _stickToBottom = true;
    }
    _lastPixels = pixels;
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final aiTheme = AiMessageTheme.of(context);
    final railColor = aiTheme.resolveReasoningBorder(scheme);
    final scrollBehavior = ScrollConfiguration.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        widget.header,
        AiCollapsibleBody(
          open: widget.children.isNotEmpty,
          child: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxHeight: kAiActivityOutlineMaxHeight,
              ),
              child: Scrollbar(
                controller: _scroll,
                thumbVisibility: true,
                child: Padding(
                  padding: const EdgeInsets.only(right: 24),
                  child: ScrollConfiguration(
                    behavior: scrollBehavior.copyWith(scrollbars: false),
                    child: NotificationListener<ScrollMetricsNotification>(
                      onNotification: _onMetricsChanged,
                      child: NotificationListener<ScrollNotification>(
                        onNotification: _onScroll,
                        child: SingleChildScrollView(
                          controller: _scroll,
                          child: ScrollConfiguration(
                            behavior: scrollBehavior,
                            child: Stack(
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(
                                    left: _aiActivityIndent,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    mainAxisSize: MainAxisSize.min,
                                    children: widget.children,
                                  ),
                                ),
                                Positioned(
                                  left: (_aiActivityChevronSize - 1) / 2,
                                  top: 0,
                                  bottom: 0,
                                  child: Container(
                                    key: const ValueKey(
                                      'ai-activity-outline-indent-guide',
                                    ),
                                    width: 1,
                                    color: railColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
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
    );
  }
}

class AiActivityChevron extends StatelessWidget {
  const AiActivityChevron({required this.open, this.color, super.key});

  final bool open;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final resolvedColor =
        color ??
        (open
            ? scheme.primary
            : AiMessageTheme.of(context).resolveToolTrigger(scheme));
    return Container(
      key: const ValueKey('ai-activity-chevron'),
      width: _aiActivityChevronSize,
      height: _aiActivityChevronSize,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Icon(
        open ? Icons.expand_more : Icons.chevron_right,
        size: 14,
        color: resolvedColor,
      ),
    );
  }
}
