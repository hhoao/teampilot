import 'dart:async';

import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';

import '../../../models/team_config.dart';
import '../../../services/acp/acp_chat_strings.dart';
import '../../../services/acp/acp_chat_transcript.dart';
import '../../../services/acp/acp_session.dart';
import '../../../services/acp/acp_session_runtime.dart';
import '../../../services/agent_status/agent_attention_state.dart';
import '../../../services/agent_status/agent_permission_request.dart';
import '../../../services/agent_status/agent_status_event.dart';
import '../../../utils/logging/logger.dart';
import '../../agent_attention_cubit.dart';

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

/// Why the session ended / errored.
enum AcpChatErrorKind {
  /// Every ACP flag candidate failed (old CLI version) —
  /// [AcpLaunchException] with [acpLaunchFailedVersion].
  launchFailedVersion,

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
    this.pendingPermission,
    this.error,
  });

  final AcpChatPhase phase;

  /// Chat transcript in arrival order (app-side single source).
  final List<AiMessage> messages;

  /// True from prompt submit until the turn's stop event.
  final bool inTurn;

  /// The currently held permission card, if any.
  final AgentPermissionRequest? pendingPermission;

  final AcpChatError? error;

  AcpChatRuntimeState copyWith({
    AcpChatPhase? phase,
    List<AiMessage>? messages,
    bool? inTurn,
    Object? pendingPermission = _unset,
    AcpChatError? error,
    bool clearError = false,
  }) => AcpChatRuntimeState(
    phase: phase ?? this.phase,
    messages: messages ?? this.messages,
    inTurn: inTurn ?? this.inTurn,
    pendingPermission: identical(pendingPermission, _unset)
        ? this.pendingPermission
        : pendingPermission as AgentPermissionRequest?,
    error: clearError ? null : (error ?? this.error),
  );

  static const _unset = Object();
}

