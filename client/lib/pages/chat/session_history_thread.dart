import 'dart:async';

import 'package:ai_message_core/ai_message_core.dart';
import 'package:ai_message_ui/ai_message_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'ai_thread_selection_context_menu.dart';

/// History message list for session review.
///
/// Owns scroll chrome (stick-to-end, load-older anchoring, ActionBar hover
/// gate, [SelectionArea]) and embeds [VirtualThreadViewport] so only nearby
/// turns (+ overscan) mount. Unmounted turns are spacer extent from a height
/// cache — avoids mid-scroll jumps from naive lazy lists while capping mount
/// cost vs a full [Column] of every message.
class SessionHistoryThread extends StatefulWidget {
  const SessionHistoryThread({
    required this.runtime,
    required this.hasOlder,
    required this.isLoadingOlder,
    this.onLoadOlder,
    super.key,
  });

  final AiThreadRuntime runtime;
  final bool hasOlder;
  final bool isLoadingOlder;
  final VoidCallback? onLoadOlder;

  @override
  State<SessionHistoryThread> createState() => _SessionHistoryThreadState();
}

class _SessionHistoryThreadState extends State<SessionHistoryThread> {
  static const _hoverResumeIdle = Duration(milliseconds: 160);
  static const _bottomEpsilon = 1.0;
  static const _loadOlderPixelThreshold = 120.0;

  late final ScrollController _scrollController;
  StreamSubscription<void>? _runtimeSub;

  /// While false, hover ActionBars ignore pointer-enter (scroll-under-cursor).
  final ValueNotifier<bool> _actionBarHoverEnabled = ValueNotifier(true);
  Timer? _hoverResumeTimer;

  var _stickToEnd = true;
  var _stickGeneration = 0;

  double _lastPixels = 0;
  double _lastMaxExtent = 0;

  var _loadOlderInFlight = false;
  var _paginationArmed = true;

  List<AiMessage> _messages = const [];

  @override
  void initState() {
    super.initState();
    _messages = widget.runtime.messages;
    _scrollController = ScrollController()..addListener(_onScrollTick);
    _runtimeSub = widget.runtime.changes.listen((_) => _onRuntimeChanged());
    _scheduleStickFrames();
  }

