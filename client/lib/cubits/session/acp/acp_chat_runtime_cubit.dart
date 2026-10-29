import 'dart:async';

import 'package:acpd/acpd.dart' as acpd;
import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';

import '../../../models/team_config.dart';
import '../../../services/acp/acp_agent_session_store.dart';
import '../../../services/acp/acp_agent_translator.dart';
import '../../../services/acp/acp_chat_extension_fold.dart';
import '../../../services/acp/acp_chat_strings.dart';
import '../../../services/acp/acp_chat_transcript.dart';
import '../../../services/acp/acp_chat_transcript_replay.dart';
import '../../../services/acp/acp_client_extensions.dart';
import '../../../services/acp/acp_rpc_error.dart';
import '../../../services/acp/acp_session.dart';
import '../../../services/acp/acp_session_runtime.dart';
import '../../../services/agent_status/agent_attention_state.dart';
import '../../../services/agent_status/agent_permission_request.dart';
import '../../../services/agent_status/agent_status_event.dart';
import '../../../utils/logging/logger.dart';
import '../../../services/agent_status/agent_attention_port.dart';
import '../../../services/agent_status/seat_lease_port.dart';

/// Lifecycle phase of the terminal-less ACP chat session.
enum AcpChatPhase {
  /// Agent process spawn + handshake in flight.
  launching,

  /// Handshake done; waiting for the first prompt.
  ready,

  /// Turn finished; ready for the next prompt.
  idle,

  /// Session is over (launch failure or process crash); no further prompts.
  ended,
}

/// What the agent is doing inside the current turn.
///
/// [none] means no turn is in flight. When several signals are live at once
/// the precedence is [toolRunning] > [generating] > [thinking].
enum AcpChatActivity { none, thinking, generating, toolRunning }

/// Why the session ended / errored.
enum AcpChatErrorKind {
  /// Every ACP flag candidate failed (old CLI version) —
  /// [AcpLaunchException] with [acpLaunchFailedVersion].
  launchFailedVersion,

  /// The separate ACP adapter binary is not installed —
  /// [AcpLaunchException] with [acpLaunchFailedAdapter].
  launchFailedAdapter,

  /// The agent process could not be spawned or never completed the handshake
  /// (binary missing, spawn/install failure, handshake error). Distinct from
  /// [processExited], which is a mid-session crash of an already-open session.
  launchFailed,

  /// The agent process exited before the session was closed.
  processExited,
}

/// Terminal error surfaced with [AcpChatPhase.ended].
class AcpChatError {
  const AcpChatError({required this.kind, required this.message});

  final AcpChatErrorKind kind;

  /// Already-localized user-facing copy.
  final String message;
}

/// State of [AcpChatRuntimeCubit].
class AcpChatRuntimeState {
  const AcpChatRuntimeState({
    this.phase = AcpChatPhase.launching,
    this.messages = const [],
    this.inTurn = false,
    this.pendingClient,
    this.error,
    this.activity = AcpChatActivity.none,
    this.historyHydrated = false,
    this.modelState,
  });

  final AcpChatPhase phase;

  /// Chat transcript in arrival order (app-side single source).
  final List<AiMessage> messages;

  /// True from prompt submit until the turn's stop event.
  final bool inTurn;

  /// The currently held permission / ask / plan card, if any.
  final AcpPendingClientRequest? pendingClient;

  /// Permission payload when [pendingClient] is [AcpPendingPermission].
  AgentPermissionRequest? get pendingPermission {
    final pending = pendingClient;
    return pending is AcpPendingPermission ? pending.request : null;
  }

  final AcpChatError? error;

  /// What the agent is doing inside the current turn.
  final AcpChatActivity activity;

  /// True after the hydrate attempt finishes, including a thrown read.
  /// The loading pane may clear; this is not permission to rewrite the file.
  final bool historyHydrated;

  /// The agent's model selector, when it advertises one.
  final AcpModelState? modelState;

  AcpChatRuntimeState copyWith({
    AcpChatPhase? phase,
    List<AiMessage>? messages,
    bool? inTurn,
    Object? pendingClient = _unset,
    AcpChatError? error,
    bool clearError = false,
    AcpChatActivity? activity,
    bool? historyHydrated,
    Object? modelState = _unset,
  }) => AcpChatRuntimeState(
    phase: phase ?? this.phase,
    messages: messages ?? this.messages,
    inTurn: inTurn ?? this.inTurn,
    pendingClient: identical(pendingClient, _unset)
        ? this.pendingClient
        : pendingClient as AcpPendingClientRequest?,
    error: clearError ? null : (error ?? this.error),
    activity: activity ?? this.activity,
    historyHydrated: historyHydrated ?? this.historyHydrated,
    modelState: identical(modelState, _unset)
        ? this.modelState
        : modelState as AcpModelState?,
  );

  static const _unset = Object();
}

/// Drives one terminal-less ACP chat session inside the workbench.
///
/// Maps [AcpSessionUpdate]s onto the shared [AiMessage] model (chunks → text
/// parts, thoughts → reasoning parts, tool calls → tool-card parts, stops →
/// idle), persists folded messages as an atomic snapshot on commit (not per
/// chunk), surfaces permission requests onto the existing attention/card
/// plumbing, and keeps turns strictly sequential (the overlap guard in
/// [AcpAgentSession.prompt] throws otherwise).
///
/// Subscribes to [AcpSessionRuntimeApi.updates] BEFORE the first prompt — the
/// broadcast stream has no buffering, so a late subscriber would lose chunks.
class AcpChatRuntimeCubit extends Cubit<AcpChatRuntimeState> {
  AcpChatRuntimeCubit({
    required AcpSessionRuntimeApi runtime,
    required this.sessionId,
    required this.tool,
    this.seatMemberId = acpMemberId,
    AgentAttentionPort? attention,
    AcpChatTranscriptWriter? transcript,
    AcpAgentSessionStore? agentSession,
    SeatBackgroundLeasePort? seatLeases,
    Duration? backgroundSyncInterval,
    this.backgroundSyncWindow = defaultBackgroundSyncWindow,
  }) : _runtime = runtime,
       _attention = attention,
       _transcript = transcript,
       _agentSession = agentSession,
       _seatLeases = seatLeases,
       _backgroundSyncInterval = backgroundSyncInterval,
       super(const AcpChatRuntimeState());

  /// Synthetic seat member id — an ACP session has exactly one member, the
  /// agent (mirrors [AcpAgentSession]'s permission hold seat).
  static const acpMemberId = 'acp';

  /// Aggregate background-task lease id (ACP has no per-task completion
  /// signal, so the whole watch shares one coarse hold).
  static const backgroundLeaseId = 'acp-background-task';

