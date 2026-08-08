import 'dart:async';
import 'dart:math' as math;

import 'package:ai_message_core/ai_message_core.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';

import '../models/app_session.dart';
import '../models/team_config.dart';
import '../models/workspace_launch_context.dart';
import '../services/conversation_timeline/conversation_timeline.dart';
import '../services/conversation_timeline/mailbox_user_source.dart';
import '../services/session/ai_history_loader.dart';
import '../services/session/ai_history_pending_text.dart';
import '../services/session/history_awaiting_working_sync.dart';
import '../services/session/session_history_pagination.dart';
import '../services/team_bus/persistence/bus_message_log.dart';
import '../utils/logging/logger.dart';

/// Host-local AI history status — not session connect / "starting…".
enum AiHistoryViewStatus {
  /// No content yet — first load of a seat. The only status that may render a
  /// full-pane loading view.
  loading,

  /// Content already cached; a background read-through is in flight. The list
  /// must NOT be blanked — the UI keeps the thread and shows a slim strip.
  refreshing,
  ready,
  empty,
  error,
}

class AiHistoryState extends Equatable {
  const AiHistoryState({
    this.status = AiHistoryViewStatus.empty,
    this.totalMessageCount = 0,
    this.hasOlder = false,
    this.isLoadingOlder = false,
    this.errorMessage,
    this.softReloadError,
    this.awaitingAssistant = false,
    this.sessionId,
    this.memberId,
    this.subagentAttachmentEpoch = 0,
  });

  final AiHistoryViewStatus status;
  final int totalMessageCount;
  final bool hasOlder;
  final bool isLoadingOlder;
  final String? errorMessage;
  final String? softReloadError;

  /// True from continue-send until the assistant turn settles (host clears on
  /// idle / send failure). SoftReload alone must not clear this — one turn may
  /// flush many assistant messages.
  final bool awaitingAssistant;
  final String? sessionId;
  final String? memberId;

  /// Bumped whenever [_subagentAttachments] is replaced so BlocBuilder rebuilds
  /// even when message count is unchanged.
  final int subagentAttachmentEpoch;

  AiHistoryState copyWith({
    AiHistoryViewStatus? status,
    int? totalMessageCount,
    bool? hasOlder,
    bool? isLoadingOlder,
    String? errorMessage,
    bool clearError = false,
    String? softReloadError,
    bool clearSoftReloadError = false,
    bool? awaitingAssistant,
    String? sessionId,
    String? memberId,
    int? subagentAttachmentEpoch,
  }) {
    return AiHistoryState(
      status: status ?? this.status,
      totalMessageCount: totalMessageCount ?? this.totalMessageCount,
      hasOlder: hasOlder ?? this.hasOlder,
      isLoadingOlder: isLoadingOlder ?? this.isLoadingOlder,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      softReloadError: clearSoftReloadError
          ? null
          : (softReloadError ?? this.softReloadError),
      awaitingAssistant: awaitingAssistant ?? this.awaitingAssistant,
      sessionId: sessionId ?? this.sessionId,
      memberId: memberId ?? this.memberId,
      subagentAttachmentEpoch:
          subagentAttachmentEpoch ?? this.subagentAttachmentEpoch,
    );
  }

  @override
  List<Object?> get props => [
    status,
    totalMessageCount,
    hasOlder,
    isLoadingOlder,
    errorMessage,
    softReloadError,
    awaitingAssistant,
    sessionId,
    memberId,
    subagentAttachmentEpoch,
  ];
}

class _PendingUser {
  const _PendingUser({required this.id, required this.text});

  final String id;
  final String text;
}

/// Per-seat History cubit: one [runtime] and tip/pending state per
/// `sessionId|shellMemberId`.
class AiHistorySeat extends Cubit<AiHistoryState> {
  AiHistorySeat({
    required AiHistoryLoader loader,
    void Function(String sessionId, String memberId)? onTranscriptApplied,
    Future<List<LoggedMessage>> Function(String sessionId, String memberId)?
    loadMailboxRecords,
  }) : _loader = loader,
       _onTranscriptApplied = onTranscriptApplied,
       _loadMailboxRecords = loadMailboxRecords,
       super(const AiHistoryState());