  @override
  void didUpdateWidget(covariant SessionHistoryThread oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.runtime != widget.runtime) {
      _runtimeSub?.cancel();
      _stickToEnd = true;
      _paginationArmed = true;
      _messages = widget.runtime.messages;
      _runtimeSub = widget.runtime.changes.listen((_) => _onRuntimeChanged());
      _scheduleStickFrames();
    }
  }

  @override
  void dispose() {
    _stickGeneration++;
    _hoverResumeTimer?.cancel();
    _actionBarHoverEnabled.dispose();
    _runtimeSub?.cancel();
    _scrollController
      ..removeListener(_onScrollTick)
      ..dispose();
    super.dispose();
  }

  void _onRuntimeChanged() {
    if (!mounted) return;
    final next = widget.runtime.messages;
    final wasPrepend = _isPrepend(_messages, next);
    setState(() => _messages = next);
    if (_stickToEnd && !wasPrepend) {
      _scheduleStickFrames();
    }
  }

  static bool _isPrepend(List<AiMessage> current, List<AiMessage> next) {
    if (current.isEmpty || next.length < current.length) return false;
    final offset = next.length - current.length;
    for (var i = 0; i < current.length; i++) {
      if (current[i].id != next[i + offset].id) return false;
    }
    return offset > 0;
  }

  void _jumpTo(double offset) {
    if (!_scrollController.hasClients) return;
    final before = _scrollController.position.pixels;
    if ((offset - before).abs() < 0.5) return;
    _scrollController.jumpTo(offset);
    if (_scrollController.hasClients) {
      _lastPixels = _scrollController.position.pixels;
      _lastMaxExtent = _scrollController.position.maxScrollExtent;
    }
  }

  void _onScrollTick() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    final pixels = position.pixels;
    final max = position.maxScrollExtent;

    if (_stickToEnd &&
        pixels < _lastPixels - _bottomEpsilon &&
        (max - _lastMaxExtent).abs() <= _bottomEpsilon) {
      _stickToEnd = false;
    }

    _lastPixels = pixels;
    _lastMaxExtent = max;
  }

  void _scheduleStickFrames({int framesLeft = 12}) {
    final generation = ++_stickGeneration;
    void tick(int left) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || generation != _stickGeneration || !_stickToEnd) return;
        if (_scrollController.hasClients) {
          final max = _scrollController.position.maxScrollExtent;
          final pixels = _scrollController.position.pixels;
          if (max > 0 && max - pixels > _bottomEpsilon) {
            _jumpTo(max);
          }
        }
        if (left > 1 && _stickToEnd) {
          tick(left - 1);
        }
      });
    }

    tick(framesLeft);
  }

  void _setHoverEnabled(bool enabled) {
    if (_actionBarHoverEnabled.value == enabled) return;
    _actionBarHoverEnabled.value = enabled;
  }

  void _suppressHoverForScroll() {
    _hoverResumeTimer?.cancel();
    _setHoverEnabled(false);
  }

  void _scheduleHoverResume() {
    _hoverResumeTimer?.cancel();
    _hoverResumeTimer = Timer(_hoverResumeIdle, () {
      if (!mounted) return;
      _setHoverEnabled(true);
    });
  }

  void _maybeLoadOlder(ScrollMetrics metrics) {
    if (metrics.pixels > _loadOlderPixelThreshold) {
      _paginationArmed = true;
      return;
    }
    if (!_paginationArmed) return;
    if (!widget.hasOlder || widget.isLoadingOlder || _loadOlderInFlight) {
      return;
    }
    if (widget.onLoadOlder == null) return;
    _paginationArmed = false;
    unawaited(_loadOlderAnchored());
  }

  bool _onScrollNotification(ScrollNotification notification) {
    if (notification is UserScrollNotification &&
        notification.direction != ScrollDirection.idle) {
      _stickToEnd = false;
    }

    if (notification is ScrollEndNotification) {
      _scheduleHoverResume();
      _maybeLoadOlder(notification.metrics);
      return false;
    }
    if (notification is ScrollStartNotification) {
      _suppressHoverForScroll();
      return false;
    }
    if (notification is ScrollUpdateNotification) {
      final delta = notification.scrollDelta;
      if (delta != null && delta != 0) {
        _suppressHoverForScroll();
        if (delta < 0) {
          _stickToEnd = false;
        }
      }
      _maybeLoadOlder(notification.metrics);
    }
    return false;
  }

  Future<void> _loadOlderAnchored() async {
    if (_loadOlderInFlight) return;
    if (!widget.hasOlder || widget.onLoadOlder == null) return;
    _loadOlderInFlight = true;
    _stickToEnd = false;

    try {
      double? pixelsBefore;
      double? maxBefore;
      if (_scrollController.hasClients) {
        pixelsBefore = _scrollController.position.pixels;
        maxBefore = _scrollController.position.maxScrollExtent;
      }

      widget.onLoadOlder!.call();
      // Runtime updates sync; wait a frame for setState + layout.
      await Future<void>.delayed(Duration.zero);
      await WidgetsBinding.instance.endOfFrame;

      if (!mounted || !_scrollController.hasClients) return;
      if (pixelsBefore == null || maxBefore == null) return;

      final maxAfter = _scrollController.position.maxScrollExtent;
      final delta = maxAfter - maxBefore;
      if (delta > 0.5) {
        _jumpTo(pixelsBefore + delta);
      }
      if (!_scrollController.hasClients) return;
      _lastPixels = _scrollController.position.pixels;
      _lastMaxExtent = _scrollController.position.maxScrollExtent;
    } finally {
      _loadOlderInFlight = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final lastId = _messages.isEmpty ? null : _messages.last.id;
    final aiTheme = AiMessageTheme.of(context);

    final Widget? header = widget.hasOlder
        ? SelectionContainer.disabled(
            child: SizedBox(
              height: 24,
              child: widget.isLoadingOlder
                  ? const Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : null,
            ),
          )
        : null;

    return NotificationListener<ScrollNotification>(
      onNotification: _onScrollNotification,
      child: SelectionArea(
        contextMenuBuilder: buildAiThreadSelectionContextMenu,
        child: SingleChildScrollView(
          controller: _scrollController,
          padding: const EdgeInsets.fromLTRB(0, 16, 0, 24),
          child: VirtualThreadViewport(
            messages: _messages,
            scrollController: _scrollController,
            header: header,
            suppressMeasureScrollCorrection: _stickToEnd,
            onMeasureScrollCorrection: (delta) {
              if (!_scrollController.hasClients || delta.abs() < 0.5) return;
              final next = (_scrollController.position.pixels + delta).clamp(
                0.0,
                _scrollController.position.maxScrollExtent,
              );
              _jumpTo(next);
            },
            messageBuilder: (context, ai) {
              return Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: aiTheme.threadHorizontalPadding,
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: aiTheme.threadMaxWidth,
                    ),
                    child: AiMessageView(
                      key: ValueKey(ai.id),
                      message: ai,
                      actionBarHoverEnabled: _actionBarHoverEnabled,
                      actionBarReveal: ai.id == lastId
                          ? AiActionBarReveal.always
                          : AiActionBarReveal.hover,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
