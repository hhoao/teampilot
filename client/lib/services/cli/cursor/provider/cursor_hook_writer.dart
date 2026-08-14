import 'dart:convert';

import '../../../../models/hook_entry.dart';
import '../../../../models/hook_event.dart';
import '../../../../models/team_config.dart';
import '../../../team_bus/mcp/teammate_bus_mcp_handler.dart';
import '../../registry/capabilities/hook_registry.dart';
import '../../registry/capabilities/hook_capability.dart';

/// Cursor hook writer：`~/.cursor/hooks.json`（`{"version":1,"hooks":{...}}`）。
///
/// cursor 命令一律 bash（官方文档确认）；per-script 字段：command / matcher /
/// timeout / loop_limit（stop 用 null）。policy 输出 `{"permission":"allow|deny"}`
/// （preToolUse 等拦截事件；exit code 2 阻塞语义由胶水 exit 2 承担）。
class CursorHookWriter implements HookCapability {
  const CursorHookWriter({this.denyReason = 'TeamPilot hook policy'});

  final String denyReason;

  @override
  String? nativeEvent(HookEvent event) =>
      HookEventCapability.nativeEvent(event, CliTool.cursor);

  @override
  bool get supportsMatcher => true;
  @override
  bool get supportsHttp => true;
  @override
  bool get supportsPolicy => true;

  @override
  bool supportsEvent(HookEvent event) => nativeEvent(event) != null;

  @override
  HookWriteResult render({
    required List<HookEntry> entries,
    required HookRenderContext ctx,
  }) {
    final hooks = <String, Object?>{};
    final scripts = <GeneratedScript>[];
    final warnings = <String>[];

    for (final entry in entries) {
      final native = nativeEvent(entry.event);
      if (native == null) {
        warnings.add('hook_unsupported_event_${entry.id}_${entry.event.name}');
        continue;
      }
      if (entry.action is HttpHookAction) {
        final http = entry.action as HttpHookAction;
        final scriptFileName =
            'teampilot-http-${entry.id}-${entry.event.name}.sh';
        scripts.add(
          GeneratedScript(
            fileName: scriptFileName,
            content: _httpForwardScript(http, entry.blockOnDecision),
          ),
        );
        final hooksList =
            List<Object?>.from((hooks[native] as List?) ?? const []);
        final hookJson = <String, Object?>{
          'command': "bash '${ctx.hooksDir}/$scriptFileName'",
          if (entry.timeout != null) 'timeout': entry.timeout!.inSeconds,
          if (entry.event == HookEvent.stop) 'loop_limit': null,
        };
        if (!hooksList.any(
          (e) => e is Map && e['command'] == hookJson['command'],
        )) {
          hooksList.add(hookJson);
        }
        hooks[native] = hooksList;
        continue;
      }
      final command = entry.action as CommandHookAction;
      if (entry.policy != HookPolicy.none && !entry.event.isIntercepting) {
        warnings.add('hook_policy_ignored_${entry.id}_${entry.event.name}');
      }
      final decisionJson = entry.policy == HookPolicy.none ||
              !entry.event.isIntercepting
          ? null
          : entry.policy == HookPolicy.allow
          ? '{"permission":"allow"}'
          : '{"permission":"deny","user_message":"$denyReason"}';
      final inner = _innerCommand(command, entry.id, ctx, scripts);
      if (inner == null) {
        warnings.add('hook_script_missing_${entry.id}');
        continue;
      }
      final glue = ctx.glueBuilder.build(
        policy: entry.policy,
        innerCommand: inner,
        decisionJson: decisionJson,
        timeout: entry.timeout,
        env: entry.env,
        blockOnDecision: entry.blockOnDecision,
        dialect: 'bash',
      );
      final scriptFileName = 'teampilot-hook-${entry.id}.sh';
      scripts.add(GeneratedScript(fileName: scriptFileName, content: glue));
      final scriptPath = '${ctx.hooksDir}/$scriptFileName';
      final hookJson = <String, Object?>{
        'command': "bash '$scriptPath'",
        if (entry.matcher != null && entry.matcher!.trim().isNotEmpty)
          'matcher': entry.matcher,
        if (entry.timeout != null) 'timeout': entry.timeout!.inSeconds,
        if (entry.event == HookEvent.stop) 'loop_limit': null,
      };
      final hooksList =
          List<Object?>.from((hooks[native] as List?) ?? const []);
      if (!hooksList.any(
        (e) => e is Map && e['command'] == hookJson['command'],
      )) {
        hooksList.add(hookJson);
      }
      hooks[native] = hooksList;
    }

    if (hooks.isEmpty) {
      return HookWriteResult(warnings: warnings);
    }
    return HookWriteResult(
      configFragments: {
        'hooks.json': {'version': 1, 'hooks': hooks},
      },
      scripts: scripts,
      warnings: warnings,
    );
  }