  static const _uuid = Uuid();

  /// Aligns with [TerminalActivityTracker.idleAfter], plus a small slack so the
  /// seat-idle falling edge usually wins the race and reveals the tip as Running
  /// clears — avoiding a flash of final text under a still-spinning indicator.
  static const tipHoldAfterAssistant = Duration(milliseconds: 2800);

  final AiHistoryLoader _loader;
  final void Function(String sessionId, String memberId)? _onTranscriptApplied;
  final Future<List<LoggedMessage>> Function(String sessionId, String memberId)?
  _loadMailboxRecords;
  final ExternalStoreAiThreadRuntime runtime = ExternalStoreAiThreadRuntime();

  /// Full loaded transcript, beyond the thread's visible pagination window
  /// ([runtime] only publishes the last `kSessionHistoryInitialTurns` turns).
  /// The CLI task board derives from this so TaskCreate calls earlier in a
  /// large session are not sliced away.
  List<AiMessage> get loadedMessages => _allMessages;

  int _loadGeneration = 0;

  /// Raw CLI transcript from [_loader.load], before merging mailbox mail.
  /// Drives the soft-reload empty-CLI guard independent of mailbox content.
  List<AiMessage> _cliMessages = const [];
  List<AiMessage> _allMessages = const [];
  int _visibleCount = 0;

  /// CLI user-turn count of the last applied snapshot. CLI user turns that
  /// newly appear past this baseline each confirm one outstanding optimistic
  /// send (FIFO). Mailbox turns are deliberately excluded: they come from the
  /// bus log, not from CLI-recorded sends, and mailbox sends roll back their
  /// pending explicitly (see [removePendingMatching]).
  int _lastUserTurnCount = 0;

  Map<String, AiSubagentAttachment> _subagentAttachments = {};
  int _subagentAttachmentEpoch = 0;

  /// Inflated Agent/Task toolCallId → attachment index for the last load.
  Map<String, AiSubagentAttachment> get subagentAttachments =>
      Map.unmodifiable(_subagentAttachments);

  /// Prefix of [_allMessages] published to the thread. Trailing assistants may
  /// stay held while [awaitingAssistant] until idle or [tipHoldAfterAssistant].
  int _committedLength = 0;
  final List<_PendingUser> _pendingQueue = [];
  Timer? _tipHoldTimer;

  /// Survives History remount / softReload — widget State must not own this.
  /// Latched true once we observe [workingSessionIds] while awaiting.
  var _sawWorkingWhileAwaiting = false;

  AppSession? _lastSession;
  String? _lastMemberId;
  TeamProfile? _lastTeam;
  String? _lastWorkingDirectory;
  WorkspaceLaunchContext? _lastLaunchContext;

  /// True when assistant tip is loaded but not yet shown.
  bool get hasHeldAssistantTip => _committedLength < _allMessages.length;

