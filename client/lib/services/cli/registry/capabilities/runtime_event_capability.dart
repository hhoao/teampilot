import '../../../agent_runtime/runtime_event.dart';
import '../../../agent_status/member_agent_status_endpoint.dart';
import '../../../../models/hook_entry.dart';
import '../../../../models/hook_event.dart';
import '../../../../models/team_config.dart';
import '../config_profile/agent_status_hooks.dart';
import '../cli_capability.dart';

/// Session-scoped context supplied while a CLI contributes its runtime hooks.
///
/// This is deliberately control-plane data only: capabilities return
/// [HookEntry] values and existing hook writers materialize them.
final class RuntimeEventHookContext {
  const RuntimeEventHookContext({
    required this.endpoint,
    required this.memberId,
  });

  final MemberAgentStatusEndpoint endpoint;
  final String memberId;
}

/// Translates a CLI's native runtime payloads and contributes native hooks.
abstract interface class RuntimeEventCapability implements CliCapability {
  RuntimeEventEnvelopeDraft? normalizeRuntimeEvent(
    Map<String, Object?> raw,
    RuntimeSeatKey seat,
    DateTime occurredAt,
  );

  RuntimeCorrelationStrength get promptCorrelationStrength;

  List<HookEntry> managedHookEntries(RuntimeEventHookContext context);
}

/// Shared HookEntry shape for the existing endpoint contract.
///
/// Per-CLI capabilities opt into this helper rather than a provider installing
/// its own files. Native event names are kept in the endpoint query so a hook
/// payload which omits its event name is still normalized correctly.
List<HookEntry> managedRuntimeEventHookEntries({
  required CliTool cli,
  required RuntimeEventHookContext context,
}) {
  const events = [
    HookEvent.permissionRequest,
    HookEvent.preToolUse,
    HookEvent.postToolUse,
    HookEvent.postToolUseFailure,
    HookEvent.stop,
    HookEvent.stopFailure,
    HookEvent.userPromptSubmit,
    HookEvent.subagentStart,
    HookEvent.subagentStop,
  ];
  const matcherEvents = {
    HookEvent.permissionRequest,
    HookEvent.preToolUse,
    HookEvent.postToolUse,
    HookEvent.postToolUseFailure,
  };
  final headers = context.endpoint.headersFor(context.memberId);
  return [
    for (final event in events)
      HookEntry(
        id: 'teampilot-runtime-event-${event.name}',
        source: HookSource.managed,
        event: event,
        matcher: matcherEvents.contains(event) ? '*' : null,
        action: HttpHookAction(
          url: agentStatusHookUrl(
            context.endpoint.url,
            HookEventCapability.nativeEvent(event, cli) ?? event.name,
          ),
          headers: headers,
        ),
        // PreToolUse holds for chat approval (AskUserQuestion / ExitPlanMode).
        // PermissionRequest shares the long cap so an ExitPlanMode plan
        // confirmation can be held for an in-chat decision; other tools'
        // events are answered `{}` immediately by the gateway, so the cap is
        // never reached for them.
        timeout:
            event == HookEvent.preToolUse ||
                event == HookEvent.permissionRequest
            ? const Duration(days: 1)
            : const Duration(seconds: 5),
      ),
  ];
}
