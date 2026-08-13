import '../../../../models/hook_entry.dart';
import '../../../../models/hook_event.dart';
import '../../../../models/team_config.dart';
import '../../../agent_status/member_agent_status_endpoint.dart';
import '../../../team_bus/member_bus_idle_endpoint.dart';
import 'agent_status_hooks.dart';

/// 把内部托管 hook 组装为 [HookEntry]（source: managed）。
/// 装配点（各 CLI config_profile）用它替代各自的 mergeAgentStatusHooks /
/// mergeStopIdleHook，渲染走统一 writer（收敛目标）。
class HookSeatContextCompleter {
  const HookSeatContextCompleter();

  /// agent-status 全事件集（与 agent_status_hooks.dart 常量一致）。
  static const List<HookEvent> agentStatusEvents = [
    HookEvent.permissionRequest,
    HookEvent.preToolUse,
    HookEvent.postToolUse,
    HookEvent.postToolUseFailure,
    HookEvent.stop,
    HookEvent.stopFailure,
    HookEvent.userPromptSubmit,
  ];

  /// 需要 matcher `*` 的事件（与 agent_status_hooks.dart 一致）。
  static const Set<HookEvent> agentStatusMatcherEvents = {
    HookEvent.permissionRequest,
    HookEvent.preToolUse,
    HookEvent.postToolUse,
    HookEvent.postToolUseFailure,
  };

  /// bus idle（mixed Stop/StopFailure）事件集。
  static const List<HookEvent> busIdleEvents = [
    HookEvent.stop,
    HookEvent.stopFailure,
  ];

  List<HookEntry> agentStatusHooks({
    required MemberAgentStatusEndpoint endpoint,
    required String memberId,
  }) {
    final headers = endpoint.headersFor(memberId);
    return [
      for (final event in agentStatusEvents)
        HookEntry(
          id: 'teampilot-agent-status-${event.name}',
          source: HookSource.managed,
          event: event,
          matcher: agentStatusMatcherEvents.contains(event) ? '*' : null,
          action: HttpHookAction(
            // URL 事件名用原生 PascalCase，与现有 agent_status_hooks.dart
            // 的 per-event URL 身份一致（hook-gate / 去重兼容）。
            url: agentStatusHookUrl(
              endpoint.url,
              HookEventCapability.nativeEvent(event, CliTool.claude)!,
            ),
            headers: headers,
          ),
          // AskUserQuestion PreToolUse 保持挂起（与现状 timeout 86400 一致）。
          timeout: event == HookEvent.preToolUse
              ? const Duration(days: 1)
              : const Duration(seconds: 5),
        ),
    ];
  }

  List<HookEntry> busIdleHooks({
    required MemberBusIdleEndpoint idle,
    required String memberId,
  }) {
    final url = idle.url;
    return [
      for (final event in busIdleEvents)
        HookEntry(
          id: 'teampilot-bus-idle-${event.name}',
          source: HookSource.managed,
          event: event,
          action: HttpHookAction(url: url, headers: idle.headersFor(memberId)),
          timeout: const Duration(seconds: 5),
          blockOnDecision: true,
        ),
    ];
  }
}
