import 'dart:async';

import 'package:ai_message_core/ai_message_core.dart';
import 'package:ai_message_ui/ai_message_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../l10n/l10n_extensions.dart';
import '../../models/failed_message_record.dart';
import 'chat_outline.dart';
import 'chat_reveal_controller.dart';
import 'history_scroll_cursor_lock.dart';
import 'session_history_live_chrome.dart';

/// Finder key for the “new messages” jump chip.
const Key kSessionHistoryNewMessagesChipKey = ValueKey(
  'session-history-new-messages-chip',
);

/// Finder key for the in-thread starting/running assistant placeholder.
const Key kSessionHistoryRunningFooterKey = ValueKey(
  'session-history-running-footer',
);

/// Synthetic tip message while continue is awaiting the assistant turn.
const AiMessage kSessionHistoryRunningPlaceholder = AiMessage(
  id: 'pending:running',
  role: AiRole.assistant,
  status: AiMessageStatus.incomplete,
  parts: [],
);

/// History message list for session review.
///
/// Owns scroll chrome (stick-to-end, load-older anchoring, hover-effects
/// gate + cursor lock, [SelectionArea] as scroll ancestor for edge
/// auto-scroll while selecting, new-messages chip). Mounts the full pagination data window (retain + chunked fill) so
/// scrolling does not remount markdown — Claude-like residency within the
/// loaded message set. Older pages still arrive via [onLoadOlder].
class SessionHistoryThread extends StatefulWidget {
  const SessionHistoryThread({
    required this.runtime,
    required this.hasOlder,
    required this.isLoadingOlder,
    this.onLoadOlder,
    this.liveChrome = SessionHistoryLiveChrome.none,
    this.pendingDeliveryStatuses = const {},
    this.onRetryFailedMessage,
    this.highlightMessageId,
    this.revealRequest,
    this.visibleOwnerId,
    super.key,
  });

  final AiThreadRuntime runtime;
  final bool hasOlder;
  final bool isLoadingOlder;
  final Future<void> Function()? onLoadOlder;

  /// Slim starting/running footer under the scroll surface.
  final SessionHistoryLiveChrome liveChrome;
  final Map<String, FailedMessageStatus> pendingDeliveryStatuses;
  final ValueChanged<String>? onRetryFailedMessage;

  /// Message id whose bubble gets a highlight ring (chat find current match).
  final String? highlightMessageId;

  /// Carries the reveal intent (jump + highlight) from the chat find host.
  final ChatRevealController? revealRequest;

  /// Owning user-turn id of the first viewport-visible turn. Host-owned;
  /// updated from [VirtualThreadViewport.onVisibleRange] without [setState].
  final ValueNotifier<String?>? visibleOwnerId;

  @override
  State<SessionHistoryThread> createState() => _SessionHistoryThreadState();
}

class _SessionHistoryThreadState extends State<SessionHistoryThread> {
  static const _hoverResumeIdle = Duration(milliseconds: 160);
  static const _bottomEpsilon = 1.0;
  static const _loadOlderPixelThreshold = 120.0;

  late final ScrollController _scrollController;
  StreamSubscription<void>? _runtimeSub;

  /// While false, ignore ActionBar hover-enter and force basic cursor
  /// (scroll-under-pointer).
  final ValueNotifier<bool> _hoverEffectsEnabled = ValueNotifier(true);
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

  /// While awaiting/applying an older-page prepend, skip viewport-internal
  /// measure correction so the thread applies extent correction once.
  var _anchoringOlder = false;
  int? _olderCaptureCount;
  double? _olderPixelsBefore;
  double? _olderMaxBefore;

  List<AiMessage> _messages = const [];

  /// Message to reveal in the viewport (from [ChatRevealController]).
  String? _revealTargetId;
  int _revealEpoch = 0;
  var _revealAnimate = false;
  var _revealAnimating = false;
  ChatRevealController? _boundReveal;

