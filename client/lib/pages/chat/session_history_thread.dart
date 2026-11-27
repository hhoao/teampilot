import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:ai_message_core/ai_message_core.dart';
import 'package:ai_message_ui/ai_message_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../l10n/l10n_extensions.dart';
import '../../models/failed_message_record.dart';
import '../../models/pending_branch_edit.dart';
import '../../services/chat/rewind/edit/edit_operation.dart';
import '../../services/chat/rewind/edit/seat_edit_coordinator.dart';
import '../../services/chat/rewind/seat_branches.dart';
import '../../utils/chat/chat_timestamp_format.dart';
import '../../widgets/session_working_spinner.dart';
import 'chat_message_action_menu.dart';
import 'edit_retry_button.dart';
import 'chat_message_edit_panel.dart';
import 'chat_outline.dart';
import 'chat_reveal_controller.dart';
import 'history_scroll_cursor_lock.dart';
import 'session_history_live_chrome.dart';
import 'session_history_scroll_to_bottom_button.dart';

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

/// Synthetic user bubble for a landing create+send that is still connecting.
///
/// Rendered only from [SessionHistoryThread.pendingUserText]; never enters the
/// runtime or the history store.
const String kSessionHistoryPendingLandingUserId = 'pending:landing';

/// Whether [chrome] means a turn is actively producing output (as opposed to
/// idle history review or a background task that outlived the turn).
bool _liveTurnActive(SessionHistoryLiveChrome chrome) =>
    chrome == SessionHistoryLiveChrome.starting ||
    chrome == SessionHistoryLiveChrome.running;

/// True when the message still ends inside a thinking chain — reasoning or a
/// tool call. Once assistant prose follows, the chain is finished output and
/// folds back to its summary row.
bool _endsWithThinking(AiMessage message) {
  if (message.parts.isEmpty) return false;
  final last = message.parts.last;
  return last is AiReasoningPart || last is AiToolCallPart;
}

/// History message list for session review.
///
/// Owns scroll chrome (stick-to-end, load-older anchoring, hover-effects
/// gate + cursor lock, [SelectionArea] nested inside the scroll content,
/// new-messages chip). Desktop mounts the full pagination data window (retain
/// + chunked fill) so scrolling does not remount markdown. Mobile keeps only
/// the visible/overscan turns mounted. Older pages still arrive via
/// [onLoadOlder].
class SessionHistoryThread extends StatefulWidget {
  const SessionHistoryThread({
    required this.runtime,
    this.userAttachmentWorkspaceRoot = '',
    this.userAttachmentUsesPosixPaths = true,
    this.onOpenUserImage,
    required this.hasOlder,
    required this.isLoadingOlder,
    this.onLoadOlder,
    this.liveChrome = SessionHistoryLiveChrome.none,
    this.backgroundLabel,
    this.provisioningLabel,
    this.pendingDeliveryStatuses = const {},
    this.onRetryFailedMessage,
    this.highlightMessageId,
    this.revealRequest,
    this.visibleOwnerId,
    this.scrollAnchorKey,
    this.scrollAnchors,
    this.mobilePerformanceMode,
    this.branches = const SeatBranches.empty(),
    this.onSwitchVersion,
    this.onForkFrom,
    this.onEditUserMessage,
    this.onPickEditAttachments,
    this.holdTranscript = false,
    this.seatEdit,
    this.onOptimisticLanded,
    this.turnInFlight = false,
    this.pendingUserText = '',
    super.key,
  });

  final AiThreadRuntime runtime;
  final String userAttachmentWorkspaceRoot;
  final bool userAttachmentUsesPosixPaths;
  final ValueChanged<AiUserMessageImage>? onOpenUserImage;
  final bool hasOlder;
  final bool isLoadingOlder;
  final Future<void> Function()? onLoadOlder;

  /// Slim starting/running footer under the scroll surface.
  final SessionHistoryLiveChrome liveChrome;

  /// What the out-of-turn background work is doing (e.g. the background shell
  /// task's description). Appended to the background footer so the row says
  /// what is still running, not just that something is.
  final String? backgroundLabel;

  /// Fixed status text while an SSH member's remote environment provisions.
  /// Overrides the [liveChrome] label; the spinner is still chosen by
  /// [liveChrome]. Null keeps the existing Starting… / Running… copy.
  final String? provisioningLabel;

  /// Transient first prompt of a landing create+send, painted as a user bubble
  /// until the runtime owns that turn (ACP `sendPrompt` / PTY pending).
  ///
  /// Memory-only: the bubble is synthesized per build and never written to the
  /// runtime, the history store, or disk. Empty for every non-landing path.
  final String pendingUserText;

  final Map<String, FailedMessageStatus> pendingDeliveryStatuses;
  final ValueChanged<String>? onRetryFailedMessage;

  /// Message id whose bubble gets a highlight ring (chat find current match).
  final String? highlightMessageId;

  /// Carries the reveal intent (jump + highlight) from the chat find host.
  final ChatRevealController? revealRequest;

  /// Owning user-turn id of the first viewport-visible turn. Host-owned;
  /// updated from [VirtualThreadViewport.onVisibleRange] without [setState].
  final ValueNotifier<String?>? visibleOwnerId;

  /// Key into [scrollAnchors] (the session id) for scroll-position restore.
  /// When set together with [scrollAnchors], this thread writes its offset to
  /// the map on dispose and jumps back to the stored offset on mount, so a
  /// host remount (e.g. a tab moving between workbench split groups) restores
  /// the reading position.
  final String? scrollAnchorKey;

  /// Host-owned anchor map (sessionId → offset). In the app this is
  /// `ChatCubit.sessionScrollAnchors`; passed as a plain map reference so the
  /// thread stays decoupled from the cubit (and testable without one).
  final Map<String, double>? scrollAnchors;

  /// Overrides the mobile history mounting policy for deterministic tests.
  /// Defaults to the Android/iOS platform check.
  final bool? mobilePerformanceMode;