  /// http 类 action 渲染为 bash 转发脚本（cursor hooks.json 仅 command 类）。
  ///
  /// `blockOnDecision=false`（agent-status）：stdin 透传 POST，best-effort，
  /// 恒 exit 0（与旧 CursorHomeAgentStatusOverlay.scriptFor 同语义）。
  /// `blockOnDecision=true`（bus idle stop）：POST 后响应含 `decision:block`
  /// 时输出 followup_message（与旧 CursorHomeBusOverlay.idleScript 同语义）。
  String _httpForwardScript(HttpHookAction http, bool blockOnDecision) {
    final headerArgs = http.headers.entries
        .map((e) => "-H '${e.key}: ${e.value}'")
        .join(' ');
    if (!blockOnDecision) {
      return '''
#!/usr/bin/env bash
# TeamPilot hook glue (http forward) — do not edit.
set -u
payload="\$(cat)"
[ -z "\$payload" ] && exit 0
curl -sS -X POST '${http.url}' $headerArgs -H 'Content-Type: application/json' -d "\$payload" >/dev/null 2>&1 || true
exit 0
''';
    }
    final followup = jsonEncode({
      'followup_message': TeammateBusMcpHandler.stopRedirectReason,
    });
    return '''
#!/usr/bin/env bash
# TeamPilot hook glue (bus idle) — do not edit.
set -u
cat >/dev/null 2>&1 || true
resp="\$(curl -sS -X POST $headerArgs '${http.url}' 2>/dev/null || true)"
case "\$resp" in
  *'"decision":"block"'*)
    printf '%s' '$followup'
    ;;
esac
exit 0
''';
  }

  String? _innerCommand(
    CommandHookAction command,
    String id,
    HookRenderContext ctx,
    List<GeneratedScript> scripts,
  ) {
    if (command.command != null) return command.command;
    final fileName = command.fileName;
    final content = command.scriptContent;
    if (fileName == null || content == null) return null;
    final scriptFileName = '$id/$fileName';
    scripts.add(GeneratedScript(fileName: scriptFileName, content: content));
    return '${ctx.hooksDir}/$scriptFileName';
  }
}

/// 按 (event, command) 去重把 writer 渲染的 hooks 片段并入现有 hooks.json map
/// （保留 agent-status / bus 已写入条目）。
Map<String, Object?> mergeCursorHooksConfig(
  Map<String, Object?> existing,
  Map<String, Object?> hooksFragment,
) {
  final hooks = Map<String, Object?>.from(
    (existing['hooks'] as Map?)?.cast<String, Object?>() ?? const {},
  );
  final incoming = (hooksFragment['hooks'] as Map?)?.cast<String, Object?>() ??
      const <String, Object?>{};
  for (final entry in incoming.entries) {
    final event = entry.key;
    final incomingList = List<Object?>.from((entry.value as List?) ?? const []);
    final existingList =
        List<Object?>.from((hooks[event] as List?) ?? const []);
    for (final inc in incomingList) {
      if (inc is! Map) continue;
      final command = inc['command'];
      if (command == null) continue;
      if (!existingList.any((e) => e is Map && e['command'] == command)) {
        existingList.add(inc);
      }
    }
    hooks[event] = existingList;
  }
  return {...existing, 'hooks': hooks};
}