  void _onRevealRequestChanged() {
    if (!mounted) return;
    final request = widget.revealRequest;
    if (request != null) {
      _revealTargetId = request.targetMessageId;
      _revealEpoch = request.epoch;
      _revealAnimate = request.animate;
    }
    // Only unpin stick-to-end for a real targeted reveal; a bare open/close of
    // the find bar (clear()) must not unpin a live chat at the bottom.
    if (request?.targetMessageId != null) {
      _setStickToEnd(false);
    }
    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _messages = widget.runtime.messages;
    _scrollController = ScrollController()..addListener(_onScrollTick);
    _runtimeSub = widget.runtime.changes.listen((_) => _onRuntimeChanged());
    _boundReveal = widget.revealRequest;
    _boundReveal?.addListener(_onRevealRequestChanged);
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
    } else if (oldWidget.liveChrome != widget.liveChrome) {
      if (widget.liveChrome.isActive && _stickToEnd) {
        _scheduleStickFrames();
      }
    }
    if (oldWidget.revealRequest != widget.revealRequest) {
      _boundReveal?.removeListener(_onRevealRequestChanged);
      _boundReveal = widget.revealRequest;
      _boundReveal?.addListener(_onRevealRequestChanged);
      _onRevealRequestChanged();
    }
  }

  /// Rebuilds so [VirtualThreadViewport.suppressMeasureScrollCorrection]
  /// tracks stick state (must not stay true after stick release).
  void _setStickToEnd(bool value) {
    if (_stickToEnd == value) return;
    if (!mounted) return;
    // Scroll notifications (incl. jumpTo) can arrive during layout/paint.
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase != SchedulerPhase.idle &&
        phase != SchedulerPhase.postFrameCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _setStickToEnd(value);
      });
      return;
    }
    setState(() {
      _stickToEnd = value;
      if (value) _showNewMessagesChip = false;
    });
  }

  @override
  void dispose() {
    _stickGeneration++;
    _hoverResumeTimer?.cancel();
    _hoverEffectsEnabled.dispose();
    _runtimeSub?.cancel();
    _boundReveal?.removeListener(_onRevealRequestChanged);
    _scrollController
      ..removeListener(_onScrollTick)
      ..dispose();
    super.dispose();
  }

  void _onRuntimeChanged() {
    if (!mounted) return;
    // Seat runtime is seat-scoped; sync notify may still fire during sibling
    // deferred mount (TpDeferredForegroundMount). A reload started during
    // another tab's build must not markNeedsBuild this retained thread.
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase != SchedulerPhase.idle &&
        phase != SchedulerPhase.postFrameCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _onRuntimeChanged();
      });
      return;
    }
    final next = widget.runtime.messages;
    final wasPrepend = _isPrepend(_messages, next);
    final tipGrew = _tipGrew(_messages, next, wasPrepend: wasPrepend);
    // Sending a message appends a fresh user turn at the tip. Re-stick even if
    // the user had scrolled up reading history — the sent bubble (and the
    // response) must be visible, exactly like tapping the new-messages chip.
    if (_newUserTip(_messages, next)) {
      _setStickToEnd(true);
    }
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

  /// True when the tip of [next] is a user turn that was not the tip of
  /// [current] — i.e. the user just sent a new message.
  static bool _newUserTip(List<AiMessage> current, List<AiMessage> next) {
    if (next.isEmpty) return false;
    final tip = next.last;
    if (tip.role != AiRole.user) return false;
    if (current.isEmpty) return true;
    return current.last.id != tip.id;
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

  void _scrollToReveal(double offset) {
    if (!_scrollController.hasClients) return;
    final max = _scrollController.position.maxScrollExtent;
    final target = offset > max ? max : offset;
    if (_revealAnimate) {
      _animateTo(target);
    } else {
      _jumpTo(target);
    }
  }

  void _animateTo(double offset) {
    if (!_scrollController.hasClients) return;
    final before = _scrollController.position.pixels;
    if ((offset - before).abs() < 0.5) return;
    _revealAnimating = true;
    final distance = (offset - before).abs();
    final ms = (240 + distance * 0.12).clamp(240, 480).round();
    unawaited(
      _scrollController
          .animateTo(
            offset,
            duration: Duration(milliseconds: ms),
            curve: Curves.easeInOutCubic,
          )
          .whenComplete(() {
            _revealAnimating = false;
            if (!_scrollController.hasClients) return;
            _lastPixels = _scrollController.position.pixels;
            _lastMaxExtent = _scrollController.position.maxScrollExtent;
          }),
    );
  }

  void _publishVisibleOwner(TurnVisibleRange range) {
    final notifier = widget.visibleOwnerId;
    if (notifier == null) return;
    final next = range.lastIndex < range.firstIndex
        ? null
        : owningUserTurnId(_displayMessages, range.firstIndex);
    if (notifier.value == next) return;
    void apply() {
      if (!mounted) return;
      if (widget.visibleOwnerId != notifier) return;
      if (notifier.value == next) return;
      notifier.value = next;
    }

    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.idle ||
        phase == SchedulerPhase.postFrameCallbacks) {
      apply();
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => apply());
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
    } else if (!_stickToEnd && max - pixels <= _bottomEpsilon) {
      // Manual scroll back to tip — same as tapping the new-messages chip.
      _resumeStickToTip();
    }

    _lastPixels = pixels;
    _lastMaxExtent = max;
    _captureOlderExtentIfWaiting();
  }

  void _captureOlderExtentIfWaiting() {
    if (!_loadOlderInFlight) return;
    if (_olderCaptureCount == null) return;
    if (widget.runtime.messages.length != _olderCaptureCount) return;
    if (!_scrollController.hasClients) return;
    _olderPixelsBefore = _scrollController.position.pixels;
    _olderMaxBefore = _scrollController.position.maxScrollExtent;
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
    if (_hoverEffectsEnabled.value == enabled) return;
    // jumpTo / measure correction dispatch ScrollStart during layout; a sync
    // ValueNotifier write would ValueListenableBuilder→setState mid-frame
    // ("Build scheduled during frame").
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase != SchedulerPhase.idle &&
        phase != SchedulerPhase.postFrameCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _setHoverEnabled(enabled);
      });
      return;
    }
    _hoverEffectsEnabled.value = enabled;
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
    _olderCaptureCount = widget.runtime.messages.length;
    if (mounted) {
      setState(() => _anchoringOlder = true);
    }
    _captureOlderExtentIfWaiting();

    try {
      try {
        await widget.onLoadOlder!.call();
      } catch (_) {
        // Seat records a soft error; keep the current transcript mounted.
      }
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || !_scrollController.hasClients) return;
      final capturedPixels = _olderPixelsBefore;
      final capturedMax = _olderMaxBefore;
      if (capturedPixels == null || capturedMax == null) return;

      final maxAfter = _scrollController.position.maxScrollExtent;
      final delta = maxAfter - capturedMax;
      if (delta > 0.5) {
        _jumpTo(capturedPixels + delta);
      }
      if (!_scrollController.hasClients) return;
      _lastPixels = _scrollController.position.pixels;
      _lastMaxExtent = _scrollController.position.maxScrollExtent;
    } finally {
      _loadOlderInFlight = false;
      _olderCaptureCount = null;
      _olderPixelsBefore = null;
      _olderMaxBefore = null;
      if (mounted) {
        setState(() => _anchoringOlder = false);
      } else {
        _anchoringOlder = false;
      }
    }
  }

  Widget _buildNewMessagesChip(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    return Positioned(
      left: 0,
      right: 0,
      // Footer sits below this Stack (Column sibling), not overlaid — no offset.
      bottom: 12,
      child: Center(
        child: SelectionContainer.disabled(
          child: Material(
            key: kSessionHistoryNewMessagesChipKey,
            color: scheme.surfaceContainerHigh,
            elevation: 2,
            shadowColor: Colors.black.withValues(alpha: 0.12),
            shape: const StadiumBorder(),
            child: TpHover(
              shape: TpPressableShape.stadium,
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

  Widget _buildRunningInMessage(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = switch (widget.liveChrome) {
      SessionHistoryLiveChrome.starting => context.l10n.sessionHistoryStarting,
      SessionHistoryLiveChrome.running ||
      SessionHistoryLiveChrome.none => context.l10n.sessionHistoryRunning,
    };
    // Column width is applied around [VirtualThreadViewport]; keep left-aligned
    // like assistant text. Tip message already uses tightened messageSpacing.
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        key: kSessionHistoryRunningFooterKey,
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              label,
              style: TpTextStyles.of(
                context,
              ).smColored(scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  List<AiMessage> get _displayMessages {
    if (!widget.liveChrome.isActive) return _messages;
    if (_messages.any((m) => m.id == kSessionHistoryRunningPlaceholder.id)) {
      return _messages;
    }
    return [..._messages, kSessionHistoryRunningPlaceholder];
  }

  @override
  Widget build(BuildContext context) {
    final displayMessages = _displayMessages;
    final lastId = displayMessages.isEmpty ? null : displayMessages.last.id;
    // Last *real* message (excludes the running footer appended to the tip).
    final realTipId = _messages.isEmpty ? null : _messages.last.id;
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

    final thread = AiHistoryRenderScope(
      // History-review policy (Claude Code webview-aligned): oversized
      // markdown collapses to a budgeted preview with "Show more / Show less"
      // (see AiTextPartView). Without this scope, a giant single message (e.g.
      // a bundled-skill user turn) renders in full and freezes open for seconds.
      child: NotificationListener<ScrollNotification>(
        onNotification: _onScrollNotification,
        child: ValueListenableBuilder<bool>(
          valueListenable: _hoverEffectsEnabled,
          builder: (context, hoverEnabled, child) {
            return HistoryScrollCursorLock(
              active: !hoverEnabled,
              child: child!,
            );
          },
          // SelectionArea must be an *ancestor* of the scrollable so the
          // framework's edge auto-scroll while drag-selecting engages
          // (Scrollable's _ScrollableSelectionContainerDelegate). The old
          // "scroll crazy" bug that prompted sitting inside the scroll content
          // (flutter/flutter#110917) is fixed since 2022 (PR #112816).
          child: SelectionArea(
            contextMenuBuilder: buildTpSelectionAreaContextMenu,
            child: SingleChildScrollView(
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(0, 16, 0, 24),
              // Width chrome outside [VirtualThreadViewport]: turn bodies are
              // cached and would keep a stale per-message ConstrainedBox.
              child: Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: aiTheme.threadHorizontalPadding,
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: aiTheme.threadMaxWidth,
                    ),
                    child: AiLineSpacedSelectionStyle(
                      child: VirtualThreadViewport(
                        messages: displayMessages,
                        scrollController: _scrollController,
                        header: header,
                        anchorEnd: true,
                        overscan: 5,
                        // Claude-like: keep the loaded pagination window mounted while
                        // scrolling; fill in chunks after open so the first paint stays light.
                        retainMountedTurns: true,
                        fillDataWindow: true,
                        mountTurns: _mountTurns,
                        // Rebuild turn bodies when the highlight target changes
                        // so the ring moves even though the message list
                        // instance is unchanged (see VirtualThreadViewport.buildKey).
                        buildKey: widget.highlightMessageId,
                        revealMessageId: _revealTargetId,
                        revealEpoch: _revealEpoch,
                        onRevealOffset: (offset) {
                          if (!_scrollController.hasClients || offset < 0) {
                            return;
                          }
                          // 16 = SingleChildScrollView top padding; the
                          // delivered offset is viewport-space document pixels.
                          _scrollToReveal(offset + 16);
                        },
                        onVisibleRange: _publishVisibleOwner,
                        suppressMeasureScrollCorrection:
                            _stickToEnd || _anchoringOlder,
                        onMeasureScrollCorrection: (delta) {
                          if (_revealAnimating) return;
                          if (!_scrollController.hasClients ||
                              delta.abs() < 0.5) {
                            return;
                          }
                          final next =
                              (_scrollController.position.pixels + delta).clamp(
                                0.0,
                                _scrollController.position.maxScrollExtent,
                              );
                          _jumpTo(next);
                        },
                        messageBuilder: (context, ai) {
                          if (ai.id == kSessionHistoryRunningPlaceholder.id) {
                            return SelectionContainer.disabled(
                              child: _buildRunningInMessage(context),
                            );
                          }
                          // While Running is appended as the tip turn, keep the real tip's
                          // bottom gap tight so Running sits under it like in-turn chrome.
                          final tightenForRunning =
                              widget.liveChrome.isActive &&
                              displayMessages.length >= 2 &&
                              displayMessages.last.id ==
                                  kSessionHistoryRunningPlaceholder.id &&
                              ai.id ==
                                  displayMessages[displayMessages.length - 2]
                                      .id;
                          final deliveryStatus =
                              widget.pendingDeliveryStatuses[ai.id];
                          final deliveryFailed =
                              deliveryStatus == FailedMessageStatus.failed;
                          final messageChild = AiMessageView(
                            key: ValueKey(ai.id),
                            message: ai,
                            actionBarHoverEnabled: _hoverEffectsEnabled,
                            actionBarReveal: deliveryFailed || ai.id == lastId
                                ? AiActionBarReveal.always
                                : AiActionBarReveal.hover,
                            onRetryDelivery:
                                deliveryFailed &&
                                    widget.onRetryFailedMessage != null
                                ? () => widget.onRetryFailedMessage!(ai.id)
                                : null,
                            // Keep the tip "thinking" expanded while it streams;
                            // collapse once a non-thinking part appears or the
                            // message is no longer the last real message.
                            chainOfThoughtAutoExpand:
                                ai.id == realTipId &&
                                aiMessageIsThinkingOnly(ai),
                          );
                          var result = tightenForRunning
                              ? Theme(
                                  data: Theme.of(context).copyWith(
                                    extensions: [
                                      ...Theme.of(context).extensions.values
                                          .where((e) => e is! AiMessageTheme),
                                      aiTheme.copyWith(messageSpacing: 8),
                                    ],
                                  ),
                                  child: messageChild,
                                )
                              : messageChild;
                          // Chat find current match: ring the bubble so the jump
                          // target is obvious even when it is off-center.
                          if (ai.id == widget.highlightMessageId) {
                            final cs = Theme.of(context).colorScheme;
                            result = Container(
                              margin: const EdgeInsets.symmetric(vertical: 2),
                              padding: const EdgeInsets.all(3),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: cs.primary,
                                  width: 1.5,
                                ),
                              ),
                              child: result,
                            );
                          }
                          return result;
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        thread,
        if (_showNewMessagesChip && !_stickToEnd)
          _buildNewMessagesChip(context),
      ],
    );
  }
}