  /// Versions of each user message on this seat.
  final SeatBranches branches;

  /// Restores the branch that the commit belongs to.
  final void Function(String commit)? onSwitchVersion;

  /// Copies the branch through the commit into a new session.
  final void Function(String commit)? onForkFrom;

  /// Submits an edit. Returns true when the edit was accepted (not when it
  /// finished), so the editor can close immediately.
  final Future<bool> Function(
    String messageId,
    String text, {
    required bool reopenEditor,
  })?
  onEditUserMessage;

  /// Opens the host file picker while a user message is being edited and
  /// returns `@` references to insert into the draft.
  final Future<List<String>> Function()? onPickEditAttachments;

  /// Keeps the transcript on screen while an edit restores and resends.
  ///
  /// The restore replays the parent branch into the seat; rendering that
  /// intermediate state and then the new turn makes the thread flash twice.
  final bool holdTranscript;

  /// Shared edit transaction; when omitted the thread owns a private
  /// coordinator (tests and standalone usage).
  final SeatEditCoordinator? seatEdit;

  /// Call when the runtime publishes the resent prompt.
  final VoidCallback? onOptimisticLanded;

  /// When true, the controls stay visible but disabled.
  final bool turnInFlight;

  @override
  State<SessionHistoryThread> createState() => _SessionHistoryThreadState();
}

class _SessionHistoryThreadState extends State<SessionHistoryThread> {
  static const _hoverResumeIdle = Duration(milliseconds: 160);
  static const _bottomEpsilon = 1.0;
  static const _loadOlderPixelThreshold = 120.0;

  /// Distance from the tip past which the jump-to-bottom button is offered.
  static const _scrollToBottomThreshold = 80.0;

  /// Slack for [_isClampDrop]: a shrink clamp can land slightly short of the
  /// new tip when the turn grew again in the same frame (one thinking/prose
  /// line). Kept separate from [_scrollToBottomThreshold] so tuning the button
  /// distance cannot silently change layout-clamp detection.
  static const _layoutClampSlack = 80.0;

  /// Frames the anchor restore waits for the virtualized viewport to grow
  /// its extent toward the anchor (turns mount lazily / in chunks).
  static const _anchorRestoreFrames = 24;

  late final ScrollController _scrollController;
  StreamSubscription<void>? _runtimeSub;

  /// Scroll offset to restore on mount (read from [SessionHistoryThread
  /// .scrollAnchors] in initState); consumed by the restore frames.
  double? _pendingRestoreAnchor;

  /// True while the anchor-restore tick chain owns the scroll offset (from
  /// mount until the restored jump lands, plus a holdoff window). While
  /// active, measure corrections from [VirtualThreadViewport] are dropped:
  /// the restored offset targets the estimate-space layout of a cold mount,
  /// and corrections for turns above the viewport would drag it away from
  /// the anchor (stick-to-end suppresses them for the same reason). Cleared
  /// when the chain finishes, when a stick/load-older regime takes over, or
  /// on user scroll.
  var _anchorRestoreActive = false;

  /// While false, ignore ActionBar hover-enter and force basic cursor
  /// (scroll-under-pointer).
  final ValueNotifier<bool> _hoverEffectsEnabled = ValueNotifier(true);
  Timer? _hoverResumeTimer;

  var _stickToEnd = true;
  var _stickGeneration = 0;

  /// Whether this transcript's host is foreground. Keep-alive tabs wrap
  /// inactive hosts in `TickerMode(enabled: false)`; a background transcript
  /// keeps building (and the runtime keeps growing its tip), but unmounted
  /// turns are only estimated, so the viewport extent churns. Tracked via
  /// [TickerMode.valuesOf] (dependency registered in [didChangeDependencies])
  /// so returning to the tab can re-anchor to the tip.
  var _foreground = true;

  /// Delay message mounts until after the first jump-to-end so open does not
  /// build the top of the thread under a scroll offset of 0.
  var _mountTurns = false;

  /// Tip grew while stick was paused — badge the jump button until the user
  /// resumes following.
  var _hasNewMessagesBelow = false;

  /// Whether the transcript is far enough from the tip to show the floating
  /// jump-to-bottom button. Kept in a notifier so scroll ticks rebuild only
  /// the button, not the whole thread.
  final ValueNotifier<bool> _showScrollToBottom = ValueNotifier(false);

  double _lastPixels = 0;

  var _loadOlderInFlight = false;
  var _paginationArmed = true;

  /// While awaiting/applying an older-page prepend, skip viewport-internal
  /// measure correction so the thread applies extent correction once.
  var _anchoringOlder = false;
  int? _olderCaptureCount;
  double? _olderPixelsBefore;
  double? _olderMaxBefore;

  List<AiMessage> _messages = const [];

  SeatEditCoordinator? _ownSeatEdit;

  ThemeData? _tightenedTheme;
  ThemeData? _tightenedThemeBase;

  /// Extent seen by the previous scroll tick. A shrink clamps the offset down
  /// to the new tip (the thinking body folding away when prose starts) with no
  /// scroll notification, so both the "release" and the "back on the tip"
  /// re-arm must ignore it — otherwise the follow dies or re-arms mid-drag.
  double _extentBaseline = 0;

  SeatEditCoordinator get _edit =>
      widget.seatEdit ??
      (_ownSeatEdit ??= SeatEditCoordinator(
        sessionId: '',
        run: _noopEditRun,
        watchdog: Duration.zero,
      ));

  /// Standalone threads never own a runtime; a submitted edit is a no-op.
  static Future<void> _noopEditRun({
    required String sessionId,
    required String memberId,
    required String userMessageId,
    required String text,
    required void Function(EditPhase phase) onPhase,
    required bool Function() aborted,
  }) async {}

