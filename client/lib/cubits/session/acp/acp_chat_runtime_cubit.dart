import 'dart:async';

import 'package:acpd/acpd.dart' as acpd;
import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';

import '../../../models/team_config.dart';
import '../../../services/acp/acp_agent_session_store.dart';
import '../../../services/acp/acp_agent_translator.dart';
import '../../../services/acp/acp_background_liveness.dart';
import '../../../services/acp/acp_background_transcript.dart';
import '../../../services/acp/acp_chat_extension_fold.dart';
import '../../../services/acp/acp_chat_strings.dart';
import '../../../services/acp/acp_chat_transcript.dart';
import '../../../services/acp/acp_chat_transcript_replay.dart';
import '../../../services/acp/acp_client_extensions.dart';
import '../../../services/acp/acp_model_ref.dart';
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
    this.launchProvider = '',
    this.launchModel = '',
    this.onUserActivity,
    AgentAttentionPort? attention,
    AcpChatTranscriptWriter? transcript,
    AcpAgentSessionStore? agentSession,
    SeatBackgroundLeasePort? seatLeases,
    AcpBackgroundTranscriptSourceFactory? backgroundTranscriptFactory,
    AcpBackgroundLivenessProbeFactory? backgroundLivenessFactory,
    Duration? backgroundSyncInterval,
    this.backgroundSyncWindow = defaultBackgroundSyncWindow,
  }) : _runtime = runtime,
       _attention = attention,
       _transcript = transcript,
       _agentSession = agentSession,
       _seatLeases = seatLeases,
       _backgroundTranscriptFactory = backgroundTranscriptFactory,
       _backgroundLivenessFactory = backgroundLivenessFactory,
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

  /// Poll cadence while the agent's own transcript is readable: each tick is a
  /// stat plus (when it grew) the appended bytes, so it can stay responsive
  /// without replaying the session over the protocol. Long waits back off to
  /// the slow cadence — a background shell can run for the whole window.
  static const _backgroundTranscriptInterval = Duration(seconds: 2);
  static const _backgroundTranscriptSlowInterval = Duration(seconds: 10);

  static const _uuid = Uuid();

  final AcpSessionRuntimeApi _runtime;
  final String sessionId;
  final CliTool tool;
  final String seatMemberId;

  /// Launch identity persisted on the session (provider row + model ref).
  ///
  /// Applied to the agent once after [start]: OpenCode v2 ignores
  /// `opencode.json`'s `model` for ACP sessions, so without this a restart
  /// silently falls back to the agent's default model.
  final String launchProvider;
  final String launchModel;

  /// Bumps the session's `updatedAt` when the operator submits a prompt, so
  /// the conversation list's relative time and `recentlyUpdated` order move
  /// like the PTY path (which touches on every user line). Null in tests.
  final void Function(String sessionId)? onUserActivity;

  final AgentAttentionPort? _attention;
  final AcpChatTranscriptWriter? _transcript;
  final AcpAgentSessionStore? _agentSession;
  final SeatBackgroundLeasePort? _seatLeases;
  final AcpBackgroundTranscriptSourceFactory? _backgroundTranscriptFactory;
  final AcpBackgroundLivenessProbeFactory? _backgroundLivenessFactory;

  /// Polls the agent's own metadata for out-of-turn work, built once the agent
  /// session id is known. Null when this CLI keeps no readable evidence.
  AcpBackgroundLivenessProbe? _backgroundLiveness;

  /// Incremental reader of the agent's own transcript, built once the agent
  /// session id is known. Null when this CLI keeps no readable transcript.
  AcpBackgroundTranscriptSource? _backgroundTranscript;

  /// Whether the last transcript read located the file. Only then may the
  /// watch tick at the transcript cadence — a bound source whose file is
  /// missing must keep the slow `session/load` cadence.
  bool _backgroundTranscriptActive = false;

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

  /// The launch-time reconcile was skipped because the first prompt arrived
  /// before the handshake finished. Run it once that turn ends (or the queued
  /// prompt is cancelled) instead of blocking the turn behind `session/load`.
  bool _reconcileAfterTurn = false;

  /// Out-of-turn history polling: armed by a background tool call, disarmed
  /// when the session closes, the completion is observed, or
  /// [backgroundSyncWindow] elapses.
  Timer? _backgroundSyncTimer;
  DateTime? _backgroundSyncStartedAt;

  /// A background tool call was opened during the live turn in progress.
  /// [endTurn] arms the watch when this is set.
  bool _turnHadBackgroundToolCall = false;

  /// Cursor child agents still running after the parent tool returned.
  /// Keyed by `subagentSessionId`. Empty values mean "alive, no label yet".
  final Map<String, String> _liveSubagents = {};

  /// Every Cursor child spawned this watch has already reported a terminal
  /// state. Stops [endTurn] from arming a lease for work that already finished.
  bool _cursorSubagentsSettled = false;

  /// Human-readable description of the background tool call opened this turn,
  /// surfaced on the seat lease so the sidebar can say what is still running.
  String? _turnBackgroundLabel;

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
    _turnBackgroundLabel = null;
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

  /// Aligns the just-opened agent with the session's persisted launch model.
  ///
  /// The CLI config is not authoritative for every agent (OpenCode v2 ignores
  /// `opencode.json`'s `model` in ACP mode), so the launch identity is applied
  /// explicitly. A model the agent does not advertise is left alone: the seat
  /// keeps the agent's own selection rather than failing the launch.
  Future<void> _applyLaunchModel() async {
    if (launchModel.trim().isEmpty) return;
    final modelRuntime = _runtime is AcpModelSwitchApi
        ? _runtime as AcpModelSwitchApi
        : null;
    final state = modelRuntime?.modelState;
    if (state == null) return;
    final target = acpModelIdForLaunchRef(
      state: state,
      provider: launchProvider,
      model: launchModel,
    );
    if (target == null || target == state.currentId) return;
    try {
      await modelRuntime!.setModel(target);
      appLogger.d('[acp-chat] session $sessionId applied launch model $target');
    } on Object catch (error) {
      appLogger.w(
        '[acp-chat] session $sessionId launch model $target failed: $error',
      );
    }
  }

  /// Spawns the agent and opens the ACP session.
  ///
  /// On success: subscribes to updates + permissions (before any prompt),
  /// stamps the attention seat idle, and moves to [AcpChatPhase.ready].
  /// On [AcpLaunchException]: inline system message + ended phase.
  /// [AcpAuthenticateException] and authenticate [TimeoutException] use
  /// not-logged-in copy. [acpd.RpcError] from `session/new` uses
  /// session-open-failed copy plus the agent's nested reason when present,
  /// except auth-required (`-32000`) which uses not-logged-in copy.
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
      // AUTH-required from `session/new` is a sign-in problem, not a broken
      // session: surface the same copy as a failed `authenticate` (all ACP
      // CLIs share -32000).
      if (error.code == acpd.ErrorCode.authRequired.code) {
        _endWith(
          AcpChatErrorKind.launchFailed,
          _strings?.notLoggedIn ?? defaultAcpChatStrings.notLoggedIn,
        );
        return;
      }
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
      _bindBackgroundProbes(sessionToolDir: sessionToolDir, agentId: liveId);
    }
    await _applyLaunchModel();
    emit(
      state.copyWith(phase: AcpChatPhase.ready, modelState: _readModelState()),
    );
    final queued = _queuedPrompt;
    _queuedPrompt = null;
    if (queued != null && queued.serial == _turnSerial) {
      // Flush before replaying handshake auth so a CLI probe `none` cannot
      // land as the first row ahead of the user's already-visible bubble.
      // The prompt owns the connection: a launch reconcile here would take the
      // update stream (`session/load` buffers instead of emitting) and park
      // the turn behind the replay. Defer it to the end of this turn.
      _reconcileAfterTurn = true;
      _dispatchPrompt(queued.text, queued.serial);
    } else {
      // A resumed session may have finished out-of-turn work after the last
      // live update; reconcile once so the reopening UI is not stale.
      _reconcileAfterTurn = false;
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
    onUserActivity?.call(sessionId);
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
      // No turn will end, so the deferred launch reconcile has to run here.
      unawaited(_runDeferredHistorySync());
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
    emit(
      state.copyWith(
        inTurn: false,
        pendingClient: null,
        activity: AcpChatActivity.none,
      ),
    );
    _applyAttention(const AgentStatusEvent(state: AgentSeatAttention.done));
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
      case AcpUsageUpdate():
        // Context usage is recorded out-of-band for the usage collector; it
        // never becomes a chat row. A history replay re-sends the session's
        // updates, and appending those would mint fresh sequence ids for
        // already-captured samples (duplicates the collector cannot dedupe),
        // so only live updates are persisted.
        if (!replaying) unawaited(_appendUsage(update));
      case AcpSubagentUpdate():
        if (isClosed || replaying) return;
        _applySubagent(update);
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

  /// Persists one context-usage sample beside the chat transcript.
  ///
  /// Fire-and-forget: a failed append must never disturb the turn, so it is
  /// logged and dropped.
  Future<void> _appendUsage(AcpUsageUpdate update) async {
    final transcript = _transcript;
    if (transcript == null) return;
    try {
      await transcript.appendUsage(
        sessionId: sessionId,
        used: update.used,
        size: update.size,
        cost: update.cost,
        model: _readModelState()?.currentId,
      );
    } on Object catch (error, stackTrace) {
      appLogger.w(
        '[acp-chat] session $sessionId usage append failed: $error',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  void _applyToolCall(AcpToolCallUpdate update) {
    final replaying = _replayMessages != null;
    // Cursor's Task tool reports the background launch as a *completed*
    // update whose result is `{isBackground: true}` — the child is still
    // running, the parent tool is not.
    final launchesBackground =
        update.background &&
        (update.status == AcpToolCallStatus.pending ||
            update.status == AcpToolCallStatus.inProgress ||
            update.status == AcpToolCallStatus.completed);
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
      if (launchesBackground && !_cursorSubagentsSettled) {
        _turnHadBackgroundToolCall = true;
        _cursorSubagentsSettled = false;
        _turnBackgroundLabel = _backgroundLabelOf(update);
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
    final backgroundLabel = _turnBackgroundLabel;
    _resetTurnTrackers();
    emit(
      state.copyWith(
        inTurn: false,
        phase: AcpChatPhase.idle,
        pendingClient: null,
        activity: AcpChatActivity.none,
      ),
    );
    // Attention done after inTurn is false so sync consumers (and ChatCubit's
    // attention-driven sessionActivities recompute) do not read a stale turn.
    _applyAttention(const AgentStatusEvent(state: AgentSeatAttention.done));
    // The turn is over but a background shell it launched is still running:
    // ACP goes silent, so watch the agent's history and hold the seat lease so
    // the UI shows "background work running" instead of `done`.
    if (_backgroundWorkActive) {
      // Text the just-finished turn produced arrived live and is already in the
      // transcript, so it must not be read as out-of-turn progress (a follow-up
      // prompt sent while a background task runs would otherwise end the watch).
      _backgroundBaselineTextLen = _assistantTextLen(state.messages);
    }
    if (_reconcileAfterTurn) {
      // [start] skipped the launch reconcile because the first prompt owned the
      // connection. Run it now that the turn is over, and arm a background
      // watch only after it settles: the reconcile replays pre-attach work, and
      // doing it after the arm would read that text as the watched task ending.
      unawaited(
        _runDeferredHistorySync().whenComplete(() {
          if (_closing || isClosed) return;
          if (hadBackground &&
              !_cursorSubagentsSettled &&
              !_backgroundWorkActive) {
            _armBackgroundWatch(label: backgroundLabel);
          }
        }),
      );
      return;
    }
    if (hadBackground && !_cursorSubagentsSettled) {
      _armBackgroundWatch(label: backgroundLabel);
    }
  }

  /// Tracks a Cursor child agent so the session stays visibly running after
  /// the parent turn ends, and drops that signal once the child finishes.
  void _applySubagent(AcpSubagentUpdate update) {
    final id = update.subagentSessionId;
    if (update.terminal) {
      if (!_liveSubagents.containsKey(id)) return;
      _liveSubagents.remove(id);
      if (_liveSubagents.isNotEmpty) {
        _armBackgroundWatch(label: _liveSubagentLabel());
        return;
      }
      _cursorSubagentsSettled = true;
      _turnHadBackgroundToolCall = false;
      _stopBackgroundSync();
      return;
    }
    final label = _subagentLabel(update);
    _liveSubagents[id] = label ?? _liveSubagents[id] ?? '';
    _cursorSubagentsSettled = false;
    if (_replayMessages != null) return;
    if (state.inTurn) {
      _turnHadBackgroundToolCall = true;
      if (label != null && label.isNotEmpty) _turnBackgroundLabel = label;
      return;
    }
    _armBackgroundWatch(label: label ?? _liveSubagentLabel());
  }

  String? _subagentLabel(AcpSubagentUpdate update) {
    final task = update.task?.trim();
    if (task != null && task.isNotEmpty) return task;
    final name = update.name?.trim();
    if (name != null && name.isNotEmpty) return name;
    return null;
  }

  String? _liveSubagentLabel() {
    for (final label in _liveSubagents.values) {
      final trimmed = label.trim();
      if (trimmed.isNotEmpty) return trimmed;
    }
    return _turnBackgroundLabel;
  }

  /// Runs the launch reconcile that [start] skipped for a queued first prompt.
  ///
  /// Only fires once per skipped launch, and only when nothing else owns the
  /// connection: [syncHistory] itself no-ops while a turn is in flight or when
  /// a reconcile is already running.
  Future<void> _runDeferredHistorySync() {
    _reconcileAfterTurn = false;
    return syncHistory();
  }

  // ----- out-of-turn history reconciliation -----

  /// Reconciles the agent's own record of the session with the app transcript.
  ///
  /// ACP v1 sends no `session/update` after a turn ends, so the agent's
  /// summary of out-of-turn work only exists on the agent side. When the CLI
  /// keeps a readable transcript ([AcpBackgroundTranscriptSource]) only the
  /// appended records are parsed; otherwise this replays the session through
  /// `session/load` (idempotent: matched messages keep their ids and are
  /// replaced with the replayed, possibly longer, parts).
  ///
  /// No-ops while a turn is in flight, after the session ended, or when
  /// neither a transcript nor [AcpHistorySyncApi] is available.
  Future<void> syncHistory() async {
    final runtime = _runtime;
    if (runtime is! AcpHistorySyncApi && _backgroundTranscript == null) return;
    if (_closing || isClosed) return;
    if (state.inTurn || state.phase == AcpChatPhase.ended) return;
    final inFlight = _historySyncInFlight;
    if (inFlight != null) return inFlight;
    final serial = _turnSerial;
    final future = _runHistorySync(runtime, serial);
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

  Future<void> _runHistorySync(AcpSessionRuntimeApi runtime, int serial) async {
    final transcript = _backgroundTranscript;
    if (transcript != null && await _tryTranscriptSync(transcript, serial)) {
      return;
    }
    // [AcpHistorySyncApi] is a sibling interface, not a supertype of
    // [AcpSessionRuntimeApi] — an `is` check alone cannot promote here.
    if (runtime is! AcpHistorySyncApi) return;
    final historySync = runtime as AcpHistorySyncApi;

    List<AcpSessionUpdate> updates;
    try {
      updates = await historySync.loadHistory();
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

  /// Binds the optional out-of-turn evidence sources once the agent session id
  /// is known: the transcript tail reader (Claude) and the liveness probe
  /// (Cursor), both scoped to the CLI's isolated config dir.
  void _bindBackgroundProbes({
    required String sessionToolDir,
    required String agentId,
  }) {
    _bindBackgroundTranscript(
      sessionToolDir: sessionToolDir,
      agentId: agentId,
    );
    if (_backgroundLiveness != null) return;
    final livenessFactory = _backgroundLivenessFactory;
    if (livenessFactory == null) return;
    try {
      _backgroundLiveness = livenessFactory(
        sessionToolDir: sessionToolDir,
        sessionId: agentId,
      );
    } on Object catch (error, stackTrace) {
      appLogger.w(
        '[acp-chat] session $sessionId liveness probe failed: $error',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  void _bindBackgroundTranscript({
    required String sessionToolDir,
    required String agentId,
  }) {
    if (_backgroundTranscript != null) return;
    final factory = _backgroundTranscriptFactory;
    if (factory == null) return;
    try {
      _backgroundTranscript = factory(
        sessionToolDir: sessionToolDir,
        sessionId: agentId,
      );
    } on Object catch (error, stackTrace) {
      appLogger.w(
        '[acp-chat] session $sessionId transcript source failed: $error',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  /// Reads the agent's transcript incrementally.
  ///
  /// Returns false when this session has no readable transcript (the caller
  /// then reconciles through `session/load`), true when the reconcile is done
  /// — including the common "nothing changed" tick.
  Future<bool> _tryTranscriptSync(
    AcpBackgroundTranscriptSource source,
    int serial,
  ) async {
    AcpBackgroundTranscriptResult? result;
    try {
      result = await source.refresh();
    } on Object catch (error, stackTrace) {
      appLogger.w(
        '[acp-chat] session $sessionId transcript sync failed: $error',
        error: error,
        stackTrace: stackTrace,
      );
      return false;
    }
    if (result == null) {
      // The source could not locate the file: keep the slow protocol cadence
      // so a capability mismatch never turns into a 2 s replay loop.
      _backgroundTranscriptActive = false;
      return false;
    }
    _backgroundTranscriptActive = true;
    if (_closing || isClosed) return true;
    if (serial != _turnSerial || state.inTurn) return true;
    if (!result.changed || result.messages.isEmpty) return true;
    _replayedBackgroundToolCalls
      ..clear()
      ..addAll(_backgroundToolCallIdsOf(result.messages));
    _noteBackgroundProgress(result.messages);
    final merged = _mergeReplayedHistory(
      current: state.messages,
      replayed: result.messages,
    );
    if (_messageShapeEqual(merged, state.messages)) return true;
    emit(state.copyWith(messages: merged));
    unawaited(_persist());
    return true;
  }

  /// A short description of a background tool call, preferring the tool's own
  /// `description` (Cursor / Claude Shell) and falling back to its title.
  String? _backgroundLabelOf(AcpToolCallUpdate update) {
    final description = update.args?['description'];
    if (description is String && description.trim().isNotEmpty) {
      return description.trim();
    }
    final title = update.title?.trim();
    return (title == null || title.isEmpty) ? null : title;
  }

  /// True when the tool part launched work that outlives the parent turn.
  ///
  /// Cursor Task puts `isBackground` on the result, not the args.
  bool _toolPartIsBackground(AiToolCallPart part) {
    final args = part.args;
    if (args != null &&
        (args['run_in_background'] == true || args['background'] == true)) {
      return true;
    }
    final result = part.result;
    return result is Map && result['isBackground'] == true;
  }

  /// Background tool-call ids carried by transcript messages, so the
  /// multi-task heuristic in [_noteBackgroundProgress] works without an ACP
  /// replay buffer.
  Set<String> _backgroundToolCallIdsOf(List<AiMessage> messages) {
    final ids = <String>{};
    for (final message in messages) {
      for (final part in message.parts) {
        if (part is! AiToolCallPart) continue;
        if (!_toolPartIsBackground(part)) continue;
        ids.add(part.toolCallId);
      }
    }
    return ids;
  }

  /// Arms the out-of-turn watch and the seat keep-alive after a turn that
  /// launched a background tool call. Idempotent while a watch is live.
  /// Ticks read the agent transcript when one is bound, else replay history.
  void _armBackgroundWatch({String? label}) {
    if (_closing || isClosed) return;
    if (!_backgroundWorkActive) {
      _backgroundWorkActive = true;
      _backgroundFirstReplay = true;
      // Baseline is the live transcript's assistant text at `end_turn` (which
      // already includes the launch acknowledgement). The next replay must
      // only differ by text the agent wrote after the shell finished.
      _backgroundBaselineTextLen = _assistantTextLen(state.messages);
      _backgroundKnownBgIds.clear();
    }
    _seatLeases?.acquireBackgroundTask(
      sessionId: sessionId,
      memberId: seatMemberId,
      leaseId: backgroundLeaseId,
      acquiredAt: DateTime.now(),
      label: label ?? _liveSubagentLabel(),
    );
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
      if (baseline != null && textLen > baseline && _liveSubagents.isEmpty) {
        _stopBackgroundSync();
      }
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
    if (textLen > baseline && _liveSubagents.isEmpty) _stopBackgroundSync();
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
    if (_backgroundTranscriptActive) {
      return DateTime.now().difference(started) < _backgroundSyncFastWindow
          ? _backgroundTranscriptInterval
          : _backgroundTranscriptSlowInterval;
    }
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
    unawaited(_runBackgroundSyncTick(started));
  }

  Future<void> _runBackgroundSyncTick(DateTime started) async {
    // The agent's own on-disk evidence is authoritative: Cursor never reports a
    // background child's completion over ACP, so waiting for replayed text
    // would hold the lease for the whole window after the work is already gone.
    if (await _backgroundWorkSettled(started)) return;
    if (_closing || isClosed) {
      _stopBackgroundSync();
      return;
    }
    // A turn or an in-flight reconciliation owns the connection; retry later.
    try {
      await syncHistory();
    } finally {
      _scheduleBackgroundSyncTick();
    }
  }

  /// Releases the lease when the liveness probe proves the out-of-turn work is
  /// over. Returns whether the watch was stopped.
  Future<bool> _backgroundWorkSettled(DateTime started) async {
    final probe = _backgroundLiveness;
    if (probe == null || !_backgroundWorkActive) return false;
    final verdict = await probe.probe(since: started);
    if (verdict != AcpBackgroundLiveness.idle) return false;
    if (_closing || isClosed || !_backgroundWorkActive) return false;
    // A child tracked from protocol frames outranks the disk probe.
    if (_liveSubagents.isNotEmpty) return false;
    _stopBackgroundSync();
    return true;
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
      // The replay does not contain the local tail (stale/foreign transcript).
      // Keep app-only system rows, and reuse the local identity of every
      // replayed message that still corresponds to one on screen: the replay
      // is authoritative for content, but minting fresh ids for messages the
      // user can already see rebuilds every bubble in the virtualized thread.
      final system = [
        for (final message in current)
          if (message.role == AiRole.system) message,
      ];
      return [
        ...system,
        ..._alignReplayMessages(current: current, replayed: replayed),
      ];
    }
    final replacement = _mergeMatchedMessage(anchor, replayed[match]);
    return [
      ...current.sublist(0, lastIdx),
      replacement,
      ...replayed.sublist(match + 1),
      ...current.sublist(lastIdx + 1),
    ];
  }

  /// Greedy forward alignment for a replay without a matching tail anchor.
  ///
  /// Walks both lists in order: a replayed message that matches a remaining
  /// local message reuses that message's id/createdAt (with the fresher
  /// replayed parts); everything else is genuinely new and keeps the replay's
  /// id. Lookahead is bounded: a local divergence can shift the two lists by a
  /// few rows, but scanning arbitrarily far for every replayed message turns a
  /// long transcript into an O(n²) string comparison pass.
  List<AiMessage> _alignReplayMessages({
    required List<AiMessage> current,
    required List<AiMessage> replayed,
  }) {
    final used = <int>{};
    var cursor = 0;
    final aligned = <AiMessage>[];
    for (final message in replayed) {
      var match = -1;
      final limit = cursor + 24 < current.length ? cursor + 24 : current.length;
      for (var i = cursor; i < limit; i++) {
        if (used.contains(i)) continue;
        if (!_messagesMatch(current[i], message)) continue;
        match = i;
        break;
      }
      if (match < 0) {
        aligned.add(message);
        continue;
      }
      used.add(match);
      cursor = match + 1;
      aligned.add(_mergeMatchedMessage(current[match], message));
    }
    return aligned;
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
    _applyAttention(const AgentStatusEvent(state: AgentSeatAttention.done));
    if (kind != AcpChatErrorKind.processExited) {
      unawaited(_persist());
    }
  }
}
