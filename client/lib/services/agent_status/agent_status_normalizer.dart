import '../../models/team_config.dart';
import 'agent_attention_state.dart';
import 'agent_status_event.dart';
import 'agent_status_tool_input.dart';
import 'ask_user_question.dart';
import 'exit_plan_mode.dart';

/// Maps raw CLI hook / plugin JSON to a normalized [AgentStatusEvent].
///
/// Pure: no I/O. Returns `null` for corrupt, unknown, or Cursor payloads
/// (Cursor uses the title path only).
///
/// Claude-family rules mirror Orca `normalizeClaudeEvent`:
/// - AskUserQuestion / ExitPlanMode PreToolUse / PermissionRequest → waiting
/// - non-AskUserQuestion PreToolUse / PostToolUse / PostToolUseFailure /
///   UserPromptSubmit → working
/// - Stop / StopFailure → done
/// - SubagentStart / SubagentStop → null (do not mark primary done)
class AgentStatusNormalizer {
  const AgentStatusNormalizer._();

  static AgentStatusEvent? normalize({
    required CliTool cli,
    required Map<String, Object?> body,
  }) {
    return switch (cli) {
      CliTool.claude || CliTool.flashskyai || CliTool.codex =>
        _normalizeClaudeFamily(body),
      CliTool.opencode => _normalizeOpenCode(body),
      CliTool.cursor => _normalizeCursor(body),
    };
  }

  /// Cursor hook payloads mirror Claude Code's keys (`hook_event_name`,
  /// `tool_name`, `tool_use_id`); the event names differ (camelCase), so map
  /// them to tool-lifecycle attention. Waiting stays on the OSC-title path
  /// (`detectCursorTitleAttention`) — cursor asks questions as plain text, not
  /// a structured tool.
  static AgentStatusEvent? _normalizeCursor(Map<String, Object?> body) {
    final eventName = body['hook_event_name']?.toString();
    if (eventName == null || eventName.isEmpty) return null;
    final toolName = _readString(body, const ['tool_name', 'toolName']);
    final toolUseId = _readString(body, const ['tool_use_id', 'toolUseId']);
    AgentStatusEvent build(AgentSeatAttention state) => AgentStatusEvent(
      state: state,
      toolName: toolName,
      hookEventName: eventName,
      toolUseId: toolUseId,
    );
    return switch (eventName) {
      'preToolUse' ||
      'postToolUse' ||
      'postToolUseFailure' ||
      'beforeSubmitPrompt' ||
      'afterAgentResponse' ||
      'beforeShellExecution' ||
      'beforeMCPExecution' => build(AgentSeatAttention.working),
      'stop' => build(AgentSeatAttention.done),
      _ => null,
    };
  }

  static AgentStatusEvent? _normalizeClaudeFamily(Map<String, Object?> body) {
    final eventName = body['hook_event_name']?.toString();
    if (eventName == null || eventName.isEmpty) return null;

    // Why: Subagent lifecycle must not flip the primary seat to done/working.
    if (eventName == 'SubagentStart' || eventName == 'SubagentStop') {
      return null;
    }

    final toolName = _readString(body, const ['tool_name', 'toolName']);
    final askUser = isAskUserQuestionTool(toolName);
    final exitPlan = isExitPlanModeTool(toolName);
    final rawToolInput = body['tool_input'] ?? body['input'] ?? body['arguments'];
    final toolInput = deriveToolInputPreview(toolName, rawToolInput);
    final toolUseId = _readString(body, const ['tool_use_id', 'toolUseId']);
    final toolAgentId = _readString(body, const ['agent_id', 'agentId']);
    final toolAgentType = _readString(body, const ['agent_type', 'agentType']);

    // AskUserQuestion / ExitPlanMode carry structured payloads the chat needs
    // to render (and optionally answer / confirm).
    final askUserQuestions =
        askUser ? parseAskUserQuestions(rawToolInput) : null;
    final planText = exitPlan ? parseExitPlanModeText(rawToolInput) : null;
    final planFilePath = exitPlan
        ? parseExitPlanModeFilePath(rawToolInput)
        : null;

    // AskUserQuestion PreToolUse: askRequestId mirrors tool_use_id so answer
    // correlation works the same as OpenCode request_id.
    final askRequestId = askUser ? toolUseId : null;

    AgentStatusEvent build(AgentSeatAttention state, {bool explicit = false}) =>
        AgentStatusEvent(
          state: state,
          toolName: toolName,
          toolInput: toolInput,
          hookEventName: eventName,
          toolUseId: toolUseId,
          toolAgentId: toolAgentId,
          toolAgentType: toolAgentType,
          hasExplicitPrompt: explicit,
          askUserQuestions: askUserQuestions,
          askRequestId: askRequestId,
          planText: planText,
          planFilePath: planFilePath,
        );

    return switch (eventName) {
      'PermissionRequest' => build(AgentSeatAttention.waiting),
      'PreToolUse' when askUser || exitPlan => build(
        AgentSeatAttention.waiting,
      ),
      'PreToolUse' || 'PostToolUse' || 'PostToolUseFailure' => build(
        AgentSeatAttention.working,
      ),
      'UserPromptSubmit' => build(
        AgentSeatAttention.working,
        explicit: true,
      ),
      'Stop' || 'StopFailure' => build(AgentSeatAttention.done),
      _ => null,
    };
  }

  static AgentStatusEvent? _normalizeOpenCode(Map<String, Object?> body) {
    final eventName = body['event']?.toString();
    if (eventName == null || eventName.isEmpty) return null;

    final askRequestId = _readString(body, const ['request_id', 'id']);
    final nativeSessionId = _readString(body, const [
      'session_id',
      'sessionID',
    ]);
    final message = _readString(body, const ['message']);

    return switch (eventName) {
      'permission.asked' => AgentStatusEvent(
        state: AgentSeatAttention.waiting,
        hookEventName: eventName,
      ),
      'question.asked' => AgentStatusEvent(
        state: AgentSeatAttention.waiting,
        hookEventName: eventName,
        askUserQuestions: parseQuestionsList(body['questions']),
        askRequestId: askRequestId,
        nativeSessionId: nativeSessionId,
      ),
      'question.reply_failed' => AgentStatusEvent(
        state: AgentSeatAttention.waiting,
        hookEventName: eventName,
        askRequestId: askRequestId,
        message: message,
        // Restore only when we can correlate back to the pending ask.
        restoreAskWaiting: askRequestId != null,
      ),
      'session.idle' => AgentStatusEvent(
        state: AgentSeatAttention.done,
        hookEventName: eventName,
      ),
      _ => null,
    };
  }

  static String? _readString(Map<String, Object?> body, List<String> keys) {
    for (final key in keys) {
      final value = body[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    return null;
  }
}

/// True for AskUserQuestion across casing variants (`AskUserQuestion`,
/// `ask_user_question`, `askUserQuestion`) — same rule as Orca.
bool isAskUserQuestionTool(String? toolName) {
  if (toolName == null || toolName.isEmpty) return false;
  final compact = toolName.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toLowerCase();
  return compact == 'askuserquestion';
}