/// Drives one terminal-less ACP chat session inside the workbench.
///
/// Maps [AcpSessionUpdate]s onto the shared [AiMessage] model (chunks → text
/// parts, thoughts → reasoning parts, tool calls → tool-card parts, stops →
/// idle), records every event into the app-side transcript (single source per
/// spec), surfaces permission requests onto the existing attention/card
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
    AgentAttentionCubit? attention,
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
  final AgentAttentionCubit? _attention;
  final AcpChatTranscriptWriter? _transcript;

  AcpChatStrings? _strings;
  StreamSubscription<AcpSessionUpdate>? _updatesSub;
  StreamSubscription<AgentPermissionRequest>? _permissionSub;
  Future<void>? _agentExitSub;

  /// Injects localized copy; must run before [start].
  void ensureStrings(AcpChatStrings strings) => _strings ??= strings;

  /// Spawns the agent and opens the ACP session.
  ///
  /// On success: subscribes to updates + permissions (before any prompt),
  /// stamps the attention seat working, and moves to [AcpChatPhase.ready].
  /// On [AcpLaunchException]: inline system message + ended phase. Any other
  /// failure is logged and also ends the session with its raw text (a
  /// non-launch failure here has no user-actionable copy of its own).
  Future<void> start({
    required String executable,
    required String sessionToolDir,
    required String workingDirectory,
    Map<String, String> baseEnv = const {},
  }) async {
    if (state.phase != AcpChatPhase.launching) return;
    try {
      await _runtime.start(
        tool: tool,
        executable: executable,
        sessionToolDir: sessionToolDir,
        workingDirectory: workingDirectory,
        baseEnv: baseEnv,
      );
    } on AcpLaunchException catch (error) {
      _endWith(
        AcpChatErrorKind.launchFailedVersion,
        error.reason == acpLaunchFailedVersion
            ? _strings?.launchFailedVersion ?? error.reason
            : error.reason,
      );
      return;
    } on Object catch (error, stackTrace) {
      appLogger.e(
        '[acp-chat] session $sessionId launch failed: $error',
        error: error,
        stackTrace: stackTrace,
      );
      _endWith(AcpChatErrorKind.processExited, '$error');
      return;
    }
    if (isClosed) return;
    _updatesSub = _runtime.updates.listen(
      _onUpdate,
      onError: (Object e) {
        appLogger.w('[acp-chat] session $sessionId updates error: $e');
      },
    );
    _permissionSub = _runtime.permissionRequests.listen(_onPermissionRequest);
    // Agent process exit (mid-session crash or out-of-turn death): inline
    // system message + ended phase. Attached in the same step as the other
    // subscriptions, after a successful start — a launch failure path has
    // already returned above and does not reach this watcher. The exit-code
    // future never completes for non-process-backed spawn connections.
    final agentExitCode = _runtime.agentProcessExitCode;
    if (agentExitCode != null) {
      _agentExitSub = agentExitCode.then((code) {
        handleProcessExited(code);
      });
    }
    _applyAttention(const AgentStatusEvent(state: AgentSeatAttention.working));
    emit(state.copyWith(phase: AcpChatPhase.ready));
  }

  /// Sends one prompt turn. Returns false (and does nothing) when a turn is
  /// already in flight, the session has ended, or the text is blank — the
  /// runtime is strictly sequential.
  bool sendPrompt(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;
    if (state.inTurn) return false;
    if (state.phase == AcpChatPhase.ended) return false;
    if (!_runtime.isStarted) return false;

    emit(state.copyWith(messages: [...state.messages, _userMessage(trimmed)]));
    emit(state.copyWith(inTurn: true));
    unawaited(
      _recordAndPrompt(trimmed).catchError((Object error, StackTrace st) {
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
    return true;
  }

  Future<void> _recordAndPrompt(String text) async {
    await _transcript?.recordUserPrompt(text);
    await _runtime.prompt(text);
  }

  /// Cancels the current turn (silently resolved via the cancelled stop).
  void cancelTurn() => _runtime.cancel();

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
    emit(state.copyWith(pendingPermission: null));
    _applyAttention(const AgentStatusEvent(state: AgentSeatAttention.working));
    final delivered = await _runtime.answerPermission(kind, always: always);
    return delivered != null;
  }

  /// The agent process died (exit watcher callback). Inline crash message +
  /// ended phase — no global error dialog.
  void handleProcessExited(int exitCode) {
    if (state.phase == AcpChatPhase.ended) return;
    _endWith(
      AcpChatErrorKind.processExited,
      '${_strings?.processExited ?? 'Agent process exited'} ($exitCode)',
    );
  }

  @override
  Future<void> close() async {
    await _updatesSub?.cancel();
    await _permissionSub?.cancel();
    _updatesSub = null;
    _permissionSub = null;
    // Detach the exit watcher FIRST: a never-completing exit future (the
    // common no-crash case) must not keep close's completion pending.
    _agentExitSub = null;
    if (state.phase != AcpChatPhase.ended) {
      _applyAttention(const AgentStatusEvent(state: AgentSeatAttention.done));
    }
    await _runtime.close();
    return super.close();
  }

  // ----- update mapping -----

  /// Awaits each transcript record before mapping the next event so the
  /// app-side message table preserves arrival order.
  Future<void> _onUpdate(AcpSessionUpdate update) async {
    if (isClosed) return;
    switch (update) {
      case AcpMessageChunk():
        await _transcript?.recordChunk(update);
        if (isClosed) return;
        _appendMessageParts(_chunkParts(update));
      case AcpToolCallUpdate():
        await _transcript?.recordToolCall(update);
        if (isClosed) return;
        _applyToolCall(update);
      case AcpPlan():
        // Plan updates have no chat-layer rendering yet (spec: recorded but
        // no mode-switching UI ships).
        break;
      case AcpStop():
        await _transcript?.recordStop(update);
        if (isClosed) return;
        _onStop(update);
    }
  }

  List<AiMessagePart> _chunkParts(AcpMessageChunk chunk) => [
    chunk.isThought
        ? AiReasoningPart(text: chunk.content)
        : AiTextPart(text: chunk.content),
  ];

  void _applyToolCall(AcpToolCallUpdate update) {
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
        emit(state.copyWith(messages: messages));
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
        emit(state.copyWith(messages: messages));
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
        _endTurn();
      case AcpStopKind.endTurn:
      case AcpStopKind.aborted:
        _endTurn();
      case AcpStopKind.maxTokens:
        _endTurn();
      case AcpStopKind.error:
        final prefix = _strings?.turnFailed ?? 'Turn failed';
        final text = stop.message == null || stop.message!.isEmpty
            ? prefix
            : '$prefix: ${stop.message}';
        _appendSystemMessage(text);
        unawaited(_transcript?.recordSystem('turn_error', text));
        _endTurn();
    }
  }

  void _endTurn() {
    if (isClosed) return;
    _applyAttention(const AgentStatusEvent(state: AgentSeatAttention.done));
    emit(
      state.copyWith(
        inTurn: false,
        phase: AcpChatPhase.idle,
        pendingPermission: null,
      ),
    );
  }

  void _onPermissionRequest(AgentPermissionRequest request) {
    if (isClosed || state.phase == AcpChatPhase.ended) return;
    emit(state.copyWith(pendingPermission: request));
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
  void _appendMessageParts(List<AiMessagePart> parts) {
    final messages = [...state.messages];
    if (messages.isNotEmpty && messages.last.role == AiRole.assistant) {
      final tip = messages.last;
      messages[messages.length - 1] = tip.copyWith(
        parts: [...tip.parts, ...parts],
      );
    } else {
      messages.add(
        AiMessage(
          id: 'acp-a-${_uuid.v4()}',
          role: AiRole.assistant,
          parts: parts,
          createdAt: DateTime.now(),
        ),
      );
    }
    emit(state.copyWith(messages: messages));
  }

  void _applyAttention(AgentStatusEvent event) {
    _attention?.applyEvent(
      sessionId: sessionId,
      memberId: acpMemberId,
      event: event,
      skipPermissions: false,
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

  void _endWith(AcpChatErrorKind kind, String message) {
    if (isClosed) return;
    _applyAttention(const AgentStatusEvent(state: AgentSeatAttention.done));
    unawaited(_transcript?.recordSystem(kind.name, message));
    _appendSystemMessage(message);
    emit(
      state.copyWith(
        phase: AcpChatPhase.ended,
        inTurn: false,
        pendingPermission: null,
        error: AcpChatError(kind: kind, message: message),
      ),
    );
  }
}