  Future<void> load({
    required AppSession session,
    required String memberId,
    required WorkspaceLaunchContext launchContext,
    TeamProfile? team,
    String? workingDirectory,
    bool force = false,
  }) async {
    final seatChanged =
        state.sessionId != session.sessionId || state.memberId != memberId;
    // No-blank invariant: only a seat change or an empty list may clear the
    // transcript. A re-load of content that already exists refreshes in place
    // (refreshing) so the UI never blanks a conversation it is switching to.
    final hadContent = _allMessages.isNotEmpty;
    final isRefresh = !seatChanged && hadContent;
    if (seatChanged) {
      clearPendings();
    }

    _lastSession = session;
    _lastMemberId = memberId;
    _lastTeam = team;
    _lastWorkingDirectory = workingDirectory;
    _lastLaunchContext = launchContext;

    final gen = ++_loadGeneration;
    _cancelTipHoldTimer();
    if (isRefresh) {
      // Keep the cached transcript and thread runtime; background read-through
      // patches the list in place. Never call runtime.setLoading() here.
      emit(
        AiHistoryState(
          status: AiHistoryViewStatus.refreshing,
          awaitingAssistant: state.awaitingAssistant,
          sessionId: session.sessionId,
          memberId: memberId,
          totalMessageCount: state.totalMessageCount,
          hasOlder: state.hasOlder,
          subagentAttachmentEpoch: _subagentAttachmentEpoch,
        ),
      );
    } else {
      _cliMessages = const [];
      _allMessages = const [];
      _visibleCount = 0;
      _committedLength = 0;
      _lastUserTurnCount = 0;
      _clearSubagentAttachments();
      runtime.setLoading();
      emit(
        AiHistoryState(
          status: AiHistoryViewStatus.loading,
          // Preserve turn chrome across soft→cold remounts of the same seat.
          awaitingAssistant: !seatChanged && state.awaitingAssistant,
          sessionId: session.sessionId,
          memberId: memberId,
          subagentAttachmentEpoch: _subagentAttachmentEpoch,
        ),
      );
    }

    try {
      final result = await _loader.load(
        session: session,
        memberId: memberId,
        launchContext: launchContext,
        team: team,
        workingDirectory: workingDirectory,
        force: force,
      );
      if (gen != _loadGeneration || isClosed) return;
      _cliMessages = result.messages;
      _setSubagentAttachments(result.subagentAttachments);
      final merged = await _mergeWithMailbox(
        result.messages,
        session.sessionId,
        memberId,
      );
      if (gen != _loadGeneration || isClosed) return;
      _applyMessages(merged, session.sessionId, memberId);
    } catch (e, st) {
      appLogger.e(
        '[ai-history] seat load failed session=${session.sessionId} '
        'member=$memberId team=${team?.id ?? session.sessionTeam}: $e',
        error: e,
        stackTrace: st,
      );
      if (gen != _loadGeneration || isClosed) return;
      if (isRefresh) {
        // Refresh failure keeps the cached content; the UI maps
        // error-with-content to the thread plus a non-blocking strip.
        emit(
          AiHistoryState(
            status: AiHistoryViewStatus.error,
            errorMessage: e.toString(),
            sessionId: session.sessionId,
            memberId: memberId,
            totalMessageCount: _allMessages.length,
            subagentAttachmentEpoch: _subagentAttachmentEpoch,
          ),
        );
        return;
      }
      _cliMessages = const [];
      _allMessages = const [];
      _visibleCount = 0;
      _committedLength = 0;
      _clearSubagentAttachments();
      runtime.setError(e.toString());
      emit(
        AiHistoryState(
          status: AiHistoryViewStatus.error,
          errorMessage: e.toString(),
          sessionId: session.sessionId,
          memberId: memberId,
          subagentAttachmentEpoch: _subagentAttachmentEpoch,
        ),
      );
    }
  }

