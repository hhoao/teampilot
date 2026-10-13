import 'dart:async';

import 'package:acpd/acpd.dart' as acpd;
import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';

import '../../../models/team_config.dart';
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
import '../../../services/chat/team_bus/teammate_bus_permission.dart';

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

  AcpChatRuntimeState copyWith({
    AcpChatPhase? phase,
    List<AiMessage>? messages,
    bool? inTurn,
    Object? pendingClient = _unset,
    AcpChatError? error,
    bool clearError = false,
    AcpChatActivity? activity,
    bool? historyHydrated,
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
  }) : _runtime = runtime,
       _attention = attention,
       _transcript = transcript,
       super(const AcpChatRuntimeState());

  /// Synthetic seat member id — an ACP session has exactly one member, the
  /// agent (mirrors [AcpAgentSession]'s permission hold seat).
  static const acpMemberId = 'acp';

  static const _uuid = Uuid();

  final AcpSessionRuntimeApi _runtime;
  final String sessionId;
  final CliTool tool;
  final String seatMemberId;
  final AgentAttentionPort? _attention;
  final AcpChatTranscriptWriter? _transcript;

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
  }

  /// Injects localized copy; must run before [start].
  void ensureStrings(AcpChatStrings strings) => _strings ??= strings;

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
  }) async {
    if (state.phase != AcpChatPhase.launching) return;
    _hydrateInFlight ??= _hydrateTranscript();
    await _hydrateInFlight;
    if (_closing || isClosed) return;
    try {
      await _runtime.start(
        tool: tool,
        executable: executable,
        sessionToolDir: sessionToolDir,
        workingDirectory: workingDirectory,
        baseEnv: baseEnv,
        mcpServers: mcpServers,
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
    emit(state.copyWith(phase: AcpChatPhase.ready));
    final queued = _queuedPrompt;
    _queuedPrompt = null;
    if (queued != null && queued.serial == _turnSerial) {
      // Flush before replaying handshake auth so a CLI probe `none` cannot
      // land as the first row ahead of the user's already-visible bubble.
      _dispatchPrompt(queued.text, queued.serial);
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
    if (state.phase == AcpChatPhase.launching || !_runtime.isStarted) {
      _queuedPrompt = (text: trimmed, serial: serial);
      _showUserMessage(trimmed);
      _resetTurnTrackers();
      emit(state.copyWith(inTurn: true, activity: AcpChatActivity.thinking));
      return true;
    }
    _dispatchPrompt(trimmed, serial);
    return true;
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
    _turnSerial++;
    _queuedPrompt = null;
    if (!isClosed) emit(state.copyWith(pendingClient: null));
    if (!_runtime.isStarted) {
      _clearInTurnKeepingPhase();
      unawaited(_persist());
      return;
    }
    _runtime.cancel();
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
    switch (update) {
      case AcpMessageChunk():
        if (isClosed) return;
        _removeAuthNoticeMessage();
        _seenChunkThisTurn = true;
        _appendMessageParts(_chunkParts(update));
      case AcpToolCallUpdate():
        if (isClosed) return;
        _applyToolCall(update);
        unawaited(_persist());
      case AcpPlan():
        // Plan updates have no chat-layer rendering yet (spec: recorded but
        // no mode-switching UI ships).
        break;
      case AcpStop():
        if (isClosed) return;
        _onStop(update);
      case AcpAuthNotice():
        if (isClosed) return;
        // `_auth/status_update` is reporting-only. `kind: none` comes from an
        // async `claude auth status --json` probe at initialize / prompt start
        // and is not a confirmed TeamPilot logout — session OAuth under
        // CLAUDE_CONFIG_DIR can still succeed. Never turn that probe into a
        // chat row. A later logged-in notice still drops a stale banner.
        if (update.loggedIn) {
          _removeAuthNoticeMessage();
        }
      case AcpTodoListUpdate() || AcpTaskUpdate() || AcpGeneratedImageUpdate():
        if (isClosed) return;
        emit(
          state.copyWith(
            messages: foldAcpExtensionNotification(
              messages: state.messages,
              update: update,
              newId: () => 'acp-a-${_uuid.v4()}',
            ),
          ),
        );
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
    final activity = _turnActivity();
    // Upsert onto the last assistant message's matching tool part; a new
    // toolCallId appends a fresh part (tool card).
    final messages = [...state.messages];
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
          );
          matched = true;
          break;
        }
      }
      if (matched) {
        messages[i] = message.copyWith(parts: parts);
        emit(state.copyWith(messages: messages, activity: activity));
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
            ),
          ],
        );
        emit(state.copyWith(messages: messages, activity: activity));
        return;
      }
    }
    // No assistant message to attach to — start one.
    _appendMessageParts([
      AiToolCallPart(
        toolCallId: update.toolCallId,
        toolName: update.title ?? update.toolCallId,
        status: _mapToolStatus(update.status) ?? AiToolCallStatus.incomplete,
      ),
    ]);
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
        final prefix = _strings?.turnFailed ?? 'Turn failed';
        final text = stop.message == null || stop.message!.isEmpty
            ? prefix
            : '$prefix: ${stop.message}';
        _appendSystemMessage(text);
        unawaited(_persist());
        _endTurn();
    }
  }

  void _endTurn() {
    if (_closing || isClosed) return;
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
  }

  void _onPermissionRequest(AgentPermissionRequest request) {
    if (isTeammateBusPermissionRequest(request)) {
      unawaited(_autoAllowTeammateBus(request));
      return;
    }
    _onClientRequest(AcpPendingPermission(request));
  }

  /// TeamPilot installed teammate-bus; Cursor ACP still asks via
  /// `session/request_permission` before `read_messages` / `send_message`.
  /// Auto-allow so mixed collaboration is not blocked on a host-owned MCP.
  Future<void> _autoAllowTeammateBus(AgentPermissionRequest request) async {
    if (_closing || isClosed || state.phase == AcpChatPhase.ended) return;
    final always = request.always.isEmpty ? null : request.always.first;
    final kind = always == null
        ? AgentPermissionReplyKind.allowOnce
        : AgentPermissionReplyKind.always;
    appLogger.i(
      '[acp-chat] session $sessionId auto-allow teammate-bus '
      '${request.description}',
    );
    await _runtime.answerPermission(kind, always: always);
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
    final incoming = [
      for (final part in parts)
        if (!_isEmptyStreamPart(part)) part,
    ];
    final activity = _turnActivity();
    if (incoming.isEmpty) {
      if (activity == state.activity) return;
      emit(state.copyWith(activity: activity));
      return;
    }
    final messages = [...state.messages];
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
    emit(state.copyWith(messages: messages, activity: activity));
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
      ),
    );
    if (kind != AcpChatErrorKind.processExited) {
      unawaited(_persist());
    }
  }
}
