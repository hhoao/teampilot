import '../../../../models/hook_entry.dart';
import '../../../../models/hook_event.dart';
import '../../../../models/plugin.dart';
import '../../../../models/team_config.dart';
import '../../../agent_status/member_agent_status_endpoint.dart';
import '../../../team/team_lead_delegate_settings_merge.dart';
import '../../../team_bus/member_bus_idle_endpoint.dart';
import '../../../resource/assemblers/hook_assembler.dart';
import '../../../resource/providers/hook_contribution_provider.dart';
import '../../../io/filesystem.dart';
import 'config_profile_scope.dart';
import 'agent_status_hooks.dart';

/// 把内部托管 hook 组装为 [HookEntry]（source: managed）。
/// 装配点（各 CLI config_profile）用它组装 managed 条目，渲染走统一 writer
/// （Task 19 后旧 mergeAgentStatusHooks / mergeStopIdleHook 通道已删除）。
class HookSeatContextCompleter {
  const HookSeatContextCompleter();

  Future<HookAssemblyResult> assemble({
    required CliTool cli,
    required Iterable<HookContributionProvider> providers,
    TeamMemberConfig? member,
    Map<String, String> endpoints = const {},
    Filesystem? filesystem,
    String? hooksDirectory,
    LaunchProfileScope? scope,
  }) => const HookAssembler().assemble(
    context: HookProviderContext(
      cli: cli,
      member: member,
      endpoints: endpoints,
      filesystem: filesystem,
      hooksDirectory: hooksDirectory,
      scope: scope,
    ),
    providers: providers,
  );

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

  /// team-lead delegate PreToolUse 命令钩子（source: managed）。
  ///
  /// matcher 保留旧 `TeamLeadDelegateSettingsMerge.blockedToolsMatcher` 语义
  /// （脚本只拦截受限工具集，见 `teampilot-team-lead-delegate-only.sh`），
  /// 与 Task 18 收敛前 `maybeApplyTeamLeadHooks` 的渲染内容一致。
  List<HookEntry> delegateHooks({required List<String> commands}) => [
    for (final command in commands)
      if (command.trim().isNotEmpty)
        HookEntry(
          id: 'teampilot-team-lead-delegate',
          source: HookSource.managed,
          event: HookEvent.preToolUse,
          matcher: TeamLeadDelegateSettingsMerge.blockedToolsMatcher,
          action: CommandHookAction.raw(command.trim()),
        ),
  ];

  /// 扩展 settings-hook（manifest `config.event` + matcher + command）。
  ///
  /// entry id 带扩展 id（`teampilot-extension-settings-hook-<extensionId>-
  /// <eventName>`）——两个扩展对同一事件配 settings-hook 时 id 仍唯一，
  /// writer 的胶水文件名（按 entry.id 生成）不碰撞，避免后写覆盖先写、
  /// 去重保留的条目指向被覆盖脚本。事件名接受 camelCase（`preToolUse`）
  /// 与 CLI 原生 PascalCase（`PreToolUse`）两种拼写；`matcher` 透传（旧
  /// `SettingsHookEffectApplier` 默认 `'Bash'`，由调用方按 effect 提供）。
  List<HookEntry> extensionHooks({
    required String extensionId,
    required List<String> events,
    required String command,
    String? matcher,
  }) => [
    for (final eventName in events)
      if (_parseEventName(eventName) != null && command.trim().isNotEmpty)
        HookEntry(
          id: 'teampilot-extension-settings-hook-$extensionId-$eventName',
          source: HookSource.extension,
          event: _parseEventName(eventName)!,
          matcher: matcher,
          action: CommandHookAction.raw(command.trim()),
        ),
  ];

  /// 插件 hooks（`hooks/hooks.json` 扫描产物）→ HookEntry(source: plugin)。
  ///
  /// event / matcher 语义照抄 [PluginHook] 现有字段（事件名同时接受
  /// camelCase 与 CLI 原生 PascalCase）；`PluginHook` 不含 command 字段，
  /// 命令由调用方提供（现状插件 hooks 仅披露、未接入渲染，装配点暂缺数据源）。
  List<HookEntry> pluginHooks({
    required List<PluginHook> hooks,
    required String command,
  }) => [
    for (final hook in hooks)
      if (_parseEventName(hook.event) != null && command.trim().isNotEmpty)
        HookEntry(
          id: 'teampilot-plugin-hook-${hook.event}',
          source: HookSource.plugin,
          event: _parseEventName(hook.event)!,
          matcher: hook.matcher.trim().isEmpty ? null : hook.matcher.trim(),
          action: CommandHookAction.raw(command.trim()),
        ),
  ];

  /// 宽容事件名解析：camelCase 精确匹配 → 大小写不敏感 → claude 原生名。
  static HookEvent? _parseEventName(String name) {
    final exact = HookEvent.tryParse(name);
    if (exact != null) return exact;
    final lower = name.trim().toLowerCase();
    if (lower.isEmpty) return null;
    for (final event in HookEvent.values) {
      if (event.name.toLowerCase() == lower) return event;
    }
    for (final event in HookEvent.values) {
      final native = HookEventCapability.nativeEvent(event, CliTool.claude);
      if (native?.toLowerCase() == lower) return event;
    }
    return null;
  }
}