  /// Live refresh: tip-Δ window, no loading flash when already ready.
  ///
  /// Reuses [AiHistoryLoader] token cache (`force: false`) so unchanged
  /// transcripts skip locate/parse. Mailbox is still refreshed every call.
  Future<void> softReload() async {
    final session = _lastSession;
    final memberId = _lastMemberId;
    final launchContext = _lastLaunchContext;
    if (session == null || memberId == null || launchContext == null) return;

    final gen = _loadGeneration;
    final sessionId = session.sessionId;

    try {
      final result = await _loader.load(
        session: session,
        memberId: memberId,
        launchContext: launchContext,
        team: _lastTeam,
        workingDirectory: _lastWorkingDirectory,
      );
      if (gen != _loadGeneration || isClosed) return;
      if (session.sessionId != (_lastSession?.sessionId ?? '') ||
          memberId != _lastMemberId) {
        return;
      }

      final messages = result.messages;
      final mailboxRecords = await _safeLoadMailboxRecords(
        sessionId,
        memberId,
      );
      if (gen != _loadGeneration || isClosed) return;
      if (session.sessionId != (_lastSession?.sessionId ?? '') ||
          memberId != _lastMemberId) {
        return;
      }

      // Pre-locate: a transient empty CLI parse must never wipe an already
      // -loaded transcript. If the mailbox has no *new* read user mail either,
      // keep the prior view entirely (old empty-CLI protection). If it does,
      // merge that new mail onto the **prior** CLI transcript ([_cliMessages])
      // instead of the empty parse — an empty parse is never treated as
      // "CLI cleared". Keep prior [_subagentAttachments] / epoch in both cases.
      if (messages.isEmpty && _cliMessages.isNotEmpty) {
        final mailboxEvents = partitionMailboxUserRecords(
          mailboxRecords,
        ).events;
        final existingIds = {for (final m in _allMessages) m.id};
        final hasNewReadMailboxUsers = mailboxEvents.any(
          (e) => !existingIds.contains(e.id),
        );
        if (!hasNewReadMailboxUsers) return;

        final merged = buildConversationTimeline(
          cliMessages: _cliMessages,
          mailboxRecords: mailboxRecords,
        ).messages;
        _applySoftReloadMessages(merged, sessionId, memberId);
        return;
      }

      final cliUnchanged = sameMessageListContent(_cliMessages, messages);
      if (!cliUnchanged) {
        _cliMessages = messages;
      }
      _setSubagentAttachments(result.subagentAttachments);
      final merged = buildConversationTimeline(
        cliMessages: _cliMessages,
        mailboxRecords: mailboxRecords,
      ).messages;
      if (cliUnchanged && sameMessageListContent(_allMessages, merged)) {
        return;
      }
      _applySoftReloadMessages(merged, sessionId, memberId);
    } catch (e, st) {
      appLogger.e(
        '[ai-history] seat softReload failed session=$sessionId '
        'member=$memberId: $e',
        error: e,
        stackTrace: st,
      );
      if (gen != _loadGeneration || isClosed) return;
      emit(state.copyWith(softReloadError: e.toString()));
    }
  }

  /// Re-merges [_cliMessages] with freshly loaded mailbox records — used
  /// after a Queued mail is consumed. Unlike [softReload], the CLI transcript
  /// itself is never re-parsed here; only the mailbox side of the merge is
  /// refreshed, so a newly-read mail can be promoted without waiting for (or
  /// forcing) a CLI reload.
  Future<void> refreshMailboxTimeline() async {
    final session = _lastSession;
    final memberId = _lastMemberId;
    if (session == null || memberId == null) return;

    final gen = _loadGeneration;
    final sessionId = session.sessionId;

    try {
      final mailboxRecords = await _safeLoadMailboxRecords(
        sessionId,
        memberId,
      );
      if (gen != _loadGeneration || isClosed) return;
      if (session.sessionId != (_lastSession?.sessionId ?? '') ||
          memberId != _lastMemberId) {
        return;
      }

      final merged = buildConversationTimeline(
        cliMessages: _cliMessages,
        mailboxRecords: mailboxRecords,
      ).messages;
      _applySoftReloadMessages(merged, sessionId, memberId);
    } catch (e, st) {
      appLogger.e(
        '[ai-history] seat refreshMailboxTimeline failed session=$sessionId '
        'member=$memberId: $e',
        error: e,
        stackTrace: st,
      );
      if (gen != _loadGeneration || isClosed) return;
      emit(state.copyWith(softReloadError: e.toString()));
    }
  }

  /// Review remount: soft when already ready for this seat, else cold load.
  Future<void> softReloadOrLoad({
    required AppSession session,
    required String memberId,
    required WorkspaceLaunchContext launchContext,
    TeamProfile? team,
    String? workingDirectory,
  }) async {
    if (state.status == AiHistoryViewStatus.ready &&
        state.sessionId == session.sessionId &&
        state.memberId == memberId) {
      await softReload();
      return;
    }
    await load(
      session: session,
      memberId: memberId,
      launchContext: launchContext,
      team: team,
      workingDirectory: workingDirectory,
    );
  }

  /// Unmatched optimistic user bubbles still overlaid on the transcript.
  bool get hasOptimisticPending => _pendingQueue.isNotEmpty;

  /// Rising-edge latch for sidebar working while a History turn is awaiting.
  bool get sawWorkingWhileAwaiting => _sawWorkingWhileAwaiting;

