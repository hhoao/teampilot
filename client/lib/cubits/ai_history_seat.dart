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
import '../services/session/session_history_pagination.dart';
import '../services/team_bus/persistence/bus_message_log.dart';
import '../utils/logging/logger.dart';

/// Host-local AI history status — not session connect / "starting…".
enum AiHistoryViewStatus { loading, ready, empty, error }

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
  ];
}

class _PendingUser {
  const _PendingUser({required this.id, required this.text});

  final String id;
  final String text;
}

class _StickyLocalUser {
  const _StickyLocalUser({required this.id, required this.text});

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

  int _loadGeneration = 0;

  /// Raw CLI transcript from [_loader.load], before merging mailbox mail.
  /// Drives the soft-reload empty-CLI guard independent of mailbox content.
  List<AiMessage> _cliMessages = const [];
  List<AiMessage> _allMessages = const [];
  int _visibleCount = 0;

  /// Prefix of [_allMessages] published to the thread. Trailing assistants may
  /// stay held while [awaitingAssistant] until idle or [tipHoldAfterAssistant].
  int _committedLength = 0;
  final List<_PendingUser> _pendingQueue = [];

  /// Mailbox (and similar) user turns that are not in the CLI transcript.
  /// Appended after the committed tip; survive softReload; cleared on seat change.
  final List<_StickyLocalUser> _stickyLocalUsers = [];
  Timer? _tipHoldTimer;

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
    _cliMessages = const [];
    _allMessages = const [];
    _visibleCount = 0;
    _committedLength = 0;
    runtime.setLoading();
    emit(
      AiHistoryState(
        status: AiHistoryViewStatus.loading,
        // Preserve turn chrome across soft→cold remounts of the same seat.
        awaitingAssistant: !seatChanged && state.awaitingAssistant,
        sessionId: session.sessionId,
        memberId: memberId,
      ),
    );

    try {
      final messages = await _loader.load(
        session: session,
        memberId: memberId,
        launchContext: launchContext,
        team: team,
        workingDirectory: workingDirectory,
        force: force,
      );
      if (gen != _loadGeneration || isClosed) return;
      _cliMessages = messages;
      final merged = await _mergeWithMailbox(
        messages,
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
      _cliMessages = const [];
      _allMessages = const [];
      _visibleCount = 0;
      _committedLength = 0;
      runtime.setError(e.toString());
      emit(
        AiHistoryState(
          status: AiHistoryViewStatus.error,
          errorMessage: e.toString(),
          sessionId: session.sessionId,
          memberId: memberId,
        ),
      );
    }
  }

