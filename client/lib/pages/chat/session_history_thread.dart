import 'dart:async';

import 'package:ai_message_core/ai_message_core.dart';
import 'package:ai_message_ui/ai_message_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../l10n/l10n_extensions.dart';
import 'ai_thread_selection_context_menu.dart';

/// Finder key for the “new messages” jump chip.
const Key kSessionHistoryNewMessagesChipKey = ValueKey(
  'session-history-new-messages-chip',
);

/// Finder key for the live-refresh “Running…” footer.
const Key kSessionHistoryRunningFooterKey = ValueKey(
  'session-history-running-footer',
);

/// History message list for session review.
///
/// Owns scroll chrome (stick-to-end, load-older anchoring, ActionBar hover
/// gate, [SelectionArea], new-messages chip). Mounts the full pagination data
/// window (retain + chunked fill) so scrolling does not remount markdown —
/// Claude-like residency within the loaded message set. Older pages still
/// arrive via [onLoadOlder].
class SessionHistoryThread extends StatefulWidget {
  const SessionHistoryThread({
    required this.runtime,
    required this.hasOlder,
    required this.isLoadingOlder,
    this.onLoadOlder,
    this.liveRefreshActive = false,
    super.key,
  });

  final AiThreadRuntime runtime;
  final bool hasOlder;
  final bool isLoadingOlder;
  final VoidCallback? onLoadOlder;

  /// When true, shows a slim “Running…” footer under the scroll surface.
  final bool liveRefreshActive;

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
  /// Delay message mounts until after the first jump-to-end so open does not
  /// build the top of the thread under a scroll offset of 0.
  var _mountTurns = false;

  /// Tip grew while stick was paused — show jump chip until user resumes.
  var _showNewMessagesChip = false;

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
    _scheduleOpenAtEnd();
  }

  @override
  void didUpdateWidget(covariant SessionHistoryThread oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.runtime != widget.runtime) {
      _runtimeSub?.cancel();
      _setStickToEnd(true);
      _showNewMessagesChip = false;
      _paginationArmed = true;
      _mountTurns = false;
      _messages = widget.runtime.messages;
      _runtimeSub = widget.runtime.changes.listen((_) => _onRuntimeChanged());
      _scheduleOpenAtEnd();
    }
  }

  /// Rebuilds so [VirtualThreadViewport.suppressMeasureScrollCorrection]
  /// tracks stick state (must not stay true after stick release).
  void _setStickToEnd(bool value) {
    if (_stickToEnd == value) return;
    if (!mounted) return;
    setState(() {
      _stickToEnd = value;
      if (value) _showNewMessagesChip = false;
    });
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
    final tipGrew = _tipGrew(_messages, next, wasPrepend: wasPrepend);
    setState(() {
      _messages = next;
      if (!_stickToEnd && tipGrew) {
        _showNewMessagesChip = true;
      }
    });
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

  static bool _tipGrew(
    List<AiMessage> current,
    List<AiMessage> next, {
    required bool wasPrepend,
  }) {
    if (wasPrepend) return false;
    if (next.isEmpty) return false;
    if (current.isEmpty) return true;
    if (next.length > current.length) return true;
    return next.last.id != current.last.id;
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
      _setStickToEnd(false);
    }

    _lastPixels = pixels;
    _lastMaxExtent = max;
  }

  void _scheduleOpenAtEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_scrollController.hasClients) {
        final max = _scrollController.position.maxScrollExtent;
        if (max > 0) {
          _jumpTo(max);
        }
      }
      if (!_mountTurns) {
        setState(() => _mountTurns = true);
      }
      _scheduleStickFrames();
    });
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

  void _resumeStickToTip() {
    _setStickToEnd(true);
    _scheduleStickFrames();
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
      _setStickToEnd(false);
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
          _setStickToEnd(false);
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
    _setStickToEnd(false);

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

  Widget _buildNewMessagesChip(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    return Positioned(
      left: 0,
      right: 0,
      bottom: widget.liveRefreshActive ? 36 : 12,
      child: Center(
        child: SelectionContainer.disabled(
          child: Material(
            key: kSessionHistoryNewMessagesChipKey,
            color: scheme.surfaceContainerHigh,
            elevation: 2,
            shadowColor: Colors.black.withValues(alpha: 0.12),
            shape: const StadiumBorder(),
            child: InkWell(
              customBorder: const StadiumBorder(),
              onTap: _resumeStickToTip,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 18,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      l10n.sessionHistoryNewMessages,
                      style: TpTextStyles.of(
                        context,
                      ).smColored(scheme.onSurface),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRunningFooter(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SelectionContainer.disabled(
      child: Padding(
        key: kSessionHistoryRunningFooterKey,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
        child: Text(
          context.l10n.sessionHistoryRunning,
          textAlign: TextAlign.center,
          style: TpTextStyles.of(context).xsColored(scheme.onSurfaceVariant),
        ),
      ),
    );
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

    final thread = NotificationListener<ScrollNotification>(
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
            anchorEnd: true,
            overscan: 5,
            // Claude-like: keep the loaded pagination window mounted while
            // scrolling; fill in chunks after open so the first paint stays light.
            retainMountedTurns: true,
            fillDataWindow: true,
            mountTurns: _mountTurns,
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
                    child: AiHistoryRenderScope(
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
                ),
              );
            },
          ),
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Stack(
            children: [
              thread,
              if (_showNewMessagesChip && !_stickToEnd)
                _buildNewMessagesChip(context),
            ],
          ),
        ),
        if (widget.liveRefreshActive) _buildRunningFooter(context),
      ],
    );
  }
}