  /// Upper bound on out-of-turn history polling after a background tool call.
  static const defaultBackgroundSyncWindow = Duration(minutes: 45);

  /// Poll cadence: responsive right after a launch (the first completion is
  /// usually minutes out), calmer for long suites so the agent is not asked to
  /// replay its history every few seconds for an hour.
  static const _backgroundSyncFastInterval = Duration(seconds: 10);
  static const _backgroundSyncSlowInterval = Duration(seconds: 60);
  static const _backgroundSyncFastWindow = Duration(minutes: 3);

  static const _uuid = Uuid();

  final AcpSessionRuntimeApi _runtime;
  final String sessionId;
  final CliTool tool;
  final String seatMemberId;
  final AgentAttentionPort? _attention;
  final AcpChatTranscriptWriter? _transcript;
  final AcpAgentSessionStore? _agentSession;
  final SeatBackgroundLeasePort? _seatLeases;

  /// Test/embedding override for the history-sync poll cadence.
  final Duration? _backgroundSyncInterval;
  final Duration backgroundSyncWindow;

  AcpChatStrings? _strings;
  StreamSubscription<AcpSessionUpdate>? _updatesSub;
  StreamSubscription<AgentPermissionRequest>? _permissionSub;
  StreamSubscription<AcpPendingClientRequest>? _clientRequestsSub;
  ({String text, int serial})? _queuedPrompt;
  int _turnSerial = 0;
  bool _closing = false;
  Future<void>? _hydrateInFlight;

  /// True only when [AcpChatTranscriptWriter.loadMessages] returned (missing
  /// file, empty, garbage→[], or a decoded list). Stays false for this cubit's
  /// lifetime if the initial load threw, so a later persist cannot replace an
  /// unread file after a transient I/O error. The user still chats in memory;
  /// disk stays the unread file until the next successful reopen.
  bool _allowPersist = false;

  /// Tool-call ids opened this turn and not yet terminated.
  final Set<String> _runningToolCalls = {};

  /// Snapshot of the message list being rebuilt by a history reconciliation.
  /// Non-null while replay updates are folded; prevents them from touching the
  /// live turn trackers or emitting intermediate states.
  List<AiMessage>? _replayMessages;

  /// In-flight [syncHistory] so overlapping background ticks coalesce.
  Future<void>? _historySyncInFlight;

  /// Out-of-turn history polling: armed by a background tool call, disarmed
  /// when the session closes, the completion is observed, or
  /// [backgroundSyncWindow] elapses.
  Timer? _backgroundSyncTimer;
  DateTime? _backgroundSyncStartedAt;

  /// A background tool call was opened during the live turn in progress.
  /// [endTurn] arms the watch when this is set.
  bool _turnHadBackgroundToolCall = false;

  /// A background watch is live (lease held, polling scheduled).
  bool _backgroundWorkActive = false;

  /// Whether the watch has not folded a reconcile yet (used to tell a fast
  /// completion of the armed task from a brand-new background launch).
  bool _backgroundFirstReplay = true;

  /// Total assistant text length observed at watch arm. Growth past this with
  /// no new background tool call means the agent resumed (task finished).
  int? _backgroundBaselineTextLen;

  /// Background tool-call ids already folded this watch. A replay carrying a
  /// new id means another background task started, so the watch continues.
  final Set<String> _backgroundKnownBgIds = {};

  /// Background tool-call ids seen while folding the replay in flight. Reset
  /// per reconcile; used to detect a newly launched task.
  final Set<String> _replayedBackgroundToolCalls = {};

  /// Whether the current turn has emitted any message chunk yet.
  bool _seenChunkThisTurn = false;

  /// Activity implied by the turn trackers. Callers must have already updated
  /// the trackers for the event in hand.
  AcpChatActivity _turnActivity() {
    if (_runningToolCalls.isNotEmpty) return AcpChatActivity.toolRunning;
    if (_seenChunkThisTurn) return AcpChatActivity.generating;
    return AcpChatActivity.thinking;
  }

  /// Clears the per-turn trackers. Called when a turn opens and when it ends.
  void _resetTurnTrackers() {
    _seenChunkThisTurn = false;
    _runningToolCalls.clear();
    _turnHadBackgroundToolCall = false;
  }

  /// Injects localized copy; must run before [start].
  void ensureStrings(AcpChatStrings strings) => _strings ??= strings;

  /// The local agent OS pid, or null when the runtime has no process to
  /// measure (SSH / tests). Consumed by the Resource Manager metrics registry.
  int? get agentPid {
    final runtime = _runtime;
    if (runtime is! AcpAgentProcessPidApi) return null;
    return (runtime as AcpAgentProcessPidApi).agentPid;
  }

  /// Reads the runtime's model selector through the optional ACP capability.
  AcpModelState? _readModelState() {
    final runtime = _runtime;
    if (runtime is! AcpModelSwitchApi) return null;
    return (runtime as AcpModelSwitchApi).modelState;
  }

  /// Whether this runtime can switch models without restarting the agent.
  bool get supportsModelSwitch => _runtime is AcpModelSwitchApi;