  /// Theme for the live tip while the Running footer is appended: tightens the
  /// message's bottom gap so the footer sits under it like in-turn chrome.
  ///
  /// Cached against the base [ThemeData] instance: the extension is read from
  /// that same theme, so a new base theme invalidates the cache.
  /// Building a fresh copy per streamed chunk marked every Theme-dependent
  /// widget in the message dirty and re-created the descendant
  /// [ScrollPosition]s (framework didChangeDependencies → _updatePosition),
  /// which cancels in-flight scroll activities (the thinking body's follow,
  /// drags) and defeats the per-part render cache.
  ThemeData _tightenedTipTheme(BuildContext context, AiMessageTheme aiTheme) {
    final base = Theme.of(context);
    final cached = _tightenedTheme;
    if (cached != null && identical(base, _tightenedThemeBase)) {
      return cached;
    }
    final next = base.copyWith(
      extensions: [
        ...base.extensions.values.where((e) => e is! AiMessageTheme),
        aiTheme.copyWith(messageSpacing: 8),
      ],
    );
    _tightenedTheme = next;
    _tightenedThemeBase = base;
    return next;
  }

  Object? _bodyCacheKeyForTurn(ThreadTurn turn) {
    final keys = <Object?>[
      // Editing dims every turn, so all cached bodies must rebuild when the
      // edit state starts / stops — not just the turn owning the message.
      _edit.editingMessageId,
      // A new edit transaction must rebuild the body so the inline editor is a
      // fresh State (the previous one latched itself as submitted).
      _edit.operation?.id,
      widget.onSwitchVersion != null,
      widget.onForkFrom != null,
      widget.onEditUserMessage != null,
    ];
    for (final id in turn.messageIds) {
      if (id == _edit.editingMessageId) keys.add('editing:$id');
      // A failed-delivery flip must refresh the "Retry" menu item.
      keys.add(widget.pendingDeliveryStatuses[id]);
      final version = widget.branches.turnOf(id);
      if (version != null) {
        keys.add(Object.hash(version.commit, version.index, version.count));
      }
    }
    return Object.hashAll(keys);
  }

  /// Hands the edit to the host, which accepts it synchronously and runs the
  /// resend in the background. A true result only means "accepted".
  Future<bool> _submitEdit(
    AiMessage message,
    String text, {
    bool reopenEditorOnFailure = false,
  }) {
    final submit = widget.onEditUserMessage;
    if (submit == null) return Future<bool>.value(false);
    _editBaselineIds = _messages.map((message) => message.id).toSet();
    return submit(
      message.id,
      text,
      reopenEditor: reopenEditorOnFailure,
    );
  }

  Future<void> _openMobileEdit(
    BuildContext context,
    AiMessage message,
  ) async {
    if (!mounted) return;
    final rewindEnabled =
        AiMessageInteractionScope.maybeRewindEnabled(context) ??
        !widget.turnInFlight;
    if (!rewindEnabled || _edit.editingMessageId == message.id) return;
    _edit.openEditor(message.id);
    await showChatMessageEditSheet(
      context,
      initialText: _edit.draft ?? plainTextForCopy(message),
      title: context.l10n.edit.userMessage,
      cancelLabel: context.l10n.edit.cancel,
      sendLabel: context.l10n.edit.send,
      onSubmit: (text) => _submitEdit(message, text),
    );
    if (!mounted) return;
    // The sheet is gone either way: drop the editor latch so the transcript is
    // not left dimmed behind a missing editor.
    _edit.cancelEditor();
  }

  PendingBranchEdit? get _pendingEdit => _edit.pending;