  /// Apply working/connect edges to awaiting + latch.
  ///
  /// Returns the action so the host can schedule/cancel idle grace (Timer is
  /// owned by the Chat view lifecycle). Latch lives here so remount keeps it.
  HistoryAwaitingWorkingAction applyWorkingSessionSync({
    required bool sessionWorking,
    bool sessionConnecting = false,
    bool memberRunning = true,
  }) {
    if (isClosed) return HistoryAwaitingWorkingAction.none;
    final action = resolveHistoryAwaitingWorkingAction(
      awaitingAssistant: state.awaitingAssistant,
      sessionWorking: sessionWorking,
      sawWorkingWhileAwaiting: _sawWorkingWhileAwaiting,
      sessionConnecting: sessionConnecting,
      memberRunning: memberRunning,
    );
    switch (action) {
      case HistoryAwaitingWorkingAction.none:
      case HistoryAwaitingWorkingAction.scheduleGraceClear:
      case HistoryAwaitingWorkingAction.deferWhileStarting:
        break;
      case HistoryAwaitingWorkingAction.resetLatch:
        _sawWorkingWhileAwaiting = false;
        break;
      case HistoryAwaitingWorkingAction.latchWorking:
        _sawWorkingWhileAwaiting = true;
        break;
      case HistoryAwaitingWorkingAction.clearAwaiting:
        flushHeldTip(endAwaiting: true);
        break;
    }
    return action;
  }

  void enqueuePendingUser(String text) {
    if (isClosed) return;
    // New user turn — need a fresh rising edge of working.
    _sawWorkingWhileAwaiting = false;
    final pending = _PendingUser(id: 'pending:${_uuid.v4()}', text: text);
    _pendingQueue.add(pending);
    _remergePendingsOntoRuntime();
    // Empty / loading: promote to ready so History shows the pending bubble
    // instead of the empty / spinner pane (runtime already has the tip message).
    if (state.status == AiHistoryViewStatus.empty ||
        state.status == AiHistoryViewStatus.loading) {
      emit(
        state.copyWith(
          status: AiHistoryViewStatus.ready,
          awaitingAssistant: true,
        ),
      );
    } else {
      emit(state.copyWith(awaitingAssistant: true));
    }
  }

  /// Rolls back an optimistic pending when connect/inject fails.
  void removePendingMatching(String text) {
    if (isClosed) return;
    final target = normalizeAiHistoryPendingText(text);
    final before = _pendingQueue.length;
    _pendingQueue.removeWhere(
      (p) => normalizeAiHistoryPendingText(p.text) == target,
    );
    if (_pendingQueue.length == before && state.awaitingAssistant == false) {
      return;
    }
    _cancelTipHoldTimer();
    _commitAll();
    _remergePendingsOntoRuntime();
    _sawWorkingWhileAwaiting = false;
    emit(state.copyWith(awaitingAssistant: false));
  }

  void setAwaitingAssistant(bool value) {
    if (isClosed) return;
    if (!value) {
      _cancelTipHoldTimer();
      _sawWorkingWhileAwaiting = false;
      if (hasHeldAssistantTip) {
        _commitAll();
        _remergePendingsOntoRuntime();
      }
    }
    if (state.awaitingAssistant == value &&
        state.totalMessageCount == _committedLength) {
      return;
    }
    emit(
      state.copyWith(
        awaitingAssistant: value,
        totalMessageCount: _committedLength,
        hasOlder: _hasOlder(),
      ),
    );
  }

  /// Publish any held assistant tip. When [endAwaiting] is true (seat idle),
  /// also clear Running chrome so the final tip and spinner settle together.
  void flushHeldTip({bool endAwaiting = false}) {
    if (isClosed) return;
    _cancelTipHoldTimer();
    final hadHeld = hasHeldAssistantTip;
    if (hadHeld) _commitAll();

    if (endAwaiting) {
      if (!hadHeld && !state.awaitingAssistant) return;
      if (state.status == AiHistoryViewStatus.ready ||
          state.status == AiHistoryViewStatus.empty) {
        _remergePendingsOntoRuntime();
      }
      _sawWorkingWhileAwaiting = false;
      emit(
        state.copyWith(
          awaitingAssistant: false,
          totalMessageCount: _committedLength,
          hasOlder: _hasOlder(),
          isLoadingOlder: false,
        ),
      );
      return;
    }

    if (hadHeld) {
      _emitReadyWindow(state.sessionId, state.memberId);
    }
  }