  /// Switches the open session's model via the agent's `model` config option.
  ///
  /// Returns false when the runtime does not support model switching, the
  /// session has ended, or the agent rejects the request. A successful call
  /// updates [AcpChatRuntimeState.modelState] from the agent's response.
  Future<bool> setModel(String modelId) async {
    final modelRuntime = _runtime is AcpModelSwitchApi
        ? _runtime as AcpModelSwitchApi
        : null;
    if (modelRuntime == null) return false;
    if (_closing || isClosed || state.phase == AcpChatPhase.ended) return false;
    try {
      await modelRuntime.setModel(modelId);
      if (!isClosed) emit(state.copyWith(modelState: modelRuntime.modelState));
      return true;
    } on Object catch (error, stackTrace) {
      appLogger.w(
        '[acp-chat] session $sessionId model switch failed: $error',
        error: error,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  /// Spawns the agent and opens the ACP session.
  ///
  /// On success: subscribes to updates + permissions (before any prompt),
  /// stamps the attention seat idle, and moves to [AcpChatPhase.ready].
  /// On [AcpLaunchException]: inline system message + ended phase.
  /// [AcpAuthenticateException] and authenticate [TimeoutException] use
  /// not-logged-in copy. [acpd.RpcError] from `session/new` uses
  /// session-open-failed copy plus the agent's nested reason when present.
  /// Any other failure is logged and ends the session.
  Future<void> start({
    required String executable,
    required String sessionToolDir,
    required String workingDirectory,
    Map<String, String> baseEnv = const {},
    List<acpd.McpServer> mcpServers = const [],
    LaunchSecurityPolicy permissionPolicy = LaunchSecurityPolicy.fullAccess,
  }) async {
    if (state.phase != AcpChatPhase.launching) return;
    _hydrateInFlight ??= _hydrateTranscript();
    await _hydrateInFlight;
    if (_closing || isClosed) return;
    final resume = await _agentSession?.readRecord();
    if (_closing || isClosed) return;
    final resumeId = resume?.sessionId;
    // Resume in the directory the agent session actually lives in. ACP
    // `session/load` requires an exact directory match (OpenCode answers a
    // mismatch with `ACPSessionDirectoryMismatchError`), and the session may
    // have moved since TeamPilot last opened it — e.g. into a git worktree.
    final storedCwd = resume?.cwd?.trim() ?? '';
    final effectiveWorkingDirectory = storedCwd.isNotEmpty
        ? storedCwd
        : workingDirectory;
    try {
      await _runtime.start(
        tool: tool,
        executable: executable,
        sessionToolDir: sessionToolDir,
        workingDirectory: effectiveWorkingDirectory,
        baseEnv: baseEnv,
        mcpServers: mcpServers,
        permissionPolicy: permissionPolicy,
        resumeSessionId: resumeId,
      );
    } on AcpLaunchException catch (error) {
      if (error.reason == acpLaunchFailedAdapter) {
        _endWith(
          AcpChatErrorKind.launchFailedAdapter,
          _strings?.launchFailedAdapter ??
              defaultAcpChatStrings.launchFailedAdapter,
        );
        return;
      }
      _endWith(
        AcpChatErrorKind.launchFailedVersion,
        error.reason == acpLaunchFailedVersion
            ? _strings?.launchFailedVersion ?? error.reason
            : error.reason,
      );
      return;
    } on AcpAuthenticateException {
      _endWith(
        AcpChatErrorKind.launchFailed,
        _strings?.notLoggedIn ?? defaultAcpChatStrings.notLoggedIn,
      );
      return;
    } on TimeoutException catch (error, stackTrace) {
      if ((error.message ?? error.toString()).contains('authenticate')) {
        _endWith(
          AcpChatErrorKind.launchFailed,
          _strings?.notLoggedIn ?? defaultAcpChatStrings.notLoggedIn,
        );
        return;
      }
      appLogger.e(
        '[acp-chat] session $sessionId launch failed: $error',
        error: error,
        stackTrace: stackTrace,
      );
      _endWith(
        AcpChatErrorKind.launchFailed,
        _strings?.launchFailed ?? defaultAcpChatStrings.launchFailed,
      );
      return;
    } on acpd.RpcError catch (error, stackTrace) {
      final detail = acpRpcErrorUserDetail(error);
      appLogger.e(
        '[acp-chat] session $sessionId launch failed: $error'
        '${detail == null ? '' : ' ($detail)'}',
        error: error,
        stackTrace: stackTrace,
      );
      _endWith(
        AcpChatErrorKind.launchFailed,
        acpSessionOpenFailedCopy(
          prefix:
              _strings?.sessionOpenFailed ??
              defaultAcpChatStrings.sessionOpenFailed,
          detail: detail,
        ),
      );
      return;
    } on Object catch (error, stackTrace) {
      appLogger.e(
        '[acp-chat] session $sessionId launch failed: $error',
        error: error,
        stackTrace: stackTrace,
      );
      // Spawn/install/handshake failures have no per-error copy — surface the
      // shared localized launch-failure message, not the raw exception text.
      _endWith(
        AcpChatErrorKind.launchFailed,
        _strings?.launchFailed ?? defaultAcpChatStrings.launchFailed,
      );
      return;
    }
    if (_closing || isClosed) return;
    _updatesSub = _runtime.updates.listen(
      _onUpdate,
      onError: (Object e) {
        appLogger.w('[acp-chat] session $sessionId updates error: $e');
      },
    );
    final handshakeAuth = _runtime.lastAuthNotice;
    _permissionSub = _runtime.permissionRequests.listen(_onPermissionRequest);
    _clientRequestsSub = _runtime.clientRequests.listen(_onClientRequest);
    // Agent process exit (mid-session crash or out-of-turn death): inline
    // system message + ended phase. Attached in the same step as the other
    // subscriptions, after a successful start — a launch failure path has
    // already returned above and does not reach this watcher. The exit-code
    // future never completes for non-process-backed spawn connections. No
    // handle is retained: `handleProcessExited` -> `_endWith` no-ops once the
    // cubit is closed, so a late completion cannot touch torn-down state.
    final agentExitCode = _runtime.agentProcessExitCode;
    if (agentExitCode != null) {
      unawaited(agentExitCode.then(handleProcessExited));
    }
    _applyAttention(const AgentStatusEvent(state: AgentSeatAttention.done));
    final liveId = _runtime.sessionId;
    if (liveId.isNotEmpty) {
      // Persist the id and the directory we asked for. Agents that can list
      // their sessions re-discover the current cwd on every resume (a session
      // can move), so this is the fallback for agents without `session/list`.
      unawaited(_agentSession?.write(liveId, cwd: effectiveWorkingDirectory));
    }
    emit(
      state.copyWith(phase: AcpChatPhase.ready, modelState: _readModelState()),
    );
    final queued = _queuedPrompt;
    _queuedPrompt = null;
    if (queued != null && queued.serial == _turnSerial) {
      // Flush before replaying handshake auth so a CLI probe `none` cannot
      // land as the first row ahead of the user's already-visible bubble.
      _dispatchPrompt(queued.text, queued.serial);
    } else {
      // A resumed session may have finished out-of-turn work after the last
      // live update; reconcile once so the reopening UI is not stale.
      unawaited(syncHistory());
    }
    if (handshakeAuth != null) unawaited(_onUpdate(handshakeAuth));
  }

  /// Sends one prompt turn. Returns false (and does nothing) when a turn is
  /// already in flight, the session has ended, or the text is blank — the
  /// runtime is strictly sequential.
  bool sendPrompt(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;
    if (state.inTurn || _queuedPrompt != null) return false;
    if (state.phase == AcpChatPhase.ended) return false;
    // Handshake `kind=none` is a CLI probe, not a confirmed logout. Drop it
    // as soon as the user sends so it never sits above the turn.
    _removeAuthNoticeMessage();
    _turnSerial++;
    final serial = _turnSerial;
    if (state.phase == AcpChatPhase.launching ||
        !_runtime.isStarted ||
        // A history reconcile owns the connection's update stream; queue the
        // prompt so its live chunks are not swallowed by the replay buffer.
        _historySyncInFlight != null) {
      _queuedPrompt = (text: trimmed, serial: serial);
      _showUserMessage(trimmed);
      _resetTurnTrackers();
      emit(state.copyWith(inTurn: true, activity: AcpChatActivity.thinking));
      return true;
    }
    _dispatchPrompt(trimmed, serial);
    return true;
  }

  /// Flushes a prompt queued behind a history reconcile (mirrors the launch
  /// queue flush in [start]).
  void _maybeFlushQueuedPrompt() {
    if (_closing || isClosed) return;
    final queued = _queuedPrompt;
    if (queued == null) return;
    if (queued.serial != _turnSerial) {
      _queuedPrompt = null;
      return;
    }
    _queuedPrompt = null;
    if (!_runtime.isStarted) return;
    _dispatchPrompt(queued.text, queued.serial);
  }

  Future<void> _hydrateTranscript() async {
    List<AiMessage>? loaded;
    try {
      loaded = await _transcript?.loadMessages();
    } on Object catch (error, stackTrace) {
      appLogger.e(
        '[acp-chat] session $sessionId history hydrate failed: $error',
        error: error,
        stackTrace: stackTrace,
      );
      if (!isClosed) emit(state.copyWith(historyHydrated: true));
      return;
    }
    if (isClosed) return;
    _allowPersist = true;
    if (loaded == null || loaded.isEmpty) {
      emit(state.copyWith(historyHydrated: true));
      return;
    }
    emit(
      state.copyWith(
        historyHydrated: true,
        messages: mergeHydratedAcpMessages(
          loaded: loaded,
          live: state.messages,
        ),
      ),
    );
  }

  void _showUserMessage(String trimmed) {
    if (_hasMatchingTipUser(trimmed)) return;
    emit(state.copyWith(messages: [...state.messages, _userMessage(trimmed)]));
  }

  bool _hasMatchingTipUser(String trimmed) {
    if (state.messages.isEmpty) return false;
    final tip = state.messages.last;
    if (tip.role != AiRole.user) return false;
    return tip.parts.whereType<AiTextPart>().map((p) => p.text).join() ==
        trimmed;
  }

  void _dispatchPrompt(String trimmed, int serial) {
    _showUserMessage(trimmed);
    _resetTurnTrackers();
    emit(state.copyWith(inTurn: true, activity: AcpChatActivity.thinking));
    // A turn is in flight: without this the ACP seat sits at `done` for the
    // whole turn and every attention-driven surface reads "starting".
    _applyAttention(const AgentStatusEvent(state: AgentSeatAttention.working));
    unawaited(
      _recordAndPrompt(trimmed, serial).catchError((
        Object error,
        StackTrace st,
      ) {
        appLogger.e(
          '[acp-chat] session $sessionId prompt failed: $error',
          error: error,
          stackTrace: st,
        );
        // prompt() failures surface through the updates stream as an error
        // stop; a non-emitting failure still clears the turn here.
        _endTurn();
      }),
    );
  }

  Future<void> _recordAndPrompt(String text, int serial) async {
    await _persist();
    if (_closing || isClosed) return;
    if (serial != _turnSerial) {
      if (state.phase != AcpChatPhase.launching && state.inTurn) {
        _endTurn();
      }
      return;
    }
    await _runtime.prompt(text);
  }

  /// Cancels the current turn (silently resolved via the cancelled stop).
  void cancelTurn() {
    final hadQueued = _queuedPrompt != null;
    _turnSerial++;
    _queuedPrompt = null;
    if (!isClosed) emit(state.copyWith(pendingClient: null));
    if (!_runtime.isStarted) {
      _clearInTurnKeepingPhase();
      unawaited(_persist());
      return;
    }
    _runtime.cancel();
    if (hadQueued) {
      // A prompt queued behind launch/history-sync never reached the runtime,
      // so no stop event will arrive; clear the optimistic in-turn state now.
      _clearInTurnKeepingPhase();
      unawaited(_persist());
    }
  }

  /// Assigns [policy] for subsequent permission requests on the open session.
  void setPermissionPolicy(LaunchSecurityPolicy policy) {
    if (_closing || isClosed) return;
    _runtime.setPermissionPolicy(policy);
  }

  void _clearInTurnKeepingPhase() {
    if (_closing || isClosed) return;
    _resetTurnTrackers();
    _applyAttention(const AgentStatusEvent(state: AgentSeatAttention.done));
    emit(
      state.copyWith(
        inTurn: false,
        pendingClient: null,
        activity: AcpChatActivity.none,
      ),
    );
  }

  /// Answers the pending permission card. Returns whether a reply was
  /// delivered to the agent (false when nothing was held or already ended).
  Future<bool> answerPermission(
    AgentPermissionReplyKind kind, {
    Object? alwaysPayload,
  }) async {
    final pending = state.pendingPermission;
    if (pending == null) return false;
    AgentPermissionAlwaysOption? always;
    if (kind == AgentPermissionReplyKind.always) {
      for (final option in pending.always) {
        if (identical(option.payload, alwaysPayload) ||
            option.payload == alwaysPayload) {
          always = option;
          break;
        }
      }
      always ??= pending.always.isEmpty ? null : pending.always.first;
    }
    emit(state.copyWith(pendingClient: null));
    _applyAttention(const AgentStatusEvent(state: AgentSeatAttention.working));
    final delivered = await _runtime.answerPermission(kind, always: always);
    return delivered != null;
  }

  Future<void> answerAsk(AcpAskHoldReply reply) =>
      _clearPendingThen(() => _runtime.answerAsk(reply));

  Future<void> answerPlan(AcpPlanHoldReply reply) =>
      _clearPendingThen(() => _runtime.answerPlan(reply));

  Future<void> _clearPendingThen(Future<void> Function() run) async {
    emit(state.copyWith(pendingClient: null));
    _applyAttention(const AgentStatusEvent(state: AgentSeatAttention.working));
    await run();
  }

  /// The agent process died (exit watcher callback). Inline crash message +
  /// ended phase — no global error dialog.
  void handleProcessExited(int exitCode) {
    if (_closing || isClosed || state.phase == AcpChatPhase.ended) return;
    _endWith(
      AcpChatErrorKind.processExited,
      '${_strings?.processExited ?? 'Agent process exited'} ($exitCode)',
    );
  }

  @override
  Future<void> close() async {
    // Mark before killing the agent: `_runtime.close()` awaits process exit,
    // so the watcher fires with 0 while this cubit is still open.
    _closing = true;
    _stopBackgroundSync();
    await _updatesSub?.cancel();
    await _permissionSub?.cancel();
    await _clientRequestsSub?.cancel();
    _updatesSub = null;
    _permissionSub = null;
    _clientRequestsSub = null;
    final hydrate = _hydrateInFlight;
    try {
      if (hydrate != null) await hydrate;
    } on Object catch (error, stackTrace) {
      appLogger.e(
        '[acp-chat] session $sessionId hydrate await failed on close: $error',
        error: error,
        stackTrace: stackTrace,
      );
    } finally {
      if (_allowPersist) await _persist();
      // The exit watcher holds no handle to cancel, and a never-completing exit
      // future (the common no-crash case) must not keep close pending — its
      // callback is a no-op once the cubit is closed.
      if (state.phase != AcpChatPhase.ended) {
        _applyAttention(const AgentStatusEvent(state: AgentSeatAttention.done));
      }
      await _runtime.close();
    }
    return super.close();
  }

  // ----- update mapping -----

  /// Maps protocol updates onto in-memory messages. Chunks stay in RAM;
  /// tool cards, stops, and system rows rewrite the snapshot.
  Future<void> _onUpdate(AcpSessionUpdate update) async {
    if (_closing || isClosed) return;
    final replaying = _replayMessages != null;
    switch (update) {
      case AcpMessageChunk():
        if (isClosed) return;
        if (update.role == AcpRole.user) {
          // Live user bubbles are app-owned (SendPrompt inserts them); a user
          // chunk only appears in a history replay, where it anchors the
          // assistant messages that follow it.
          if (replaying) _appendReplayUserChunk(update.content);
          return;
        }
        if (!replaying) {
          _removeAuthNoticeMessage();
          _seenChunkThisTurn = true;
        }
        _appendMessageParts(_chunkParts(update));
      case AcpToolCallUpdate():
        if (isClosed) return;
        _applyToolCall(update);
        if (!replaying) unawaited(_persist());
      case AcpStop():
        if (isClosed || replaying) return;
        _onStop(update);
      case AcpAuthNotice():
        if (isClosed || replaying) return;
        // `_auth/status_update` is reporting-only. `kind: none` comes from an
        // async `claude auth status --json` probe at initialize / prompt start
        // and is not a confirmed TeamPilot logout — session OAuth under
        // CLAUDE_CONFIG_DIR can still succeed. Never turn that probe into a
        // chat row. A later logged-in notice still drops a stale banner.
        if (update.loggedIn) {
          _removeAuthNoticeMessage();
        }
      case AcpModelStateUpdate():
        if (isClosed) return;
        emit(state.copyWith(modelState: update.state));
      case AcpPlan() ||
          AcpTodoListUpdate() ||
          AcpTaskUpdate() ||
          AcpGeneratedImageUpdate():
        if (isClosed) return;
        final folded = foldAcpExtensionNotification(
          messages: _replayMessages ?? state.messages,
          update: update,
          newId: () => 'acp-a-${_uuid.v4()}',
        );
        if (replaying) {
          _replayMessages = folded;
          return;
        }
        emit(state.copyWith(messages: folded));
        unawaited(_persist());
      default:
        break;
    }
  }

  List<AiMessagePart> _chunkParts(AcpMessageChunk chunk) => [
    chunk.isThought
        ? AiReasoningPart(text: chunk.content)
        : AiTextPart(text: chunk.content),
  ];

  void _applyToolCall(AcpToolCallUpdate update) {
    final replaying = _replayMessages != null;
    final launchesBackground = update.background &&
        (update.status == AcpToolCallStatus.pending ||
            update.status == AcpToolCallStatus.inProgress);
    if (!replaying) {
      switch (update.status) {
        case AcpToolCallStatus.pending:
        case AcpToolCallStatus.inProgress:
          _runningToolCalls.add(update.toolCallId);
        case AcpToolCallStatus.completed:
        case AcpToolCallStatus.failed:
          _runningToolCalls.remove(update.toolCallId);
        case null:
          break;
      }
      if (launchesBackground) {
        _turnHadBackgroundToolCall = true;
      }
    } else if (launchesBackground) {
      _replayedBackgroundToolCalls.add(update.toolCallId);
    }
    final activity = replaying ? AcpChatActivity.none : _turnActivity();
    // Upsert onto the last assistant message's matching tool part; a new
    // toolCallId appends a fresh part (tool card).
    final messages = [...(_replayMessages ?? state.messages)];
    for (var i = messages.length - 1; i >= 0; i--) {
      final message = messages[i];
      if (message.role != AiRole.assistant) break;
      final parts = [...message.parts];
      var matched = false;
      for (var j = parts.length - 1; j >= 0; j--) {
        final part = parts[j];
        if (part is AiToolCallPart && part.toolCallId == update.toolCallId) {
          parts[j] = part.copyWith(
            toolName: update.title ?? part.toolName,
            status: _mapToolStatus(update.status) ?? part.status,
            isError: update.status == AcpToolCallStatus.failed || part.isError,
            args: update.args ?? part.args,
            result: update.result ?? part.result,
          );
          matched = true;
          break;
        }
      }
      if (matched) {
        messages[i] = message.copyWith(parts: parts);
        _emitToolCallMessages(messages, activity, replaying);
        return;
      }
      // No match in this message yet — append if it is the tip.
      if (i == messages.length - 1) {
        messages[i] = message.copyWith(
          parts: [
            ...parts,
            AiToolCallPart(
              toolCallId: update.toolCallId,
              toolName: update.title ?? update.toolCallId,
              status:
                  _mapToolStatus(update.status) ?? AiToolCallStatus.incomplete,
              args: update.args,
              result: update.result,
            ),
          ],
        );
        _emitToolCallMessages(messages, activity, replaying);
        return;
      }
    }
    // No assistant message to attach to — start one.
    _appendMessageParts([
      AiToolCallPart(
        toolCallId: update.toolCallId,
        toolName: update.title ?? update.toolCallId,
        status: _mapToolStatus(update.status) ?? AiToolCallStatus.incomplete,
        args: update.args,
        result: update.result,
      ),
    ]);
  }

  void _emitToolCallMessages(
    List<AiMessage> messages,
    AcpChatActivity activity,
    bool replaying,
  ) {
    if (replaying) {
      _replayMessages = messages;
      return;
    }
    emit(state.copyWith(messages: messages, activity: activity));
  }

  AiToolCallStatus? _mapToolStatus(AcpToolCallStatus? status) =>
      switch (status) {
        null => null,
        AcpToolCallStatus.pending => AiToolCallStatus.incomplete,
        AcpToolCallStatus.inProgress => AiToolCallStatus.running,
        AcpToolCallStatus.completed => AiToolCallStatus.complete,
        AcpToolCallStatus.failed => AiToolCallStatus.complete,
      };

  void _onStop(AcpStop stop) {
    switch (stop.kind) {
      case AcpStopKind.cancelled:
        // User cancel: silent (spec).
        unawaited(_persist());
        _endTurn();
      case AcpStopKind.endTurn:
      case AcpStopKind.aborted:
      case AcpStopKind.maxTokens:
        unawaited(_persist());
        _endTurn();
      case AcpStopKind.error:
        final text = stop.message == acpStopAuthRequired
            ? (_strings?.notLoggedIn ?? defaultAcpChatStrings.notLoggedIn)
            : (stop.message == null || stop.message!.isEmpty
                  ? (_strings?.turnFailed ?? 'Turn failed')
                  : '${_strings?.turnFailed ?? 'Turn failed'}: ${stop.message}');
        _appendSystemMessage(text);
        unawaited(_persist());
        _endTurn();
    }
  }

  void _endTurn() {
    if (_closing || isClosed) return;
    final hadBackground = _turnHadBackgroundToolCall;
    _resetTurnTrackers();
    _applyAttention(const AgentStatusEvent(state: AgentSeatAttention.done));
    emit(
      state.copyWith(
        inTurn: false,
        phase: AcpChatPhase.idle,
        pendingClient: null,
        activity: AcpChatActivity.none,
      ),
    );
    // The turn is over but a background shell it launched is still running:
    // ACP goes silent, so watch the agent's history and hold the seat lease so
    // the UI shows "background work running" instead of `done`.
    if (_backgroundWorkActive) {
      // Text the just-finished turn produced arrived live and is already in the
      // transcript, so it must not be read as out-of-turn progress (a follow-up
      // prompt sent while a background task runs would otherwise end the watch).
      _backgroundBaselineTextLen = _assistantTextLen(state.messages);
    }
    if (hadBackground) _armBackgroundWatch();
  }

  // ----- out-of-turn history reconciliation -----

  /// Replays the agent's own session history and merges anything the app
  /// missed after `end_turn` (background shell tasks / subagents).
  ///
  /// ACP v1 sends no `session/update` after a turn ends, so the agent's
  /// summary of out-of-turn work only exists in its recorded history. Uses
  /// `session/load` on the live connection and folds the replay into the app
  /// transcript (idempotent: matched messages keep their ids and are replaced
  /// with the replayed, possibly longer, parts).
  ///
  /// No-ops while a turn is in flight, after the session ended, or when the
  /// runtime does not implement [AcpHistorySyncApi].
  Future<void> syncHistory() async {
    final runtime = _runtime;
    if (runtime is! AcpHistorySyncApi) return;
    if (_closing || isClosed) return;
    if (state.inTurn || state.phase == AcpChatPhase.ended) return;
    final inFlight = _historySyncInFlight;
    if (inFlight != null) return inFlight;
    final serial = _turnSerial;
    final syncRuntime = runtime as AcpHistorySyncApi;
    final future = _runHistorySync(syncRuntime, serial);
    _historySyncInFlight = future;
    try {
      await future;
    } finally {
      if (identical(_historySyncInFlight, future)) {
        _historySyncInFlight = null;
        _maybeFlushQueuedPrompt();
      }
    }
  }

  Future<void> _runHistorySync(AcpHistorySyncApi runtime, int serial) async {
    List<AcpSessionUpdate> updates;
    try {
      updates = await runtime.loadHistory();
    } on Object catch (error, stackTrace) {
      appLogger.w(
        '[acp-chat] session $sessionId history sync failed: $error',
        error: error,
        stackTrace: stackTrace,
      );
      return;
    }
    if (_closing || isClosed) return;
    if (serial != _turnSerial || state.inTurn) return;
    if (updates.isEmpty) return;
    _replayMessages = <AiMessage>[];
    _replayedBackgroundToolCalls.clear();
    List<AiMessage> rebuilt;
    try {
      for (final update in updates) {
        await _onUpdate(update);
      }
    } finally {
      rebuilt = _replayMessages ?? const <AiMessage>[];
      _replayMessages = null;
    }
    if (_closing || isClosed) return;
    if (serial != _turnSerial || state.inTurn) return;
    if (rebuilt.isEmpty) return;
    _noteBackgroundProgress(rebuilt);
    final merged = _mergeReplayedHistory(
      current: state.messages,
      replayed: rebuilt,
    );
    if (_messageShapeEqual(merged, state.messages)) return;
    emit(state.copyWith(messages: merged));
    unawaited(_persist());
  }

  /// Arms out-of-turn polling and the seat keep-alive after a turn that
  /// launched a background tool call. Idempotent while a watch is live.
  void _armBackgroundWatch() {
    if (_closing || isClosed) return;
    if (!_backgroundWorkActive) {
      _backgroundWorkActive = true;
      _backgroundFirstReplay = true;
      // Baseline is the live transcript's assistant text at `end_turn` (which
      // already includes the launch acknowledgement). The next replay must
      // only differ by text the agent wrote after the shell finished.
      _backgroundBaselineTextLen = _assistantTextLen(state.messages);
      _backgroundKnownBgIds.clear();
      _seatLeases?.acquireBackgroundTask(
        sessionId: sessionId,
        memberId: seatMemberId,
        leaseId: backgroundLeaseId,
        acquiredAt: DateTime.now(),
      );
    }
    _backgroundSyncStartedAt ??= DateTime.now();
    _scheduleBackgroundSyncTick();
  }

  /// Drains [AcpChatRuntimeState]'s background watch from a replay: a new
  /// background tool-call id means another task started (keep watching);
  /// otherwise new assistant text means the agent resumed because the shell
  /// finished, so the watch ends and the lease is released.
  void _noteBackgroundProgress(List<AiMessage> replayed) {
    if (!_backgroundWorkActive) return;
    final textLen = _assistantTextLen(replayed);
    final replayBgIds = _replayedBackgroundToolCalls;
    final newBgIds = replayBgIds.difference(_backgroundKnownBgIds);
    final baseline = _backgroundBaselineTextLen;

    if (_backgroundFirstReplay) {
      _backgroundFirstReplay = false;
      _backgroundKnownBgIds.addAll(replayBgIds);
      // One bg id is the task armed by this watch; more than one means the
      // agent already finished it and launched another before the first poll.
      if (replayBgIds.length > 1) {
        _backgroundBaselineTextLen = textLen;
        return;
      }
      if (baseline != null && textLen > baseline) _stopBackgroundSync();
      return;
    }

    if (newBgIds.isNotEmpty) {
      _backgroundKnownBgIds.addAll(newBgIds);
      _backgroundBaselineTextLen = textLen;
      return;
    }
    if (baseline == null) {
      _backgroundBaselineTextLen = textLen;
      return;
    }
    if (textLen > baseline) _stopBackgroundSync();
  }

  int _assistantTextLen(List<AiMessage> messages) {
    var total = 0;
    for (final message in messages) {
      if (message.role != AiRole.assistant) continue;
      for (final part in message.parts) {
        if (part is AiTextPart) total += part.text.length;
      }
    }
    return total;
  }

  void _scheduleBackgroundSyncTick() {
    if (_closing || isClosed || _backgroundSyncTimer != null) return;
    final started = _backgroundSyncStartedAt;
    if (started == null) return;
    if (DateTime.now().difference(started) >= backgroundSyncWindow) {
      _stopBackgroundSync();
      return;
    }
    _backgroundSyncTimer = Timer(_nextBackgroundSyncDelay(started), () {
      _backgroundSyncTimer = null;
      _onBackgroundSyncTick();
    });
  }

  Duration _nextBackgroundSyncDelay(DateTime started) {
    final override = _backgroundSyncInterval;
    if (override != null) return override;
    if (DateTime.now().difference(started) < _backgroundSyncFastWindow) {
      return _backgroundSyncFastInterval;
    }
    return _backgroundSyncSlowInterval;
  }

  void _onBackgroundSyncTick() {
    if (_closing || isClosed) {
      _stopBackgroundSync();
      return;
    }
    final started = _backgroundSyncStartedAt;
    if (started == null ||
        DateTime.now().difference(started) >= backgroundSyncWindow) {
      _stopBackgroundSync();
      return;
    }
    // A turn or an in-flight reconciliation owns the connection; retry later.
    unawaited(syncHistory().whenComplete(_scheduleBackgroundSyncTick));
  }

  void _stopBackgroundSync() {
    _backgroundSyncTimer?.cancel();
    _backgroundSyncTimer = null;
    _backgroundSyncStartedAt = null;
    if (!_backgroundWorkActive) return;
    _backgroundWorkActive = false;
    _backgroundBaselineTextLen = null;
    _backgroundKnownBgIds.clear();
    _seatLeases?.releaseBackgroundTask(
      sessionId: sessionId,
      memberId: seatMemberId,
      leaseId: backgroundLeaseId,
    );
  }

  /// Merges a full replay into [current] by locating the last live message.
  ///
  /// Appends only the replayed messages after that anchor; a matched anchor is
  /// replaced with the replayed parts so a truncated final message gains the
  /// text the app missed, while its local id/createdAt are preserved.
  List<AiMessage> _mergeReplayedHistory({
    required List<AiMessage> current,
    required List<AiMessage> replayed,
  }) {
    if (replayed.isEmpty || current.isEmpty) {
      return current.isEmpty ? replayed : current;
    }
    var lastIdx = -1;
    for (var i = current.length - 1; i >= 0; i--) {
      if (current[i].role != AiRole.system) {
        lastIdx = i;
        break;
      }
    }
    if (lastIdx < 0) return [...current, ...replayed];
    final anchor = current[lastIdx];
    var match = -1;
    for (var i = replayed.length - 1; i >= 0; i--) {
      if (_messagesMatch(anchor, replayed[i])) {
        match = i;
        break;
      }
    }
    if (match < 0) {
      // The replay does not contain the local tail (stale/foreign transcript);
      // keep app-only system rows ahead of the authoritative replay.
      final system = [
        for (final message in current)
          if (message.role == AiRole.system) message,
      ];
      return [...system, ...replayed];
    }
    final replacement = _mergeMatchedMessage(anchor, replayed[match]);
    return [
      ...current.sublist(0, lastIdx),
      replacement,
      ...replayed.sublist(match + 1),
      ...current.sublist(lastIdx + 1),
    ];
  }

  bool _messagesMatch(AiMessage current, AiMessage replayed) {
    if (current.role != replayed.role) return false;
    final currentText = _textOf(current);
    final replayedText = _textOf(replayed);
    switch (current.role) {
      case AiRole.user:
        return currentText == replayedText;
      case AiRole.assistant:
        if (currentText.isNotEmpty) {
          return replayedText.startsWith(currentText);
        }
        final currentTools = _toolIdsOf(current);
        final replayedTools = _toolIdsOf(replayed);
        if (currentTools.isNotEmpty) {
          return currentTools.every(replayedTools.contains);
        }
        final currentReasoning = _reasoningOf(current);
        if (currentReasoning.isNotEmpty) {
          return _reasoningOf(replayed).startsWith(currentReasoning);
        }
        return replayedTools.isEmpty && _reasoningOf(replayed).isEmpty;
      case AiRole.system:
        return false;
    }
  }

  AiMessage _mergeMatchedMessage(AiMessage current, AiMessage replayed) {
    // The replay is the authoritative agent-side view; it can only have more
    // or fresher parts than the live transcript for the matched message.
    if (replayed.parts.length < current.parts.length) return current;
    if (_messageShapeEqual([replayed], [current])) return current;
    return current.copyWith(parts: replayed.parts);
  }

  String _textOf(AiMessage message) => [
    for (final part in message.parts)
      if (part is AiTextPart) part.text,
  ].join();

  String _reasoningOf(AiMessage message) => [
    for (final part in message.parts)
      if (part is AiReasoningPart) part.text,
  ].join();

  Set<String> _toolIdsOf(AiMessage message) => {
    for (final part in message.parts)
      if (part is AiToolCallPart) part.toolCallId,
  };

  bool _messageShapeEqual(List<AiMessage> a, List<AiMessage> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id) return false;
      if (a[i].parts.length != b[i].parts.length) return false;
      for (var j = 0; j < a[i].parts.length; j++) {
        if (_partShape(a[i].parts[j]) != _partShape(b[i].parts[j])) {
          return false;
        }
      }
    }
    return true;
  }

  String _partShape(AiMessagePart part) => switch (part) {
    AiTextPart(:final text) => 'text:${text.hashCode}',
    AiReasoningPart(:final text) => 'reason:${text.hashCode}',
    AiToolCallPart(
      :final toolCallId,
      :final toolName,
      :final status,
      :final isError,
    ) =>
      'tool:$toolCallId:$toolName:${status.name}:$isError',
  };

  void _onPermissionRequest(AgentPermissionRequest request) {
    _onClientRequest(AcpPendingPermission(request));
  }

  void _onClientRequest(AcpPendingClientRequest pending) {
    if (_closing || isClosed || state.phase == AcpChatPhase.ended) return;
    emit(state.copyWith(pendingClient: pending));
    _applyAttention(const AgentStatusEvent(state: AgentSeatAttention.waiting));
  }

  // ----- helpers -----

  AiMessage _userMessage(String text) => AiMessage(
    id: 'acp-u-${_uuid.v4()}',
    role: AiRole.user,
    parts: [AiTextPart(text: text)],
    createdAt: DateTime.now(),
  );

  /// Appends parts onto the tip assistant message (streaming continuation),
  /// or opens a new assistant message when the tip is not appendable.
  ///
  /// Consecutive [AiTextPart] / [AiReasoningPart] of the same type are
  /// concatenated. ACP streams one NDJSON chunk per token; appending each as
  /// its own part makes the UI render hundreds of thinking-process steps.
  ///
  /// Always re-emits the derived turn activity: a chunk that carries no
  /// visible text is dropped as an empty stream part but must still move the
  /// status from thinking to generating.
  void _appendMessageParts(List<AiMessagePart> parts) {
    final replaying = _replayMessages != null;
    final incoming = [
      for (final part in parts)
        if (!_isEmptyStreamPart(part)) part,
    ];
    final activity = replaying ? AcpChatActivity.none : _turnActivity();
    if (incoming.isEmpty) {
      if (replaying || activity == state.activity) return;
      emit(state.copyWith(activity: activity));
      return;
    }
    final messages = [...(_replayMessages ?? state.messages)];
    if (messages.isNotEmpty && messages.last.role == AiRole.assistant) {
      final tip = messages.last;
      messages[messages.length - 1] = tip.copyWith(
        parts: _coalesceStreamingParts(tip.parts, incoming),
      );
    } else {
      messages.add(
        AiMessage(
          id: 'acp-a-${_uuid.v4()}',
          role: AiRole.assistant,
          parts: _coalesceStreamingParts(const [], incoming),
          createdAt: DateTime.now(),
        ),
      );
    }
    if (replaying) {
      _replayMessages = messages;
      return;
    }
    emit(state.copyWith(messages: messages, activity: activity));
  }

  /// Merges a replayed `user_message_chunk` into the replay buffer.
  ///
  /// Unlike live chunks, replay chunks carry both roles; a user chunk opens (or
  /// continues) a user message so the assistant chunks that follow do not get
  /// appended onto the previous assistant bubble.
  void _appendReplayUserChunk(String text) {
    final messages = _replayMessages;
    if (messages == null || text.isEmpty) return;
    if (messages.isNotEmpty && messages.last.role == AiRole.user) {
      final tip = messages.last;
      messages[messages.length - 1] = tip.copyWith(
        parts: _coalesceStreamingParts(tip.parts, [AiTextPart(text: text)]),
      );
      return;
    }
    messages.add(_userMessage(text));
  }

  static bool _isEmptyStreamPart(AiMessagePart part) => switch (part) {
    AiTextPart(:final text) => text.isEmpty,
    AiReasoningPart(:final text) => text.isEmpty,
    _ => false,
  };

  static List<AiMessagePart> _coalesceStreamingParts(
    List<AiMessagePart> existing,
    List<AiMessagePart> incoming,
  ) {
    final out = [...existing];
    for (final part in incoming) {
      if (out.isEmpty) {
        out.add(part);
        continue;
      }
      final merged = _mergeStreamParts(out.last, part);
      if (merged != null) {
        out[out.length - 1] = merged;
      } else {
        out.add(part);
      }
    }
    return out;
  }

  static AiMessagePart? _mergeStreamParts(AiMessagePart a, AiMessagePart b) {
    if (a is AiTextPart && b is AiTextPart) {
      return AiTextPart(text: '${a.text}${b.text}');
    }
    if (a is AiReasoningPart && b is AiReasoningPart) {
      return AiReasoningPart(text: '${a.text}${b.text}');
    }
    return null;
  }

  void _applyAttention(AgentStatusEvent event) {
    _attention?.applyEvent(
      sessionId: sessionId,
      memberId: seatMemberId,
      event: event,
      skipPermissions: false,
    );
  }

  bool _isAuthNoticeMessage(AiMessage message) {
    final text = _strings?.notLoggedIn ?? defaultAcpChatStrings.notLoggedIn;
    return message.role == AiRole.system &&
        message.parts.any((p) => p is AiTextPart && p.text == text);
  }

  /// Drops the handshake "not logged in" row once the agent is actually
  /// authenticated or has started streaming (the CLI probe can report `none`
  /// while session OAuth in CLAUDE_CONFIG_DIR still works).
  void _removeAuthNoticeMessage() {
    if (!state.messages.any(_isAuthNoticeMessage)) return;
    emit(
      state.copyWith(
        messages: [
          for (final message in state.messages)
            if (!_isAuthNoticeMessage(message)) message,
        ],
      ),
    );
  }

  /// Appends a standalone system message (turn errors, lifecycle notices).
  void _appendSystemMessage(String text) {
    emit(
      state.copyWith(
        messages: [
          ...state.messages,
          AiMessage(
            id: 'acp-sys-${_uuid.v4()}',
            role: AiRole.system,
            parts: [AiTextPart(text: text)],
            createdAt: DateTime.now(),
          ),
        ],
      ),
    );
  }

  List<AiMessage> _messagesForDisk() {
    final error = state.error;
    if (error == null || error.kind != AcpChatErrorKind.processExited) {
      return state.messages;
    }
    return [
      for (final message in state.messages)
        if (!(message.role == AiRole.system &&
            message.parts.whereType<AiTextPart>().map((p) => p.text).join() ==
                error.message))
          message,
    ];
  }

  Future<void> _persist() async {
    if (!_allowPersist) return;
    final transcript = _transcript;
    if (transcript == null) return;
    try {
      await transcript.saveMessages(_messagesForDisk());
    } on Object catch (error, stackTrace) {
      appLogger.e(
        '[acp-chat] persist failed session=$sessionId: $error',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  void _endWith(AcpChatErrorKind kind, String message) {
    if (_closing || isClosed) return;
    _stopBackgroundSync();
    _queuedPrompt = null;
    _resetTurnTrackers();
    _applyAttention(const AgentStatusEvent(state: AgentSeatAttention.done));
    _appendSystemMessage(message);
    emit(
      state.copyWith(
        phase: AcpChatPhase.ended,
        inTurn: false,
        pendingClient: null,
        error: AcpChatError(kind: kind, message: message),
        activity: AcpChatActivity.none,
        modelState: null,
      ),
    );
    if (kind != AcpChatErrorKind.processExited) {
      unawaited(_persist());
    }
  }
}