  /// Message ids visible when the edit started: a replayed parent message is
  /// never mistaken for the resent prompt.
  Set<String> _editBaselineIds = const {};

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
    _edit.addListener(_onBranchEditChanged);
    _scrollController = ScrollController()..addListener(_onScrollTick);
    _runtimeSub = widget.runtime.changes.listen((_) => _onRuntimeChanged());
    _boundReveal = widget.revealRequest;
    _boundReveal?.addListener(_onRevealRequestChanged);
    _pendingRestoreAnchor = _readScrollAnchor();
    if (_pendingRestoreAnchor != null) {
      // Restoring a mid-thread reading position: the thread must not stick
      // to the tip while the restore lands.
      _stickToEnd = false;
      _anchorRestoreActive = true;
    }
    _scheduleOpenAtEnd();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final enabled = TickerMode.valuesOf(context).enabled;
    final becameForeground = enabled && !_foreground;
    _foreground = enabled;
    _syncScrollToBottom();
    if (becameForeground) {
      _restickAfterForeground();
    }
  }

  /// Returning to a kept-alive tab. Background hosts are wrapped in
  /// `TickerMode(enabled: false)`, and their transcript keeps growing while
  /// away: estimates for unmounted turns make the extent churn and the last
  /// observed offset no longer describes what the user will see. If the thread
  /// was following the tip when it left, rebase the offset bookkeeping and
  /// jump to the real tip (post-frame: this frame's layout has applied the
  /// new extent), then keep following.
  void _restickAfterForeground() {
    if (!mounted) return;
    if (_anchorRestoreActive || _pendingRestoreAnchor != null) return;
    if (_scrollController.hasClients) {
      final position = _scrollController.position;
      _lastPixels = position.pixels;
      // The extent churned while the host was inactive (estimates for unmounted
      // turns, plus anything the turn streamed). Rebase the clamp baseline too,
      // or the first foreground tick reads that churn as a layout clamp.
      _extentBaseline = position.maxScrollExtent;
    }
    if (!_stickToEnd) return;
    _scheduleStickFrames();
  }

  @override
  void didUpdateWidget(covariant SessionHistoryThread oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.seatEdit, widget.seatEdit)) {
      (oldWidget.seatEdit ?? _ownSeatEdit)?.removeListener(
        _onBranchEditChanged,
      );
      _edit.addListener(_onBranchEditChanged);
    }
    if (oldWidget.runtime != widget.runtime) {
      // Member/seat switch keeps the default open-at-end behavior — anchor
      // restore only applies to a fresh mount of the same thread.
      _cancelAnchorRestore();
      _runtimeSub?.cancel();
      _setStickToEnd(true);
      _hasNewMessagesBelow = false;
      _paginationArmed = true;
      _mountTurns = false;
      // Keep the controller's draft: a runtime swap also happens when an edit
      // fails, and the editor must reopen with the author's text.
      _edit.runtimeSwapped();
      if (_pendingEdit == null) {
        _messages = widget.runtime.messages;
      }
      // The restore swaps the seat runtime mid-edit; keep the optimistic
      // branch and wait for the new runtime to publish the resent prompt.
      _runtimeSub = widget.runtime.changes.listen((_) => _onRuntimeChanged());
      _scheduleOpenAtEnd();
    } else if (oldWidget.holdTranscript && !widget.holdTranscript) {
      _onRuntimeChanged();
    } else if (oldWidget.liveChrome != widget.liveChrome) {
      if (widget.liveChrome.isActive && _stickToEnd) {
        _scheduleStickFrames();
      }
    }
    if (oldWidget.pendingUserText != widget.pendingUserText &&
        widget.pendingUserText.trim().isNotEmpty &&
        _stickToEnd) {
      // Landing bubble arrives after mount (tab opens first): keep it pinned.
      _scheduleStickFrames();
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
      if (value) _hasNewMessagesBelow = false;
    });
    _syncScrollToBottom();
  }

  @override
  void dispose() {
    (widget.seatEdit ?? _ownSeatEdit)?.removeListener(_onBranchEditChanged);
    _ownSeatEdit?.dispose();
    _writeScrollAnchor();
    _stickGeneration++;
    _hoverResumeTimer?.cancel();
    _hoverEffectsEnabled.dispose();
    _showScrollToBottom.dispose();
    _runtimeSub?.cancel();
    _boundReveal?.removeListener(_onRevealRequestChanged);
    _scrollController
      ..removeListener(_onScrollTick)
      ..dispose();
    super.dispose();
  }

  double? _readScrollAnchor() {
    final key = widget.scrollAnchorKey;
    if (key == null) return null;
    return widget.scrollAnchors?[key];
  }

  /// Persists the current reading position into the host-owned anchor map so
  /// a remount (e.g. a tab moving between workbench split groups) can
  /// restore it. Child scrollables unmount before this State disposes, so
  /// the controller is usually already detached — fall back to the last
  /// observed offset tracked by the scroll listener.
  void _writeScrollAnchor() {
    final key = widget.scrollAnchorKey;
    final anchors = widget.scrollAnchors;
    if (key == null || anchors == null) return;
    final offset = _scrollController.hasClients
        ? _scrollController.position.pixels
        : _lastPixels;
    anchors[key] = offset;
  }

  /// Ends the anchor-restore regime: re-enables measure corrections so later
  /// layout changes (load-older prepend, expand) keep the content under the
  /// viewport stable.
  void _endAnchorRestore() {
    if (!mounted) return;
    _pendingRestoreAnchor = null;
    if (!_anchorRestoreActive) return;
    // Scroll notifications (incl. jumpTo) can arrive during layout/paint.
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase != SchedulerPhase.idle &&
        phase != SchedulerPhase.postFrameCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _endAnchorRestore();
      });
      return;
    }
    setState(() => _anchorRestoreActive = false);
  }

  /// A new scroll regime (user drag, stick frames) took over before the
  /// restore landed — kill the restore tick chain and end the regime.
  void _cancelAnchorRestore() {
    _stickGeneration++;
    _endAnchorRestore();
  }

  void _onBranchEditChanged() {
    if (mounted) setState(() {});
  }

  void _onRuntimeChanged() {
    if (!mounted) return;
    // An edit restores the parent branch first; hold the old transcript until
    // the new turn lands so the thread switches once instead of twice.
    if (_edit.holdsTranscript || widget.holdTranscript) return;
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
    // The restore replays the parent prefix before the new turn exists. Keep
    // the optimistic branch on screen until the list carries the new prompt.
    final pending = _pendingEdit;
    if (pending != null && !_listHasPendingEdit(next)) {
      return;
    }
    if (pending != null) {
      _edit.markLanded();
      widget.onOptimisticLanded?.call();
    }
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
        _hasNewMessagesBelow = true;
      }
    });
    if (_stickToEnd && !wasPrepend && _foreground) {
      // Background hosts only estimate unmounted turns, so the extent churns;
      // chasing it there jitters the offset and can trip the release
      // heuristic. The foreground handoff re-anchors to the real tip instead.
      _scheduleStickFrames();
    }
    // Content can grow below the viewport without changing `pixels`, so the
    // scroll listener may not fire; re-check once layout applies the extent.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncScrollToBottom();
    });
  }

  /// Whether [next] ends with the user message the edit resent.
  ///
  /// The restored prefix ends with the parent's prompt, so matching the last
  /// user text is what tells the new branch apart from the replayed one.
  bool _listHasPendingEdit(List<AiMessage> next) {
    final expected = _pendingEdit?.text.trim() ?? '';
    if (expected.isEmpty) return true;
    for (final message in next.reversed) {
      if (message.role != AiRole.user) continue;
      if (_editBaselineIds.contains(message.id)) return false;
      final text = message.parts
          .whereType<AiTextPart>()
          .map((part) => part.text)
          .join()
          .trim();
      return text == expected;
    }
    return false;
  }

  /// Editing replaces the message with text only, so attachments/structured
  /// parts would be silently dropped on resend.
  static bool _isPureText(AiMessage message) =>
      message.parts.isNotEmpty &&
      message.parts.every((part) => part is AiTextPart);

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
    // Streaming updates keep the length stable; return before scanning the
    // whole window on every chunk.
    if (current.isEmpty || next.length <= current.length) return false;
    final offset = next.length - current.length;
    for (var i = 0; i < current.length; i++) {
      if (current[i].id != next[i + offset].id) return false;
    }
    return true;
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

  /// Whether an offset drop of [drop] pixels with an extent shrinking by
  /// [shrink] pixels is a layout clamp rather than a user scroll. The clamp
  /// drops the offset by about the shrink; a drag adds its own movement on top.
  bool _isClampDrop(double shrink, double drop) =>
      shrink > _bottomEpsilon && drop >= shrink - _layoutClampSlack;

  void _onScrollTick() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    final pixels = position.pixels;
    final max = position.maxScrollExtent;

    // Release when the offset moved up and we are no longer pinned to the tip.
    // The extent is *not* required to be stable: while a turn streams the tip
    // grows every frame, and requiring `maxScrollExtent` to be unchanged (the
    // previous rule) disabled this release for the whole streaming window.
    //
    // A shrinking extent clamps the offset to the new tip: it looks like both
    // a scroll-up (release) and a "user came back to the tip" (re-arm), and
    // both would be wrong — the thinking body folding away is the common case.
    //
    // Background hosts are skipped: the thread keeps building there, but
    // unmounted-turn estimates churn the extent, so an offset drop is layout
    // noise, not a drag. Releasing on it would silently stop the follow for
    // good (the user is not there to scroll back down). [_restickAfterForeground]
    // re-anchors on return instead.
    final shrink = _extentBaseline - max;
    final drop = _lastPixels - pixels;
    _extentBaseline = max;
    final clamped = _isClampDrop(shrink, drop);
    if (_foreground) {
      if (_stickToEnd &&
          !clamped &&
          drop > _bottomEpsilon &&
          max - pixels > _bottomEpsilon) {
        _setStickToEnd(false);
      } else if (!_stickToEnd &&
          shrink <= _bottomEpsilon &&
          max - pixels <= _bottomEpsilon) {
        // Manual scroll back to tip — same as tapping the jump button. A
        // shrinking extent also lands on the tip; that must not re-arm.
        _resumeStickToTip();
      }
    }

    _lastPixels = pixels;
    _captureOlderExtentIfWaiting();
    _syncScrollToBottom();
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
      final anchor = _pendingRestoreAnchor;
      if (anchor != null) {
        _scheduleAnchorRestore(anchor);
        return;
      }
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

  /// Restores a previously stored reading position: waits (bounded frames)
  /// until the viewport extent covers the anchor, then jumps to it clamped to
  /// [ScrollPosition.maxScrollExtent]. Skips silently while the position is
  /// not yet attached or the extent is still zero. After the jump the regime
  /// stays active for the remaining frames so late above-viewport
  /// measurements cannot correct the restored offset away (their corrections
  /// are dropped while [_anchorRestoreActive]).
  void _scheduleAnchorRestore(double anchor) {
    final generation = ++_stickGeneration;
    // A bare post-frame chain does not schedule frames; without this the
    // restore stalls once fill/measure settles (nothing else requests a
    // frame, so the queued tick never runs).
    void tick(int framesLeft) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || generation != _stickGeneration) return;
        if (!_scrollController.hasClients) {
          if (framesLeft > 1) {
            SchedulerBinding.instance.ensureVisualUpdate();
            tick(framesLeft - 1);
          } else {
            _endAnchorRestore();
          }
          return;
        }
        if (!_mountTurns) {
          setState(() => _mountTurns = true);
        }
        final max = _scrollController.position.maxScrollExtent;
        if (max <= 0 || (max < anchor && framesLeft > 1)) {
          SchedulerBinding.instance.ensureVisualUpdate();
          tick(framesLeft - 1);
          return;
        }
        _pendingRestoreAnchor = null;
        _jumpTo(anchor.clamp(0.0, max));
        if (_scrollController.hasClients &&
            _scrollController.position.maxScrollExtent -
                    _scrollController.position.pixels <=
                _bottomEpsilon) {
          // Landed on the tip — resume stick so live growth keeps following.
          _resumeStickToTip();
          return;
        }
        if (framesLeft > 1) {
          SchedulerBinding.instance.ensureVisualUpdate();
          tick(framesLeft - 1);
          return;
        }
        _endAnchorRestore();
      });
    }

    tick(_anchorRestoreFrames);
  }

  void _scheduleStickFrames({int framesLeft = 12}) {
    // Stick frames own the offset now — a still-pending anchor restore must
    // not fight them.
    _endAnchorRestore();
    final generation = ++_stickGeneration;
    void tick(int left) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || generation != _stickGeneration || !_stickToEnd) return;
        // A background host's extent churns with unmounted-turn estimates;
        // chasing it there jitters the offset and can trip the release below.
        // [_restickAfterForeground] picks the tip up again on return.
        if (!_foreground) return;
        if (_scrollController.hasClients) {
          final max = _scrollController.position.maxScrollExtent;
          final pixels = _scrollController.position.pixels;
          // Stick release lives in [_onScrollTick] and the scroll
          // notifications; this chain only keeps the offset on the tip.
          // Never move the offset under an active gesture: `jumpTo` calls
          // `goIdle()`, which disposes the drag/fling and makes the thread
          // unscrollable while a turn streams. `isScrollingNotifier` is true
          // exactly while a drag, fling or animation owns the offset.
          final gestureActive =
              _scrollController.position.isScrollingNotifier.value;
          if (!gestureActive && max > 0 && max - pixels > _bottomEpsilon) {
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

  bool get _scrollToBottomVisible {
    if (!_foreground || _stickToEnd || !_scrollController.hasClients) {
      return false;
    }
    final position = _scrollController.position;
    return position.maxScrollExtent > 0 &&
        position.maxScrollExtent - position.pixels > _scrollToBottomThreshold;
  }

  /// Keeps the jump-button visibility in sync with the scroll offset.
  ///
  /// Scroll listeners fire during layout, so a sync notifier write would
  /// rebuild the button mid-frame ("Build scheduled during frame") — defer
  /// those to the frame callback, same as [_setHoverEnabled].
  void _syncScrollToBottom() {
    final visible = _scrollToBottomVisible;
    if (_showScrollToBottom.value == visible) return;
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase != SchedulerPhase.idle &&
        phase != SchedulerPhase.postFrameCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final next = _scrollToBottomVisible;
        if (_showScrollToBottom.value != next) {
          _showScrollToBottom.value = next;
        }
      });
      return;
    }
    _showScrollToBottom.value = visible;
  }

  void _animateScrollToBottom() {
    if (!_scrollController.hasClients) return;
    // Clears the new-messages dot and hides the button immediately.
    _setStickToEnd(true);
    final position = _scrollController.position;
    final distance = position.maxScrollExtent - position.pixels;
    if (distance <= _bottomEpsilon) {
      _scheduleStickFrames();
      return;
    }
    final ms = (240 + distance * 0.12).clamp(240, 480).round();
    unawaited(
      _scrollController
          .animateTo(
            position.maxScrollExtent,
            duration: Duration(milliseconds: ms),
            curve: Curves.easeInOutCubic,
          )
          .whenComplete(() {
            // A mid-flight user drag releases stick; re-pinning then would
            // fight the user and snap them back down.
            if (mounted && _stickToEnd) _scheduleStickFrames();
          }),
    );
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
    // Only the transcript's own scrollable may drive hover suppression, stick
    // release and pagination. Notifications from nested scrollables (the
    // reasoning body's auto-follow `jumpTo`, tool output panes, …) bubble up
    // here with depth > 0; treating them as history scrolls made the cursor
    // lock flap between basic and click while reasoning streamed inside its
    // max-height box, and let an inner drag cancel stick-to-end.
    if (notification.depth != 0) return false;
    if (notification is UserScrollNotification &&
        notification.direction != ScrollDirection.idle) {
      _setStickToEnd(false);
      _cancelAnchorRestore();
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
        // A shrink clamp also reports a negative delta; see [_onScrollTick].
        final clamped = _isClampDrop(
          _extentBaseline - notification.metrics.maxScrollExtent,
          -delta,
        );
        if (delta < 0 && !clamped) {
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
      await widget.onLoadOlder!.call();
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

  Widget _buildRunningInMessage(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isBackground =
        widget.liveChrome == SessionHistoryLiveChrome.background;
    final backgroundLabel = widget.backgroundLabel?.trim() ?? '';
    final label = widget.provisioningLabel ?? switch (widget.liveChrome) {
      SessionHistoryLiveChrome.starting => context.l10n.session.historyStarting,
      SessionHistoryLiveChrome.background =>
        backgroundLabel.isEmpty
            ? context.l10n.session.historyBackgroundRunning
            : '${context.l10n.session.historyBackgroundRunning} · '
                  '$backgroundLabel',
      SessionHistoryLiveChrome.running ||
      SessionHistoryLiveChrome.none => context.l10n.session.historyRunning,
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
            // Background work is not a turn: show the breathing hourglass
            // instead of the running spinner so the two states stay
            // distinguishable — yet the footer still reads as alive.
            if (isBackground)
              SessionBackgroundWorkMarker(
                size: 14,
                color: scheme.onSurfaceVariant,
              )
            else
              TpIndeterminateSpinner(
                size: 14,
                strokeWidth: 2,
                color: scheme.onSurfaceVariant,
              ),
            const SizedBox(width: 10),
            // The background label can be an arbitrary tool description, so
            // clip it instead of overflowing the footer row.
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TpTextStyles.of(
                  context,
                ).smColored(scheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Appends the transient landing bubble while it is not in [messages] yet.
  ///
  /// Matching by role + text (not id) keeps the swap seamless: the ACP queued
  /// prompt and the hydrated PTY pending reuse the user's own words, so the
  /// synthetic bubble drops itself the frame the real turn lands.
  List<AiMessage> _withPendingLandingUser(List<AiMessage> messages) {
    final text = widget.pendingUserText.trim();
    if (text.isEmpty) return messages;
    final alreadyPresent = messages.any(
      (m) =>
          m.role == AiRole.user &&
          m.parts.any((p) => p is AiTextPart && p.text.trim() == text),
    );
    if (alreadyPresent) return messages;
    return [
      ...messages,
      AiMessage(
        id: kSessionHistoryPendingLandingUserId,
        role: AiRole.user,
        parts: [AiTextPart(text: text)],
      ),
    ];
  }

  List<AiMessage> get _displayMessages {
    final pending = _pendingEdit;
    if (pending != null) {
      final index = _messages.indexWhere(
        (message) => message.id == pending.messageId,
      );
      final edited = index >= 0
          ? _messages[index].copyWith(parts: [AiTextPart(text: pending.text)])
          : AiMessage(
              id: pending.messageId,
              role: AiRole.user,
              parts: [AiTextPart(text: pending.text)],
            );
      // The edited bubble shows its new text immediately and everything the
      // old branch had below it becomes the running row, so the thread does
      // not repaint the restored branch and then the new one.
      return [
        ..._messages.take(index < 0 ? _messages.length : index),
        edited,
        kSessionHistoryRunningPlaceholder,
      ];
    }
    final messages = _withPendingLandingUser(_messages);
    if (!widget.liveChrome.isActive) return messages;
    if (messages.any((m) => m.id == kSessionHistoryRunningPlaceholder.id)) {
      return messages;
    }
    return [...messages, kSessionHistoryRunningPlaceholder];
  }

  @override
  Widget build(BuildContext context) {
    final mobile =
        widget.mobilePerformanceMode ?? (Platform.isAndroid || Platform.isIOS);
    final displayMessages = _displayMessages;
    final lastId = displayMessages.isEmpty ? null : displayMessages.last.id;
    final forkLabel = context.l10n.forkFromHere;
    final editLabel = context.l10n.edit.userMessage;
    final editSendLabel = context.l10n.edit.send;
    final editCancelLabel = context.l10n.edit.cancel;
    final previousVersionLabel = context.l10n.branchPrevious;
    final nextVersionLabel = context.l10n.branchNext;
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
          // SelectionArea must sit *inside* the scroll content, never wrap the
          // scrollable. As a scroll ancestor it enables the framework's
          // selection edge auto-scroll (_ScrollableSelectionContainerDelegate),
          // which is broken against this virtualized viewport: fill/retain
          // mount churn makes the delegate re-dispatch synthesized edge events
          // from stale fragment geometry every frame, re-arming the auto
          // scroller — a plain trackpad click on text then crawls the thread
          // upward uncontrollably, and geometry-inferred edge positions
          // (−lineHeight/2, estimated turn heights) land the highlight above
          // the pointer. Nesting inside removes that delegate entirely
          // (flutter/flutter#110917 workaround; same arrangement as before
          // commit 3df44f6dc re-exposed it).
          child: SingleChildScrollView(
            controller: _scrollController,
            padding: EdgeInsets.fromLTRB(
              0,
              aiTheme.threadTopPadding,
              0,
              aiTheme.threadBottomPadding,
            ),
            // Width chrome outside [VirtualThreadViewport]: turn bodies are
            // cached and would keep a stale per-message ConstrainedBox.
            child: Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: aiTheme.threadHorizontalPadding,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: aiTheme.threadMaxWidth),
                  child: AiLineSpacedSelectionStyle(
                    child: SelectionArea(
                      contextMenuBuilder: buildTpSelectionAreaContextMenu,
                      child: VirtualThreadViewport(
                        messages: displayMessages,
                        scrollController: _scrollController,
                        header: header,
                        anchorEnd: true,
                        overscan: 5,
                        // Desktop keeps the loaded pagination window mounted while
                        // scrolling; mobile stays bounded to visible/overscan turns.
                        retainMountedTurns: !mobile,
                        fillDataWindow: !mobile,
                        // Offstage hosts never lay out or paint, so growing the
                        // window there only makes the return frame bigger.
                        allowFill: _foreground,
                        mountTurns: _mountTurns,
                        // Rebuild turn bodies when the highlight target changes
                        // so the ring moves even though the message list
                        // instance is unchanged (see VirtualThreadViewport.buildKey).
                        buildKey: widget.highlightMessageId,
                        // Branch versions and fork/switch callbacks can land
                        // after the first mount (generation bump, same live
                        // list). Drop cached turn bodies so the action bar
                        // appears without a new message list instance.
                        // Only the turn that owns the edited message or its
                        // version control needs a new body. The busy flag is
                        // delivered through AiMessageInteractionScope so it
                        // can rebuild action bars without dropping this cache.
                        bodyCacheKeyForTurn: _bodyCacheKeyForTurn,
                        revealMessageId: _revealTargetId,
                        revealEpoch: _revealEpoch,
                        onRevealOffset: (offset) {
                          if (!_scrollController.hasClients || offset < 0) {
                            return;
                          }
                          // threadTopPadding = SingleChildScrollView top padding;
                          // the delivered offset is viewport-space document pixels.
                          _scrollToReveal(offset + aiTheme.threadTopPadding);
                        },
                        onVisibleRange: _publishVisibleOwner,
                        suppressMeasureScrollCorrection:
                            _stickToEnd || _anchoringOlder,
                        onMeasureScrollCorrection: (delta) {
                          if (_revealAnimating) return;
                          // A background host lays out only through estimates for
                          // unmounted turns; correcting the offset there walks
                          // the reading position toward the tip behind the
                          // user's back. The visible range is append-only, so
                          // there is nothing to compensate on return either.
                          if (!_foreground) return;
                          // The anchor-restore regime owns the offset; see
                          // [_anchorRestoreActive].
                          if (_anchorRestoreActive) return;
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
                          // Keep the live thinking tail expanded (reasoning
                          // followed by tool calls) while the turn streams, so
                          // the newest reasoning line stays visible. Once
                          // assistant prose starts, the turn ends, or history
                          // is opened cold, fold back to the summary row.
                          final liveThinkingTail =
                              ai.id == realTipId &&
                              _liveTurnActive(widget.liveChrome) &&
                              _endsWithThinking(ai);
                          final version = ai.role == AiRole.user
                              ? widget.branches.turnOf(ai.id)
                              : null;
                          final editing =
                              ai.role == AiRole.user &&
                              _edit.editingMessageId == ai.id;
                          final showsVersion =
                              version != null && version.count > 1;
                          final previous = version?.previous;
                          final next = version?.next;
                          final timestampText = formatChatTimestamp(
                            ai.createdAt,
                            locale: Localizations.localeOf(
                              context,
                            ).languageCode,
                          );
                          // A failed or stopped resend leaves one red retry at
                          // the left of the bubble, centred on it. The
                          // transaction itself is not rendered. The desktop
                          // inline editor keeps the draft, so it shows nothing.
                          final editOperation = _edit.operation;
                          final showEditRetry =
                              editOperation != null &&
                              editOperation.messageId == ai.id &&
                              editOperation.phase.allowsRetry &&
                              _edit.editingMessageId != ai.id;
                          // A new editing session for this message must build a
                          // fresh editor State: the old one latched itself as
                          // submitted and would ignore the retry. The operation
                          // id changes on every submit, including a retry.
                          final messageChild = AiMessageView(
                            key: ValueKey(
                              editing
                                  ? '${ai.id}:edit:${_edit.operation?.id}'
                                  : ai.id,
                            ),
                            message: ai,
                            userAttachmentWorkspaceRoot:
                                widget.userAttachmentWorkspaceRoot,
                            userAttachmentUsesPosixPaths:
                                widget.userAttachmentUsesPosixPaths,
                            onOpenUserImage: widget.onOpenUserImage,
                            timestampText: timestampText,
                            actionBarHoverEnabled: _hoverEffectsEnabled,
                            actionBarReveal:
                                deliveryFailed ||
                                    ai.id == lastId ||
                                    showsVersion
                                ? AiActionBarReveal.always
                                : AiActionBarReveal.hover,
                            onRetryDelivery:
                                deliveryFailed &&
                                    widget.onRetryFailedMessage != null
                                ? () => widget.onRetryFailedMessage!(ai.id)
                                : null,
                            chainOfThoughtAutoExpand:
                                liveThinkingTail &&
                                aiTheme.cotExpandLatestOnOpen,
                            onFork: version == null || widget.onForkFrom == null
                                ? null
                                : () => widget.onForkFrom!(version.commit),
                            forkLabel: forkLabel,
                            editing: !mobile && editing,
                            onEdit:
                                version == null ||
                                    widget.onEditUserMessage == null ||
                                    !_isPureText(ai)
                                ? null
                                : mobile
                                ? () => unawaited(_openMobileEdit(context, ai))
                                : () => _edit.openEditor(ai.id),
                            editLabel: editLabel,
                            onSubmitEdit: (text) => _submitEdit(
                              ai,
                              text,
                              reopenEditorOnFailure: true,
                            ),
                            onCancelEdit: _edit.cancelEditor,
                            onPickEditAttachments: widget.onPickEditAttachments,
                            editSendLabel: editSendLabel,
                            editCancelLabel: editCancelLabel,
                            editInitialText: _edit.editingMessageId == ai.id
                                ? _edit.draft
                                : null,
                            versionIndex: showsVersion ? version.index : null,
                            versionCount: showsVersion ? version.count : null,
                            onPreviousVersion:
                                showsVersion &&
                                    previous != null &&
                                    widget.onSwitchVersion != null
                                ? () => widget.onSwitchVersion!(previous)
                                : null,
                            onNextVersion:
                                showsVersion &&
                                    next != null &&
                                    widget.onSwitchVersion != null
                                ? () => widget.onSwitchVersion!(next)
                                : null,
                            previousVersionLabel: previousVersionLabel,
                            nextVersionLabel: nextVersionLabel,
                            rewindForkEnabled: !widget.turnInFlight,
                            leadingAction: showEditRetry
                                ? EditRetryButton(
                                    onRetry: () => unawaited(_edit.retry()),
                                  )
                                : null,
                          );
                          var result = tightenForRunning
                              ? Theme(
                                  data: _tightenedTipTheme(context, aiTheme),
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
                          final mobileEditingId = mobile
                              ? _edit.editingMessageId
                              : null;
                          if (mobileEditingId != null) {
                            if (mobileEditingId != ai.id) {
                              result = IgnorePointer(
                                key: ValueKey('chat-message-dim:${ai.id}'),
                                ignoring: true,
                                child: Opacity(opacity: 0.28, child: result),
                              );
                            }
                            return result;
                          }
                          if (!mobile) return result;

                          final canEdit =
                              ai.role == AiRole.user &&
                              _isPureText(ai) &&
                              version != null &&
                              widget.onEditUserMessage != null;
                          final handlers = ChatMessageActionHandlers(
                            onRetry:
                                deliveryFailed &&
                                    widget.onRetryFailedMessage != null
                                ? () => widget.onRetryFailedMessage!(ai.id)
                                : null,
                            onEdit: canEdit
                                ? () => unawaited(_openMobileEdit(context, ai))
                                : null,
                            onFork:
                                version != null && widget.onForkFrom != null
                                ? () => widget.onForkFrom!(version.commit)
                                : null,
                            onPreviousVersion:
                                showsVersion &&
                                    previous != null &&
                                    widget.onSwitchVersion != null
                                ? () => widget.onSwitchVersion!(previous)
                                : null,
                            onNextVersion:
                                showsVersion &&
                                    next != null &&
                                    widget.onSwitchVersion != null
                                ? () => widget.onSwitchVersion!(next)
                                : null,
                          );
                          result = SelectionContainer.disabled(
                            child: GestureDetector(
                              key: ValueKey('chat-message-gestures:${ai.id}'),
                              behavior: HitTestBehavior.translucent,
                              onLongPressStart: (details) {
                                unawaited(
                                  showChatMessageActionMenu(
                                    context,
                                    globalPosition: details.globalPosition,
                                    message: ai,
                                    deliveryFailed: deliveryFailed,
                                    showsVersion: showsVersion,
                                    rewindEnabled:
                                        AiMessageInteractionScope.maybeRewindEnabled(
                                          context,
                                        ) ??
                                        !widget.turnInFlight,
                                    handlers: handlers,
                                  ),
                                );
                              },
                              onTap: canEdit
                                  ? () => unawaited(_openMobileEdit(context, ai))
                                  : null,
                              child: result,
                            ),
                          );
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

    return AiMessageInteractionScope(
      rewindForkEnabled: !widget.turnInFlight,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Match the composer card: both the thread and the composer center a
          // column capped at [AiMessageTheme.threadMaxWidth] with the same
          // horizontal padding, so this inset lands on the input box's right
          // edge on wide windows instead of the window edge. Nudge it one
          // spacing step inward so it reads as floating over the card corner.
          final contentWidth = math.min(
            math.max(
              0.0,
              constraints.maxWidth - 2 * aiTheme.threadHorizontalPadding,
            ),
            aiTheme.threadMaxWidth,
          );
          final rightInset =
              (constraints.maxWidth - contentWidth) / 2 + context.tpSpacing.md;
          return Stack(
            fit: StackFit.expand,
            children: [
              thread,
              ValueListenableBuilder<bool>(
                valueListenable: _showScrollToBottom,
                builder: (context, visible, _) {
                  if (!visible) return const SizedBox.shrink();
                  return SessionHistoryScrollToBottomButton(
                    tooltip: context.l10n.ai.messageScrollToBottom,
                    showNewMessagesDot: _hasNewMessagesBelow,
                    onPressed: _animateScrollToBottom,
                    rightInset: rightInset,
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }
}