  void clearPendings() {
    if (isClosed) return;
    _cancelTipHoldTimer();
    if (_pendingQueue.isEmpty &&
        !state.awaitingAssistant &&
        !hasHeldAssistantTip &&
        !_sawWorkingWhileAwaiting) {
      return;
    }
    _pendingQueue.clear();
    _commitAll();
    if (state.status == AiHistoryViewStatus.ready ||
        state.status == AiHistoryViewStatus.empty) {
      _remergePendingsOntoRuntime();
    }
    _sawWorkingWhileAwaiting = false;
    if (state.awaitingAssistant) {
      emit(state.copyWith(awaitingAssistant: false));
    }
  }

  /// Drop cache for [sessionId] and force-reload if this seat last loaded it.
  Future<void> invalidateAndReload(String sessionId) async {
    _loader.invalidate(sessionId: sessionId);
    final session = _lastSession;
    final memberId = _lastMemberId;
    final launchContext = _lastLaunchContext;
    if (session == null || memberId == null || launchContext == null) return;
    if (session.sessionId != sessionId) return;
    await load(
      session: session,
      memberId: memberId,
      launchContext: launchContext,
      team: _lastTeam,
      workingDirectory: _lastWorkingDirectory,
      force: true,
    );
  }

  void loadOlder() {
    if (state.status != AiHistoryViewStatus.ready) return;
    if (!state.hasOlder || state.isLoadingOlder) return;

    emit(state.copyWith(isLoadingOlder: true));
    _visibleCount = math.min(
      _visibleCount + kSessionHistoryOlderPageSize,
      _committedLength,
    );
    _emitReadyWindow(state.sessionId, state.memberId);
  }

  /// Expands the committed + visible render window so the message at [index]
  /// (0-based into the full loaded transcript) is rendered. No-op when already
  /// visible or out of range. Used by chat find to jump to a match without
  /// iterating `loadOlder` (the full transcript is already in memory).
  void revealMessage(int index) {
    if (isClosed) return;
    if (index < 0 || index >= _allMessages.length) return;
    _commitAll();
    final need = _allMessages.length - index;
    if (_visibleCount >= need) return;
    _visibleCount = need;
    _emitReadyWindow(state.sessionId, state.memberId);
  }

  /// Merges [cliMessages] with read mailbox user mail for [sessionId] /
  /// [memberId]. Mailbox load failures degrade to CLI-only (logged, not thrown)
  /// so a mailbox hiccup never blocks history from loading.
  Future<List<AiMessage>> _mergeWithMailbox(
    List<AiMessage> cliMessages,
    String sessionId,
    String memberId,
  ) async {
    final mailboxRecords = await _safeLoadMailboxRecords(sessionId, memberId);
    return buildConversationTimeline(
      cliMessages: cliMessages,
      mailboxRecords: mailboxRecords,
    ).messages;
  }

  Future<List<LoggedMessage>> _safeLoadMailboxRecords(
    String sessionId,
    String memberId,
  ) async {
    final loadMailboxRecords = _loadMailboxRecords;
    if (loadMailboxRecords == null) return const [];
    try {
      return await loadMailboxRecords(sessionId, memberId);
    } catch (e, st) {
      appLogger.w(
        '[ai-history] mailbox load failed session=$sessionId '
        'member=$memberId: $e',
        error: e,
        stackTrace: st,
      );
      return const [];
    }
  }

