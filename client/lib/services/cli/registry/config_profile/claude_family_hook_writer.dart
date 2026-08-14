import '../../../../models/hook_entry.dart';
import '../../../../models/hook_event.dart';
import '../../../../models/team_config.dart';
import '../../../host/host_script_dialect.dart';
import '../../../host/host_script_runner.dart';
import '../../../hook/glue_script_builder.dart';
import '../capabilities/hook_registry.dart';
import '../capabilities/hook_capability.dart';

/// claude / flashskyai 共享的 hook writer：settings.json `hooks` 片段。
///
/// 渲染产物为 `{'hooks': {...}}` 片段；装配点用 `mergeHooksInto` 幂等并入
/// （按 (event, url|command) 去重）。Task 19 后为唯一渲染路径
/// （旧 ClaudeFamilyHookRegistry.render 资产路径已删除）。
class ClaudeFamilyHookWriter implements HookCapability {
  const ClaudeFamilyHookWriter({this.denyReason = 'TeamPilot hook policy'});

  final String denyReason;

  @override
  String? nativeEvent(HookEvent event) =>
      HookEventCapability.nativeEvent(event, CliTool.claude);

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
    final runner = ctx.runner;

    for (final entry in entries) {
      final native = nativeEvent(entry.event);
      if (native == null) {
        warnings.add('hook_unsupported_event_${entry.id}_${entry.event.name}');
        continue;
      }
      if (entry.policy != HookPolicy.none && !entry.event.isIntercepting) {
        warnings.add('hook_policy_ignored_${entry.id}_${entry.event.name}');
      }
      final decisionJson = entry.policy == HookPolicy.none ||
              !entry.event.isIntercepting
          ? null
          : entry.policy == HookPolicy.allow
          ? '{"permissionDecision":"allow"}'
          : '{"permissionDecision":"deny","permissionDecisionReason":'
                '"$denyReason"}';
      final hooksList =
          List<Object?>.from((hooks[native] as List?) ?? const []);

      switch (entry.action) {
        case HttpHookAction http:
          final hookJson = <String, Object?>{
            'type': 'http',
            'url': http.url,
            if (http.headers.isNotEmpty) 'headers': http.headers,
            if (entry.timeout != null)
              'timeout': entry.timeout!.inSeconds,
          };
          hooksList.add({
            if (entry.matcher != null && entry.matcher!.trim().isNotEmpty)
              'matcher': entry.matcher,
            'hooks': [hookJson],
          });
        case CommandHookAction command:
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
            dialect: ctx.runner?.dialect.name == 'powershell'
                ? 'powershell'
                : 'bash',
          );
          final scriptFileName = 'teampilot-hook-${entry.id}'
              '${runner?.dialect.scriptExtension ?? '.sh'}';
          scripts.add(GeneratedScript(fileName: scriptFileName, content: glue));
          final scriptPath = runner == null
              ? '${ctx.hooksDir}/$scriptFileName'
              : runner.commandStringForScriptFile(
                  '${ctx.hooksDir}/$scriptFileName',
                );
          final hookJson = <String, Object?>{
            'type': 'command',
            'command': scriptPath,
            'timeout': entry.timeout?.inSeconds ?? 5,
          };
          hooksList.add({
            if (entry.matcher != null && entry.matcher!.trim().isNotEmpty)
              'matcher': entry.matcher,
            'hooks': [hookJson],
          });
      }
      hooks[native] = hooksList;
    }

    return HookWriteResult(
      configFragments: {
        'settings.json': {'hooks': hooks},
      },
      scripts: scripts,
      warnings: warnings,
    );
  }

  /// 用户命令 / 托管脚本 → 内层命令；托管脚本以 GeneratedScript 写出
  /// 并在 hooksDir 子目录落盘。
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
    final path = '${ctx.hooksDir}/$scriptFileName';
    return ctx.runner?.commandStringForScriptFile(path) ?? path;
  }
}
