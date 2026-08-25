import '../../../agent_status/agent_status_event.dart';
import '../../../agent_runtime/runtime_event.dart';
import '../../../../models/hook_entry.dart';
import '../../../../models/team_config.dart';
import '../../registry/capabilities/chat_interaction_capability.dart';
import '../../registry/capabilities/claude_family_agent_status_normalizer.dart';
import '../../registry/capabilities/runtime_event_capability.dart';

/// PTY picker answer flow — codex surfaces AskUserQuestion through the
/// embedded terminal; no in-chat ExitPlanMode approval (keeps the
/// "Open Terminal" fallback).
final class CodexChatInteraction
    implements ChatInteractionCapability, RuntimeEventCapability {
  const CodexChatInteraction();

  @override
  AgentStatusEvent? normalize(Map<String, Object?> body) =>
      const ClaudeFamilyAgentStatusNormalizer().normalize(body);

  @override
  RuntimeEventEnvelopeDraft? normalizeRuntimeEvent(
    Map<String, Object?> raw,
    RuntimeSeatKey seat,
    DateTime occurredAt,
  ) {
    if (raw['hook_event_name'] != 'UserPromptSubmit') return null;
    final prompt = raw['prompt']?.toString();
    if (prompt == null || prompt.isEmpty) return null;
    return RuntimeEventEnvelopeDraft.promptSubmitted(
      seat: seat,
      cli: CliTool.codex,
      prompt: prompt,
      occurredAt: occurredAt,
      correlationStrength: promptCorrelationStrength,
    );
  }

  @override
  RuntimeCorrelationStrength get promptCorrelationStrength =>
      RuntimeCorrelationStrength.serializedPromptEpoch;

  @override
  List<HookEntry> managedHookEntries(RuntimeEventHookContext context) =>
      managedRuntimeEventHookEntries(cli: CliTool.codex, context: context);

  @override
  bool get supportsStructuredAsk => true;

  @override
  bool get supportsInChatAnswer => true;

  @override
  bool get supportsMultiSelectInChat => true;

  @override
  bool get supportsMultiQuestionInChat => true;

  @override
  bool get supportsInChatPermissionReply => false;

  @override
  AskUserAnswerKind get answerKind => AskUserAnswerKind.ptyPicker;

  @override
  bool get supportsInChatApproval => false;

  @override
  ExitPlanApprovalKind get approvalKind => ExitPlanApprovalKind.none;
}