  void _applyMessages(
    List<AiMessage> messages,
    String sessionId,
    String memberId,
  ) {
    _cancelTipHoldTimer();
    _allMessages = messages;
    _committedLength = _allMessages.length;
    _visibleCount = math.min(kSessionHistoryInitialTurns, _committedLength);
    _reconcilePendings();

    if (_allMessages.isEmpty) {
      _emitEmptyOrPendingReady(sessionId, memberId);
      _onTranscriptApplied?.call(sessionId, memberId);
      return;
    }

    _emitReadyWindow(sessionId, memberId);
    _onTranscriptApplied?.call(sessionId, memberId);
  }

  void _applySoftReloadMessages(
    List<AiMessage> messages,
    String sessionId,
    String memberId,
  ) {
    if (sameMessageListContent(_allMessages, messages)) {
      // Tip-identical: runtime already has these identities; skip emit fan-out.
      return;
    }
    final oldLength = _allMessages.length;
    final oldVisible = _visibleCount;
    final oldCommitted = _committedLength;
    final newLength = messages.length;
    _allMessages = messages;
    final tipDelta = math.max(0, newLength - oldLength);
    if (newLength < oldLength) {
      _visibleCount = math.min(oldVisible, newLength);
      _committedLength = math.min(oldCommitted, newLength);
    } else {
      _visibleCount = math.min(newLength, oldVisible + tipDelta);
    }
    _reconcilePendings();

    if (_allMessages.isEmpty) {
      _cancelTipHoldTimer();
      _committedLength = 0;
      _emitEmptyOrPendingReady(sessionId, memberId);
      _onTranscriptApplied?.call(sessionId, memberId);
      return;
    }

    if (!state.awaitingAssistant && _pendingQueue.isEmpty) {
      _cancelTipHoldTimer();
      _committedLength = _allMessages.length;
    } else {
      _committedLength = _commitThroughLatestUser(
        math.min(oldCommitted, _allMessages.length),
      );
      if (hasHeldAssistantTip) {
        _scheduleTipHoldFlush();
      } else {
        _cancelTipHoldTimer();
      }
    }

    _emitReadyWindow(sessionId, memberId);
    _onTranscriptApplied?.call(sessionId, memberId);
  }

  /// Publish transcript through the latest user turn; leave trailing non-user
  /// tip held while the seat is still awaiting.
  int _commitThroughLatestUser(int from) {
    var committed = from.clamp(0, _allMessages.length);
    for (var i = committed; i < _allMessages.length; i++) {
      if (_allMessages[i].role == AiRole.user) {
        committed = i + 1;
      } else {
        break;
      }
    }
    return committed;
  }

  void _commitAll() {
    _committedLength = _allMessages.length;
  }

  void _cancelTipHoldTimer() {
    _tipHoldTimer?.cancel();
    _tipHoldTimer = null;
  }

  void _scheduleTipHoldFlush() {
    _cancelTipHoldTimer();
    if (!hasHeldAssistantTip) return;
    _tipHoldTimer = Timer(tipHoldAfterAssistant, () {
      if (isClosed) return;
      // Still in turn: reveal held tip but keep Running.
      flushHeldTip(endAwaiting: false);
    });
  }

  /// Empty transcript with unmatched pendings stays on the thread path.
  void _emitEmptyOrPendingReady(String sessionId, String memberId) {
    if (_pendingQueue.isEmpty) {
      runtime.setEmpty();
      emit(
        AiHistoryState(
          status: AiHistoryViewStatus.empty,
          sessionId: sessionId,
          memberId: memberId,
          subagentAttachmentEpoch: _subagentAttachmentEpoch,
        ),
      );
      return;
    }
    _remergePendingsOntoRuntime();
    emit(
      AiHistoryState(
        status: AiHistoryViewStatus.ready,
        awaitingAssistant: _computeAwaitingAssistant(),
        sessionId: sessionId,
        memberId: memberId,
        subagentAttachmentEpoch: _subagentAttachmentEpoch,
      ),
    );
  }

