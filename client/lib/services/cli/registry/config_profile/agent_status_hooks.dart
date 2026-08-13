import '../../../agent_status/member_agent_status_endpoint.dart';

/// Per-event status URL so identical-handler dedupe keeps every lifecycle hook.
///
/// Task 19 收敛后 `mergeAgentStatusHooks` 已删除——managed agent-status 条目
/// 由 `HookSeatContextCompleter.agentStatusHooks` 组装、统一 writer 渲染；
/// 此处仅保留 completer 复用的 URL 身份函数。
String agentStatusHookUrl(String baseUrl, String eventName) {
  final uri = Uri.parse(baseUrl);
  final next = Map<String, String>.from(uri.queryParameters)
    ..['event'] = eventName;
  return uri.replace(queryParameters: next).toString();
}
