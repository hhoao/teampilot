import 'agent_attention_state.dart';
import 'ask_user_question.dart';

/// Normalized agent-status signal from a CLI hook / plugin payload.
class AgentStatusEvent {
  const AgentStatusEvent({
    required this.state,
    this.toolName,
    this.toolInput,
    this.hookEventName,
    this.toolUseId,
    this.toolAgentId,
    this.toolAgentType,
    this.hasExplicitPrompt = false,
    this.askUserQuestions,
    this.askRequestId,
    this.nativeSessionId,
    this.message,
    this.restoreAskWaiting = false,
    this.planText,
    this.planFilePath,
  });

  final AgentSeatAttention state;
  final String? toolName;

  /// Preview string for sticky permission matching (Orca `toolInput`).
  final String? toolInput;

  /// Raw hook event name (`PermissionRequest`, `PreToolUse`, …).
  final String? hookEventName;

  /// Claude `tool_use_id` — sticky clear / inheritance key.
  final String? toolUseId;

  /// Claude subagent `agent_id`.
  final String? toolAgentId;

  /// Claude subagent `agent_type` (weaker than [toolAgentId]).
  final String? toolAgentType;

  /// True for UserPromptSubmit-style events that must clear sticky waiting.
  final bool hasExplicitPrompt;

  /// Structured AskUserQuestion payload for chat rendering / answering, when
  /// this event is a `PreToolUse` for the AskUserQuestion tool.
  final List<AgentAskUserQuestion>? askUserQuestions;

  /// Correlation id for answering an ask (OpenCode `request_id` / `id`, or
  /// Claude-family AskUserQuestion `tool_use_id`).
  final String? askRequestId;

  /// OpenCode native session id (`session_id` / `sessionID`).
  final String? nativeSessionId;

  /// Optional error / status message (e.g. OpenCode `question.reply_failed`).
  final String? message;

  /// True only for OpenCode `question.reply_failed` when [askRequestId] is
  /// present — cubit should restore the waiting ask card (Task 4).
  final bool restoreAskWaiting;

  /// Claude `ExitPlanMode` plan text for the chat approval card.
  final String? planText;

  /// Claude `ExitPlanMode` plan file path (when the CLI persisted it).
  final String? planFilePath;

  AgentStatusEvent copyWith({
    AgentSeatAttention? state,
    String? toolName,
    String? toolInput,
    String? hookEventName,
    String? toolUseId,
    String? toolAgentId,
    String? toolAgentType,
    bool? hasExplicitPrompt,
    List<AgentAskUserQuestion>? askUserQuestions,
    String? askRequestId,
    String? nativeSessionId,
    String? message,
    bool? restoreAskWaiting,
    String? planText,
    String? planFilePath,
  }) => AgentStatusEvent(
    state: state ?? this.state,
    toolName: toolName ?? this.toolName,
    toolInput: toolInput ?? this.toolInput,
    hookEventName: hookEventName ?? this.hookEventName,
    toolUseId: toolUseId ?? this.toolUseId,
    toolAgentId: toolAgentId ?? this.toolAgentId,
    toolAgentType: toolAgentType ?? this.toolAgentType,
    hasExplicitPrompt: hasExplicitPrompt ?? this.hasExplicitPrompt,
    askUserQuestions: askUserQuestions ?? this.askUserQuestions,
    askRequestId: askRequestId ?? this.askRequestId,
    nativeSessionId: nativeSessionId ?? this.nativeSessionId,
    message: message ?? this.message,
    restoreAskWaiting: restoreAskWaiting ?? this.restoreAskWaiting,
    planText: planText ?? this.planText,
    planFilePath: planFilePath ?? this.planFilePath,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AgentStatusEvent &&
          state == other.state &&
          toolName == other.toolName &&
          toolInput == other.toolInput &&
          hookEventName == other.hookEventName &&
          toolUseId == other.toolUseId &&
          toolAgentId == other.toolAgentId &&
          toolAgentType == other.toolAgentType &&
          hasExplicitPrompt == other.hasExplicitPrompt &&
          _sameQuestions(askUserQuestions, other.askUserQuestions) &&
          askRequestId == other.askRequestId &&
          nativeSessionId == other.nativeSessionId &&
          message == other.message &&
          restoreAskWaiting == other.restoreAskWaiting &&
          planText == other.planText &&
          planFilePath == other.planFilePath;

  @override
  int get hashCode => Object.hash(
    state,
    toolName,
    toolInput,
    hookEventName,
    toolUseId,
    toolAgentId,
    toolAgentType,
    hasExplicitPrompt,
    Object.hashAll(askUserQuestions ?? const []),
    askRequestId,
    nativeSessionId,
    message,
    restoreAskWaiting,
    planText,
    planFilePath,
  );
}

bool _sameQuestions(
  List<AgentAskUserQuestion>? a,
  List<AgentAskUserQuestion>? b,
) {
  if (identical(a, b)) return true;
  if (a == null || b == null || a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