  /// Confirms optimistic sends by the count of CLI user turns that newly
  /// appeared since the last applied snapshot, oldest pending first (FIFO).
  ///
  /// The CLI transcript is ground truth: every recorded user turn corresponds
  /// to one sent message, in order. The pending text is deliberately not
  /// compared — a CLI may rewrite what the user typed (a slash command expands
  /// into `<command-message>/<command-name>/<command-args>` markup), so only
  /// the turn count is meaningful. Counts [_cliMessages] (not the merged
  /// timeline) so bus-log mailbox turns never consume a PTY send's pending.
  void _reconcilePendings() {
    final userTurns = [
      for (final m in _cliMessages)
        if (m.role == AiRole.user) m,
    ];
    final appeared = math.max(0, userTurns.length - _lastUserTurnCount);
    final drop = math.min(appeared, _pendingQueue.length);
    if (drop > 0) {
      _pendingQueue.removeRange(0, drop);
    }
    _lastUserTurnCount = userTurns.length;
  }

  /// Soft reload must not clear this — a turn may flush many assistant messages.
  /// Host clears via [flushHeldTip] / [setAwaitingAssistant] when idle (or send fails).
  ///
  /// Do **not** force `true` from leftover optimistic pendings: after the seat
  /// goes idle (sidebar working cleared), unmatched pendings may linger until
  /// the transcript catches up; softReload must not revive Running chrome.
  bool _computeAwaitingAssistant() => state.awaitingAssistant;

  void _remergePendingsOntoRuntime() {
    final slice = _visibleSlice();
    final sliceIds = {for (final m in slice) m.id};
    final overlay = <AiMessage>[
      for (final p in _pendingQueue)
        if (!sliceIds.contains(p.id))
          AiMessage(
            id: p.id,
            role: AiRole.user,
            parts: [AiTextPart(text: p.text)],
          ),
    ];
    if (slice.isEmpty && overlay.isEmpty) {
      if (_allMessages.isEmpty) {
        runtime.setEmpty();
      }
      return;
    }
    // Always publish — callers invoke this when the window should be on the
    // runtime. [ExternalStoreAiThreadRuntime.setMessages] no-ops notify when
    // content is unchanged, so redundant publishes are cheap.
    runtime.setMessages([...slice, ...overlay]);
  }

  void _emitReadyWindow(String? sessionId, String? memberId) {
    _remergePendingsOntoRuntime();
    emit(
      AiHistoryState(
        status: AiHistoryViewStatus.ready,
        totalMessageCount: _committedLength,
        hasOlder: _hasOlder(),
        isLoadingOlder: false,
        softReloadError: state.softReloadError,
        awaitingAssistant: _computeAwaitingAssistant(),
        sessionId: sessionId,
        memberId: memberId,
        subagentAttachmentEpoch: _subagentAttachmentEpoch,
      ),
    );
  }

  void _setSubagentAttachments(Map<String, AiSubagentAttachment> next) {
    if (_sameSubagentAttachments(_subagentAttachments, next)) return;
    _subagentAttachments = Map<String, AiSubagentAttachment>.of(next);
    _subagentAttachmentEpoch++;
  }

  static bool _sameSubagentAttachments(
    Map<String, AiSubagentAttachment> a,
    Map<String, AiSubagentAttachment> b,
  ) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      final other = b[entry.key];
      if (other == null) return false;
      if (entry.value.toolCallId != other.toolCallId ||
          entry.value.source != other.source ||
          entry.value.title != other.title ||
          entry.value.sidePath != other.sidePath) {
        return false;
      }
      if (!sameMessageListContent(entry.value.messages, other.messages)) {
        return false;
      }
    }
    return true;
  }

  void _clearSubagentAttachments() {
    _subagentAttachments = {};
    _subagentAttachmentEpoch++;
  }

  List<AiMessage> _visibleSlice() {
    if (_committedLength <= 0 || _allMessages.isEmpty) return const [];
    final committed = _committedLength >= _allMessages.length
        ? _allMessages
        : _allMessages.sublist(0, _committedLength);
    final count = math.min(_visibleCount, committed.length);
    final start = math.max(0, committed.length - count);
    return committed.sublist(start);
  }

  bool _hasOlder() => _visibleCount < _committedLength;

  @override
  Future<void> close() {
    _cancelTipHoldTimer();
    runtime.close();
    return super.close();
  }
}
