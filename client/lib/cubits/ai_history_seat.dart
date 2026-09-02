import 'dart:async';
import 'dart:math' as math;

import 'package:ai_message_core/ai_message_core.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';

import '../models/app_session.dart';
import '../models/failed_message_record.dart';
import '../models/team_config.dart';
import '../models/workspace_launch_context.dart';
import '../services/conversation_timeline/conversation_timeline.dart';
import '../services/conversation_timeline/mailbox_user_source.dart';
import '../services/conversation_timeline/timeline_models.dart';
import '../services/session/ai_history_load_result.dart';
import '../services/session/ai_history_loader.dart';
import '../services/session/ai_history_message_dedup.dart';
import '../services/session/ai_history_page.dart';
import '../services/session/ai_history_pending_confirm.dart';
import '../services/session/ai_history_pending_text.dart';
import '../services/session/failed_message_store.dart';
import '../services/session/history_awaiting_working_sync.dart';
import '../services/session/session_history_pagination.dart';
import '../services/session/subagent_attachment_inflater.dart';
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
  const _PendingUser({
    required this.id,
    required this.text,
    this.deliveryStatus,
  });

  final String id;
  final String text;
  final FailedMessageStatus? deliveryStatus;
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
  AiHistoryCursor? _pageCursor;
  var _sourceHasOlder = false;

  /// CLI identity of the last successful [load] / [softReload]. [softReload]
  /// also refreshes it so a failed cold load (which never reaches the success
  /// path) or a seat switch is recovered by the next live refresh;
  /// [refreshMailboxTimeline] reuses this value without re-resolving.
  CliTool? _lastCli;

  /// Mailbox records of the last applied snapshot. The bus log is append-only
  /// per member, so a per-record `seq` + `read` scan is a cheap fingerprint —
  /// it lets [softReload] skip the whole merge + window path when neither the
  /// CLI transcript nor the mailbox moved.
  List<LoggedMessage>? _lastMailboxRecords;

  /// Cached merged timeline for identity-preserving incremental refresh.
  SeatTimelineSnapshot? _cachedTimeline;

  /// 最近一次去重日志的指纹（session|member|action|ids|kept 数），
  /// 相同指纹不重复打日志（防刷屏）。按 action 独立：deduped 与 kept-both
  /// 互不抑制。
  String? _lastDedupeLogFingerprint;
  String? _lastKeptBothLogFingerprint;

  /// Applied timeline fingerprint. Any newly appeared user or CLI message
  /// (id sequence or tip content) drops the single optimistic pending.
  /// Mailbox turns count because they land in [_allMessages]. Prepends
  /// (loadOlder / fullIndex) refresh this snapshot without clearing.
  List<String> _lastAppliedIds = const [];
  String? _lastAppliedTipContent;
  var _appliedSnapshotSeen = false;

  Map<String, AiSubagentAttachment> _subagentAttachments = {};
  int _subagentAttachmentEpoch = 0;

  /// Inflated Agent/Task toolCallId → attachment index for the last load.
  Map<String, AiSubagentAttachment> get subagentAttachments =>
      Map.unmodifiable(_subagentAttachments);

  /// Lazy-loads one subagent attachment and updates the seat cache + epoch.
  ///
  /// When [force] is true, bypasses the seat cache and re-resolves. A failed
  /// or degraded side resolve keeps the previous materialized preview.
  Future<AiSubagentAttachment?> loadSubagentAttachment(
    String toolCallId, {
    bool force = false,
  }) async {
    final session = _lastSession;
    final memberId = _lastMemberId;
    final launchContext = _lastLaunchContext;
    if (session == null || memberId == null || launchContext == null) {
      return null;
    }
    final id = toolCallId.trim();
    if (id.isEmpty) return null;
    final cached = _subagentAttachments[id];
    if (!force && cached != null) return cached;

    final attachment = await _loader.loadSubagentAttachmentForSeat(
      session: session,
      memberId: memberId,
      launchContext: launchContext,
      toolCallId: id,
      messages: _cliMessages,
      team: _lastTeam,
      workingDirectory: _lastWorkingDirectory,
    );
    if (isClosed) return attachment ?? cached;
    final kept = _keepPriorSubagentAttachment(
      cached: cached,
      next: attachment,
      force: force,
    );
    if (kept != null) {
      await _loader.seedSubagentAttachmentForSeat(
        session: session,
        memberId: memberId,
        launchContext: launchContext,
        toolCallId: id,
        attachment: kept,
        team: _lastTeam,
        workingDirectory: _lastWorkingDirectory,
      );
      return kept;
    }
    if (attachment == null) return null;

    final next = Map<String, AiSubagentAttachment>.of(_subagentAttachments)
      ..[id] = attachment;
    SubagentAttachmentInflater.addWorkflowChildren(attachment, next);
    _setSubagentAttachments(next);
    if (state.status == AiHistoryViewStatus.ready ||
        state.status == AiHistoryViewStatus.empty) {
      emit(
        state.copyWith(subagentAttachmentEpoch: _subagentAttachmentEpoch),
      );
    }
    return attachment;
  }

  /// On forced refresh, keep the last side-transcript preview when resolve
  /// fails (null) or degrades to a tool-result stub.
  static AiSubagentAttachment? _keepPriorSubagentAttachment({
    required AiSubagentAttachment? cached,
    required AiSubagentAttachment? next,
    required bool force,
  }) {
    if (!force || cached == null) return null;
    if (next == null) return cached;
    if (cached.source == AiSubagentAttachmentSource.sideTranscript &&
        next.source != AiSubagentAttachmentSource.sideTranscript) {
      return cached;
    }
    return null;
  }

  /// Prefix of [_allMessages] published to the thread. Trailing assistants may
  /// stay held while [awaitingAssistant] until idle or [tipHoldAfterAssistant].
  int _committedLength = 0;
  final List<_PendingUser> _pendingQueue = [];
  FailedMessageStore? _failedMessageStore;
  String? _failedMessageWorkspaceId;
  String? _failedMessageSessionId;
  Timer? _tipHoldTimer;

  /// Survives History remount / softReload — widget State must not own this.
  /// Latched true once we observe [busySessionIds] while awaiting.
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
      _pageCursor = null;
      _sourceHasOlder = false;
      _lastAppliedIds = const [];
      _lastAppliedTipContent = null;
      _appliedSnapshotSeen = false;
      _cachedTimeline = null;
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

    final loadSw = Stopwatch()..start();
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
      final loaderMs = loadSw.elapsedMilliseconds;
      _cliMessages = result.messages;
      _lastCli = result.cli;
      _pageCursor = result.cursor;
      _sourceHasOlder = result.hasOlder;
      if (result.subagentAttachments.isNotEmpty) {
        _setSubagentAttachments(result.subagentAttachments);
      } else if (result.subagentSideIndexDirty &&
          _subagentAttachments.isNotEmpty) {
        await _refreshMaterializedSubagentAttachments();
      } else if (!isRefresh) {
        // Cold load already cleared seat attachments; apply the empty map.
        _setSubagentAttachments(result.subagentAttachments);
      }
      // Refresh + empty + !dirty → preserve seat-owned lazy materializations.
      final merged = await _mergeWithMailbox(
        result.messages,
        session.sessionId,
        memberId,
      );
      if (gen != _loadGeneration || isClosed) return;
      _applyMessages(merged, session.sessionId, memberId);
      if (kDebugMode && !isRefresh) {
        appLogger.i(
          '[ai-history-timing] seat cold-load '
          'session=${session.sessionId} member=$memberId '
          'cli=${result.cli.name} msgs=${result.messages.length} '
          'complete=${result.isComplete} hasOlder=${result.hasOlder} '
          'loaderMs=$loaderMs totalMs=${loadSw.elapsedMilliseconds}',
        );
      }
      if (!result.isComplete) {
        unawaited(_hydrateFullIndex(gen, session.sessionId, memberId));
      }
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
      _pageCursor = null;
      _sourceHasOlder = false;
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
  ///
  /// [force] skips the mtime token cache. It does **not** re-parse the whole
  /// JSONL; a warm tail cursor stays incremental.
  Future<void> softReload({bool force = false}) async {
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
        force: force,
      );
      if (gen != _loadGeneration || isClosed) return;
      if (session.sessionId != (_lastSession?.sessionId ?? '') ||
          memberId != _lastMemberId) {
        return;
      }

      _lastCli = result.cli;

      final messages = result.messages;
      final mailboxRecords = await _safeLoadMailboxRecords(sessionId, memberId);
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
        _lastMailboxRecords = mailboxRecords;
        if (!hasNewReadMailboxUsers) return;

        final cached = buildConversationTimelineIncremental(
          previous: _cachedTimeline,
          cliMessages: _cliMessages,
          mailboxRecords: mailboxRecords,
        );
        _cachedTimeline = cached;
        _applySoftReloadMessages(cached.snapshot.messages, sessionId, memberId);
        return;
      }

      // The loader returns the same list instance from its token cache when
      // the transcript mtime is unchanged, so an instance comparison is a
      // zero-cost "CLI unchanged" test (the previous full-content identity scan
      // string-built every message — including every tool result — on the UI
      // isolate on each live refresh). After page-first hydrate, the cache may
      // still hand back the shorter recent page; treating that suffix as
      // unchanged keeps the longer full index for find / task-board consumers.
      // Subagent attachments are lazy: an empty map means "no update" unless
      // [AiHistoryLoadResult.subagentSideIndexDirty] asks for a refresh.
      final cliUnchanged =
          identical(messages, _cliMessages) || _isHydratedIndexSuffix(messages);
      final attachmentsUnchanged = result.subagentSideIndexDirty
          ? false
          : result.subagentAttachments.isEmpty ||
                identical(result.subagentAttachments, _subagentAttachments) ||
                _sameSubagentAttachments(
                  _subagentAttachments,
                  result.subagentAttachments,
                );
      if (cliUnchanged &&
          attachmentsUnchanged &&
          _mailboxUnchanged(mailboxRecords)) {
        _lastMailboxRecords = mailboxRecords;
        return;
      }
      if (!cliUnchanged) {
        _cliMessages = messages;
      }
      _lastMailboxRecords = mailboxRecords;
      if (result.subagentAttachments.isNotEmpty) {
        _setSubagentAttachments(result.subagentAttachments);
      } else if (result.subagentSideIndexDirty &&
          _subagentAttachments.isNotEmpty) {
        await _refreshMaterializedSubagentAttachments();
      } else if (!cliUnchanged && _subagentAttachments.isNotEmpty) {
        _clearSubagentAttachments();
      }
      final cached = buildConversationTimelineIncremental(
        previous: _cachedTimeline,
        cliMessages: _cliMessages,
        mailboxRecords: mailboxRecords,
      );
      _cachedTimeline = cached;
      _applySoftReloadMessages(cached.snapshot.messages, sessionId, memberId);
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
      final mailboxRecords = await _safeLoadMailboxRecords(sessionId, memberId);
      if (gen != _loadGeneration || isClosed) return;
      if (session.sessionId != (_lastSession?.sessionId ?? '') ||
          memberId != _lastMemberId) {
        return;
      }

      final cached = buildConversationTimelineIncremental(
        previous: _cachedTimeline,
        cliMessages: _cliMessages,
        mailboxRecords: mailboxRecords,
      );
      _cachedTimeline = cached;
      _lastMailboxRecords = mailboxRecords;
      _applySoftReloadMessages(cached.snapshot.messages, sessionId, memberId);
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
    bool historyContinueInFlight = false,
  }) {
    if (isClosed) return HistoryAwaitingWorkingAction.none;
    final action = resolveHistoryAwaitingWorkingAction(
      awaitingAssistant: state.awaitingAssistant,
      sessionWorking: sessionWorking,
      sawWorkingWhileAwaiting: _sawWorkingWhileAwaiting,
      sessionConnecting: sessionConnecting,
      memberRunning: memberRunning,
      historyContinueInFlight: historyContinueInFlight,
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

  bool _pendingDeliveryLatchesAwaiting(FailedMessageStatus? deliveryStatus) =>
      deliveryStatus != FailedMessageStatus.failed;

  void enqueuePendingUser(
    String text, {
    String? id,
    FailedMessageStatus? deliveryStatus,
  }) {
    if (isClosed) return;
    final latchAwaiting = _pendingDeliveryLatchesAwaiting(deliveryStatus);
    if (latchAwaiting) {
      // New user turn — need a fresh rising edge of working.
      _sawWorkingWhileAwaiting = false;
    }
    final pending = _PendingUser(
      id: id ?? 'pending:${_uuid.v4()}',
      text: text,
      deliveryStatus: deliveryStatus,
    );
    // One overlay at a time: a newer send drops any leftover bubble (including
    // failed rows) so the thread cannot stack unmatched user messages.
    _replacePendingQueue(pending);
    _remergePendingsOntoRuntime();
    // Empty / loading: promote to ready so History shows the pending bubble
    // instead of the empty / spinner pane (runtime already has the tip message).
    if (state.status == AiHistoryViewStatus.empty ||
        state.status == AiHistoryViewStatus.loading) {
      emit(
        state.copyWith(
          status: AiHistoryViewStatus.ready,
          awaitingAssistant: latchAwaiting || state.awaitingAssistant,
        ),
      );
    } else if (latchAwaiting) {
      emit(state.copyWith(awaitingAssistant: true));
    }
  }

  /// Writes an outgoing bubble before compose is cleared, then overlays that
  /// exact persisted record rather than creating a second optimistic message.
  Future<FailedMessageRecord> persistPendingUser({
    required FailedMessageStore store,
    required String workspaceId,
    required String sessionId,
    required String text,
    String? deliveryId,
  }) async {
    _bindFailedMessageStore(
      store: store,
      workspaceId: workspaceId,
      sessionId: sessionId,
    );
    final correlationId = deliveryId?.trim() ?? '';
    final existing = correlationId.isEmpty
        ? null
        : (await store.load(
            workspaceId,
            sessionId,
          )).where((record) => record.deliveryId == correlationId).firstOrNull;
    final record =
        existing ??
        FailedMessageRecord(
          id: 'pending:${_uuid.v4()}',
          text: text,
          createdAt: DateTime.now().toUtc(),
          deliveryId: correlationId.isEmpty ? null : correlationId,
        );
    if (existing == null) {
      await store.save(workspaceId, sessionId, record);
    }
    enqueuePendingUser(
      record.text,
      id: record.id,
      deliveryStatus: record.status,
    );
    return record;
  }

  /// Reuses a failed optimistic bubble for another delivery attempt.
  ///
  /// The record id stays stable so the retry is rendered in place rather than
  /// appending a duplicate outgoing message. [record.text] may be changed by
  /// edit-and-retry before this transition is persisted.
  Future<FailedMessageRecord> retryPendingUser({
    required FailedMessageStore store,
    required String workspaceId,
    required String sessionId,
    required FailedMessageRecord record,
  }) async {
    _bindFailedMessageStore(
      store: store,
      workspaceId: workspaceId,
      sessionId: sessionId,
    );
    final retrying = record.copyWith(status: FailedMessageStatus.sending);
    await store.save(workspaceId, sessionId, retrying);
    final index = _pendingQueue.indexWhere(
      (pending) => pending.id == retrying.id,
    );
    if (index < 0) {
      enqueuePendingUser(
        retrying.text,
        id: retrying.id,
        deliveryStatus: retrying.status,
      );
    } else {
      _pendingQueue[index] = _PendingUser(
        id: retrying.id,
        text: retrying.text,
        deliveryStatus: retrying.status,
      );
      _remergePendingsOntoRuntime();
      emit(state.copyWith(awaitingAssistant: true));
    }
    return retrying;
  }

  /// Restores delivery-state records after a history seat is freshly bound.
  Future<void> hydratePendingUsers({
    required FailedMessageStore store,
    required String workspaceId,
    required String sessionId,
  }) async {
    _bindFailedMessageStore(
      store: store,
      workspaceId: workspaceId,
      sessionId: sessionId,
    );
    final records = await store.load(workspaceId, sessionId);
    if (isClosed) return;
    for (final record in records) {
      if (record.status == FailedMessageStatus.sent ||
          _pendingQueue.any((pending) => pending.id == record.id)) {
        continue;
      }
      // Transcript already owns this send — silent success, no overlay.
      if (transcriptConfirmsPendingRecord(
        record: record,
        messages: _allMessages,
      )) {
        await store.remove(workspaceId, sessionId, record.id);
        continue;
      }
      enqueuePendingUser(
        record.text,
        id: record.id,
        deliveryStatus: record.status,
      );
    }
  }

  FailedMessageStatus? pendingDeliveryStatusFor(String id) => _pendingQueue
      .where((pending) => pending.id == id)
      .map((pending) => pending.deliveryStatus)
      .firstOrNull;

  Map<String, FailedMessageStatus> get pendingDeliveryStatuses => {
    for (final pending in _pendingQueue)
      if (pending.deliveryStatus case final status?) pending.id: status,
  };

  /// Keeps the failed bubble in place for recovery instead of rolling it back.
  Future<void> markPendingFailed({
    required FailedMessageStore store,
    required String workspaceId,
    required String sessionId,
    required FailedMessageRecord record,
  }) async {
    _bindFailedMessageStore(
      store: store,
      workspaceId: workspaceId,
      sessionId: sessionId,
    );
    final failed = record.copyWith(status: FailedMessageStatus.failed);
    await store.save(workspaceId, sessionId, failed);
    final index = _pendingQueue.indexWhere(
      (pending) => pending.id == record.id,
    );
    if (index < 0) return;
    _pendingQueue[index] = _PendingUser(
      id: failed.id,
      text: failed.text,
      deliveryStatus: failed.status,
    );
    _remergePendingsOntoRuntime();
    emit(state.copyWith(awaitingAssistant: false));
  }

  /// Drops one persisted pending by id after a successful deliver or explicit
  /// cancel — avoids duplicate user bubbles while the CLI transcript catches up.
  Future<void> removePendingById(String id) async {
    if (isClosed) return;
    final trimmed = id.trim();
    if (trimmed.isEmpty) return;
    final before = _pendingQueue.length;
    _pendingQueue.removeWhere((pending) => pending.id == trimmed);
    if (_pendingQueue.length == before) return;
    await _removePersistedPending(trimmed);
    if (isClosed) return;
    _remergePendingsOntoRuntime();
    _syncAwaitingAfterPendingRemoval();
  }

  void _syncAwaitingAfterPendingRemoval() {
    if (!_pendingQueue.any(
      (pending) => _pendingDeliveryLatchesAwaiting(pending.deliveryStatus),
    )) {
      if (state.awaitingAssistant) {
        emit(state.copyWith(awaitingAssistant: false));
      }
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
    _syncAwaitingAfterPendingRemoval();
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

  /// Loads the next older history page. [SessionHistoryThread] awaits this
  /// before applying scroll anchoring so async seat/loader work finishes first.
  Future<void> loadOlder() async {
    if (state.status != AiHistoryViewStatus.ready) return;
    if (!state.hasOlder || state.isLoadingOlder) return;

    if (_pageCursor == null) {
      _visibleCount = math.min(
        _visibleCount + kSessionHistoryOlderPageSize,
        _committedLength,
      );
      _emitReadyWindow(state.sessionId, state.memberId);
      return;
    }

    emit(state.copyWith(isLoadingOlder: true));
    try {
      final result = await _loader.loadOlder(
        sessionId: state.sessionId ?? '',
        memberId: state.memberId ?? '',
      );
      if (isClosed) return;
      if (result == null) {
        _sourceHasOlder = false;
        _pageCursor = null;
        if (_visibleCount < _committedLength) {
          _visibleCount = math.min(
            _visibleCount + kSessionHistoryOlderPageSize,
            _committedLength,
          );
        }
        _emitReadyWindow(state.sessionId, state.memberId);
        return;
      }
      await _applyOlderPage(result);
    } catch (e, st) {
      appLogger.w(
        '[ai-history] loadOlder failed session=${state.sessionId} '
        'member=${state.memberId}: $e',
        error: e,
        stackTrace: st,
      );
      if (isClosed) return;
      emit(
        state.copyWith(
          isLoadingOlder: false,
          softReloadError: e.toString(),
          hasOlder: _hasOlder(),
        ),
      );
    }
  }

  Future<void> _applyOlderPage(AiHistoryLoadResult result) async {
    _pageCursor = result.cursor;
    _sourceHasOlder = result.hasOlder;
    _cliMessages = prependOlderHistoryMessages(
      older: result.messages,
      recent: _cliMessages,
    );
    final sessionId = state.sessionId ?? '';
    final memberId = state.memberId ?? '';
    final previous = _allMessages;
    final merged = await _mergeWithMailbox(_cliMessages, sessionId, memberId);
    if (isClosed) return;
    var next = reuseHistoryMessageIdentity(previous: previous, next: merged);
    final cli = _lastCli;
    if (cli != null) {
      next = _loader.annotate(next, cli: cli);
    }
    next = _dedupeLiveMessages(
      next,
      sessionId: sessionId,
      memberId: memberId,
      source: 'loadOlder',
    );
    final added = math.max(0, next.length - previous.length);
    _allMessages = next;
    _committedLength = _allMessages.length;
    _visibleCount = math.min(
      _visibleCount + math.max(added, result.messages.length),
      _committedLength,
    );
    _syncAppliedSnapshotAfterStructuralEdit();
    _remergePendingsOntoRuntime();
    _emitReadyWindow(sessionId, memberId);
  }

  Future<void> _hydrateFullIndex(
    int gen,
    String sessionId,
    String memberId,
  ) async {
    try {
      final full = await _loader.fullIndex(
        sessionId: sessionId,
        memberId: memberId,
      );
      if (full == null || gen != _loadGeneration || isClosed) return;
      _cliMessages = reuseHistoryMessageIdentity(
        previous: _cliMessages,
        next: full.messages,
      );
      _lastCli = full.cli;
      if (full.subagentAttachments.isNotEmpty) {
        _setSubagentAttachments(full.subagentAttachments);
      }
      final merged = await _mergeWithMailbox(_cliMessages, sessionId, memberId);
      if (gen != _loadGeneration || isClosed) return;
      final previous = _allMessages;
      var next = reuseHistoryMessageIdentity(previous: previous, next: merged);
      next = _dedupeLiveMessages(
        next,
        sessionId: sessionId,
        memberId: memberId,
        source: 'fullIndex',
      );
      _allMessages = next;
      _committedLength = _allMessages.length;
      _visibleCount = math.min(_visibleCount, _committedLength);
      if (_visibleCount <= 0 && _committedLength > 0) {
        _visibleCount = math.min(kSessionHistoryInitialTurns, _committedLength);
      }
      _pageCursor = null;
      _sourceHasOlder = false;
      _syncAppliedSnapshotAfterStructuralEdit();
      if (state.status == AiHistoryViewStatus.ready ||
          state.status == AiHistoryViewStatus.empty) {
        _emitReadyWindow(sessionId, memberId);
      } else {
        _remergePendingsOntoRuntime();
      }
    } on Object catch (e, st) {
      appLogger.w(
        '[ai-history] full index failed session=$sessionId member=$memberId: $e',
        error: e,
        stackTrace: st,
      );
    }
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
    _lastMailboxRecords = mailboxRecords;
    final cached = buildConversationTimelineIncremental(
      previous: _cachedTimeline,
      cliMessages: cliMessages,
      mailboxRecords: mailboxRecords,
    );
    _cachedTimeline = cached;
    return cached.snapshot.messages;
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

  /// True when [next] carries the same records as the last applied snapshot.
  ///
  /// The bus log is append-only per member, so equality of length + per-record
  /// `seq` (monotonic) + `read` flag is a faithful fingerprint. O(mailbox), and
  /// a member's mailbox is tiny compared to the transcript.
  bool _mailboxUnchanged(List<LoggedMessage> next) {
    final previous = _lastMailboxRecords;
    if (previous == null) return false;
    if (previous.length != next.length) return false;
    for (var i = 0; i < previous.length; i++) {
      if (previous[i].seq != next[i].seq) return false;
      if (previous[i].read != next[i].read) return false;
    }
    return true;
  }

  /// True when [incoming] is the recent-page suffix of the already-hydrated
  /// CLI transcript. Token-cache `load()` may still return that page after
  /// [fullIndex] lands; replacing [_cliMessages] with it would shrink
  /// [loadedMessages] on [softReload].
  bool _isHydratedIndexSuffix(List<AiMessage> incoming) {
    if (incoming.isEmpty || incoming.length >= _cliMessages.length) {
      return false;
    }
    final offset = _cliMessages.length - incoming.length;
    for (var i = 0; i < incoming.length; i++) {
      if (incoming[i].id != _cliMessages[offset + i].id) return false;
    }
    return true;
  }

  void _applyMessages(
    List<AiMessage> messages,
    String sessionId,
    String memberId,
  ) {
    final cli = _lastCli;
    if (cli != null) {
      messages = _loader.annotate(messages, cli: cli);
    }
    messages = _dedupeLiveMessages(
      messages,
      sessionId: sessionId,
      memberId: memberId,
      source: 'applyMessages',
    );
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
    final cli = _lastCli;
    if (cli != null) {
      messages = _loader.annotate(messages, cli: cli);
    }
    messages = _dedupeLiveMessages(
      messages,
      sessionId: sessionId,
      memberId: memberId,
      source: 'applySoftReloadMessages',
    );
    final previousMessages = _allMessages;
    messages = reuseHistoryMessageIdentity(previous: previousMessages, next: messages);
    final oldLength = previousMessages.length;
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

  /// 发布前的兜底去重 + 取证日志。规则见
  /// [dedupeAiHistoryMessages]；命中 `removed` 时打 `action=deduped` 日志，
  /// 命中规则无法判定的同文本对（`undecidedPairs`，两消息都保留）时打
  /// `action=kept-both` 日志，均为 `w` 级；两种 action 的指纹各自防刷屏。
  List<AiMessage> _dedupeLiveMessages(
    List<AiMessage> messages, {
    required String sessionId,
    required String memberId,
    required String source,
  }) {
    final result = dedupeAiHistoryMessages(messages);
    if (result.removed.isEmpty && result.undecidedPairs.isEmpty) {
      return messages;
    }
    final cli = _lastCli;
    if (result.removed.isNotEmpty) {
      final action = 'deduped';
      final ids = result.removed.map((m) => m.id).join(',');
      final fingerprint =
          '$sessionId\u0000$memberId\u0000$action\u0000$ids'
          '\u0000${result.messages.length}';
      if (fingerprint != _lastDedupeLogFingerprint) {
        _lastDedupeLogFingerprint = fingerprint;
        final preview = result.removed
            .map((m) => _dedupePreviewMessage(m))
            .join(' | ');
        appLogger.w(
          '[ai-history] duplicate-messages session=$sessionId '
          'member=$memberId cli=${cli?.name ?? '?'} source=$source '
          'action=$action kept=${result.messages.length} removed=$preview',
        );
      }
    }
    if (result.undecidedPairs.isNotEmpty) {
      final action = 'kept-both';
      final ids = result.undecidedPairs
          .map((p) => '${p.$1.id},${p.$2.id}')
          .join(',');
      final fingerprint =
          '$sessionId\u0000$memberId\u0000$action\u0000$ids'
          '\u0000${result.messages.length}';
      if (fingerprint != _lastKeptBothLogFingerprint) {
        _lastKeptBothLogFingerprint = fingerprint;
        final preview = result.undecidedPairs
            .map(
              (p) =>
                  '${_dedupePreviewMessage(p.$1)} '
                  'vs ${_dedupePreviewMessage(p.$2)}',
            )
            .join(' | ');
        appLogger.w(
          '[ai-history] duplicate-messages session=$sessionId '
          'member=$memberId cli=${cli?.name ?? '?'} source=$source '
          'action=$action kept=${result.messages.length} pairs=$preview',
        );
      }
    }
    return result.messages;
  }

  String _dedupePreviewMessage(AiMessage m) {
    final text = m.parts
        .whereType<AiTextPart>()
        .map((p) => p.text)
        .join(' ')
        .trim();
    final tools = m.parts
        .whereType<AiToolCallPart>()
        .map((t) => '${t.toolName}(${t.result != null ? 'result' : 'pending'})')
        .join(',');
    final shown = text.length > 80 ? '${text.substring(0, 80)}…' : text;
    return '${m.id}[${m.role.name}] text=$shown tools=$tools';
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

  /// Drops the optimistic pending when any user or CLI message newly appears
  /// in the applied timeline. The pending text is not compared: a CLI may
  /// rewrite what the user typed. First apply only records a baseline so a
  /// seed/pending overlay survives the load that was already in flight.
  void _reconcilePendings() {
    final ids = [for (final message in _allMessages) message.id];
    final tipContent = _allMessages.isEmpty
        ? null
        : messageContentIdentity(_allMessages.last);
    if (!_appliedSnapshotSeen) {
      _appliedSnapshotSeen = true;
      _lastAppliedIds = ids;
      _lastAppliedTipContent = tipContent;
      return;
    }
    if (!_sameStringList(ids, _lastAppliedIds) ||
        tipContent != _lastAppliedTipContent) {
      _dropAllPendings(removePersisted: true);
    }
    _lastAppliedIds = ids;
    _lastAppliedTipContent = tipContent;
  }

  /// fullIndex / loadOlder: update the applied baseline. Drop optimistic
  /// pendings only when the **tip** changes — prepends keep the same tip and
  /// must not clear an in-flight overlay.
  void _syncAppliedSnapshotAfterStructuralEdit() {
    final ids = [for (final message in _allMessages) message.id];
    final tipContent = _allMessages.isEmpty
        ? null
        : messageContentIdentity(_allMessages.last);
    if (_appliedSnapshotSeen && tipContent != _lastAppliedTipContent) {
      _dropAllPendings(removePersisted: true);
    }
    _appliedSnapshotSeen = true;
    _lastAppliedIds = ids;
    _lastAppliedTipContent = tipContent;
  }

  static bool _sameStringList(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void _replacePendingQueue(_PendingUser pending) {
    final replaced = [
      for (final previous in _pendingQueue)
        if (previous.id != pending.id) previous,
    ];
    _pendingQueue
      ..clear()
      ..add(pending);
    for (final previous in replaced) {
      unawaited(_removePersistedPending(previous.id));
    }
  }

  void _dropAllPendings({required bool removePersisted}) {
    if (_pendingQueue.isEmpty) return;
    final dropped = List<_PendingUser>.of(_pendingQueue);
    _pendingQueue.clear();
    if (!removePersisted) return;
    for (final pending in dropped) {
      unawaited(_removePersistedPending(pending.id));
    }
  }

  void _bindFailedMessageStore({
    required FailedMessageStore store,
    required String workspaceId,
    required String sessionId,
  }) {
    _failedMessageStore = store;
    _failedMessageWorkspaceId = workspaceId;
    _failedMessageSessionId = sessionId;
  }

  Future<void> _removePersistedPending(String recordId) async {
    final store = _failedMessageStore;
    final workspaceId = _failedMessageWorkspaceId;
    final sessionId = _failedMessageSessionId;
    if (store == null || workspaceId == null || sessionId == null) return;
    await store.remove(workspaceId, sessionId, recordId);
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
            createdAt: null,
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
      // Same message list instance (incremental append reuses it) → skip the
      // content scan that string-builds every message part on the UI isolate.
      if (identical(entry.value.messages, other.messages)) continue;
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

  Future<void> _refreshMaterializedSubagentAttachments() async {
    final ids = List<String>.from(_subagentAttachments.keys);
    for (final id in ids) {
      await loadSubagentAttachment(id, force: true);
    }
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

  bool _hasOlder() => _sourceHasOlder || _visibleCount < _committedLength;

  @override
  Future<void> close() {
    _cancelTipHoldTimer();
    runtime.close();
    return super.close();
  }
}