  /// Live refresh: tip-Δ window, no loading flash when already ready.
  Future<void> softReload() async {
    final session = _lastSession;
    final memberId = _lastMemberId;
    final launchContext = _lastLaunchContext;
    if (session == null || memberId == null || launchContext == null) return;

    final gen = _loadGeneration;
    final sessionId = session.sessionId;

    try {
      _loader.invalidate(sessionId: sessionId, memberId: memberId);
      final messages = await _loader.load(
        session: session,
        memberId: memberId,
        launchContext: launchContext,
        team: _lastTeam,
        workingDirectory: _lastWorkingDirectory,
        force: true,
      );
      if (gen != _loadGeneration || isClosed) return;
      if (session.sessionId != (_lastSession?.sessionId ?? '') ||
          memberId != _lastMemberId) {
        return;
      }

      final mailboxRecords = await _safeLoadMailboxRecords(
        sessionId,
        memberId,
      );
      if (gen != _loadGeneration || isClosed) return;
      if (session.sessionId != (_lastSession?.sessionId ?? '') ||
          memberId != _lastMemberId) {
        return;
      }

      // Pre-locate: empty CLI parse keeps prior messages until a transcript
      // exists — unless the mailbox now has read user mail to merge in, in
      // which case applying keeps the timeline from going stale.
      if (messages.isEmpty && _cliMessages.isNotEmpty) {
        final hasReadMailboxUsers =
            partitionMailboxUserRecords(mailboxRecords).events.isNotEmpty;
        if (!hasReadMailboxUsers) return;
      }

      _cliMessages = messages;
      final merged = buildConversationTimeline(
        cliMessages: messages,
        mailboxRecords: mailboxRecords,
      ).messages;
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

  void enqueuePendingUser(String text) {
    if (isClosed) return;
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

  /// Append a local user bubble that is not backed by the CLI transcript.
  ///
  /// Used after a TeamBus mailbox mail is consumed: stays after the tip across
  /// soft reloads (FIFO). Does not latch [awaitingAssistant].
  void appendStickyLocalUser({required String id, required String text}) {
    if (isClosed) return;
    final trimmedId = id.trim();
    final trimmedText = text.trim();
    if (trimmedId.isEmpty || trimmedText.isEmpty) return;
    if (_stickyLocalUsers.any((s) => s.id == trimmedId)) return;
    _stickyLocalUsers.add(
      _StickyLocalUser(id: trimmedId, text: trimmedText),
    );
    _remergePendingsOntoRuntime();
    if (state.status == AiHistoryViewStatus.empty) {
      emit(state.copyWith(status: AiHistoryViewStatus.ready));
    } else if (state.status == AiHistoryViewStatus.ready) {
      // Remerge already published; no awaiting change.
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
    emit(state.copyWith(awaitingAssistant: false));
  }

  void setAwaitingAssistant(bool value) {
    if (isClosed) return;
    if (!value) {
      _cancelTipHoldTimer();
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
    final hadSticky = _stickyLocalUsers.isNotEmpty;
    if (_pendingQueue.isEmpty &&
        !hadSticky &&
        !state.awaitingAssistant &&
        !hasHeldAssistantTip) {
      return;
    }
    _pendingQueue.clear();
    _stickyLocalUsers.clear();
    _commitAll();
    if (state.status == AiHistoryViewStatus.ready ||
        state.status == AiHistoryViewStatus.empty) {
      _remergePendingsOntoRuntime();
    }
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
    _dropMatchedPendings();

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
    _dropMatchedPendings();

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

  /// Empty transcript with unmatched pendings/stickies stays on the thread path.
  void _emitEmptyOrPendingReady(String sessionId, String memberId) {
    if (_pendingQueue.isEmpty && _stickyLocalUsers.isEmpty) {
      runtime.setEmpty();
      emit(
        AiHistoryState(
          status: AiHistoryViewStatus.empty,
          sessionId: sessionId,
          memberId: memberId,
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
      ),
    );
  }

  void _dropMatchedPendings() {
    if (_pendingQueue.isEmpty) return;
    final n = math.max(_pendingQueue.length + 2, 5);
    final userTurns = [
      for (final m in _allMessages)
        if (m.role == AiRole.user) m,
    ];
    final tipUsers = userTurns.length <= n
        ? userTurns
        : userTurns.sublist(userTurns.length - n);
    final matched = List<bool>.filled(tipUsers.length, false);
    final remaining = <_PendingUser>[];

    for (final pending in _pendingQueue) {
      final norm = normalizeAiHistoryPendingText(pending.text);
      var matchIdx = -1;
      for (var i = tipUsers.length - 1; i >= 0; i--) {
        if (matched[i]) continue;
        final tipNorm = normalizeAiHistoryPendingText(
          aiHistoryUserPlainText(tipUsers[i]),
        );
        if (tipNorm == norm) {
          matchIdx = i;
          break;
        }
      }
      if (matchIdx >= 0) {
        matched[matchIdx] = true;
      } else {
        remaining.add(pending);
      }
    }
    _pendingQueue
      ..clear()
      ..addAll(remaining);
  }

  /// Soft reload must not clear this — a turn may flush many assistant messages.
  /// Host clears via [flushHeldTip] / [setAwaitingAssistant] when idle (or send fails).
  bool _computeAwaitingAssistant() {
    if (_pendingQueue.isNotEmpty) return true;
    return state.awaitingAssistant;
  }

  void _remergePendingsOntoRuntime() {
    final slice = _visibleSlice();
    final overlay = <AiMessage>[
      for (final s in _stickyLocalUsers)
        AiMessage(
          id: s.id,
          role: AiRole.user,
          parts: [AiTextPart(text: s.text)],
        ),
      for (final p in _pendingQueue)
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
      ),
    );
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
