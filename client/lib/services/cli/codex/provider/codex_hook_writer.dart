import '../../../../models/hook_entry.dart';
import '../../../../models/hook_event.dart';
import '../../../../models/team_config.dart';
import '../../../host/host_script_dialect.dart';
import '../../registry/capabilities/hook_registry.dart';
import '../../registry/capabilities/hook_capability.dart';
import 'codex_http_hook_script.dart';

/// Codex hook writer：`config.toml` 的 `[[hooks.<Event>]]` 片段。
class CodexHookWriter implements HookCapability {
  const CodexHookWriter({this.denyReason = 'TeamPilot hook policy'});

  final String denyReason;

  @override
  String? nativeEvent(HookEvent event) =>
      HookEventCapability.nativeEvent(event, CliTool.codex);

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
    final buffer = StringBuffer(
      '# TeamPilot user hooks — do not edit.\n',
    );
    final scripts = <GeneratedScript>[];
    final warnings = <String>[];
    final runner = ctx.runner;
    var first = true;

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
      final command = entry.action;
      final String? inner;
      if (command is CommandHookAction) {
        inner = _innerCommand(command, entry.id, ctx, scripts);
      } else if (command is HttpHookAction) {
        // codex config.toml 的 hooks 仅支持 command/prompt/agent 三类，没有
        // 原生 http 类；http action 渲染为 curl 转发脚本 + `type = "command"`
        // （与 cursor 的 bash 转发同法）。透传语义：
        // - bus idle（blockOnDecision）：POST 响应（含 followup_message）
        //   写回 stdout，供 codex 展示，失败容错；
        // - 拦截类 + 显式 policy：POST 响应（决策 JSON）写回 stdout；
        // - 其余（agent-status 上报）：转发 stdin payload、best-effort 丢弃。
        final dialect = ctx.runner?.dialect ?? HostScriptDialect.bash;
        final scriptFileName =
            'teampilot-http-${entry.id}-${entry.event.name}'
            '${dialect.scriptExtension}';
        final passResponseToStdout = entry.blockOnDecision ||
            (entry.event.isIntercepting &&
                entry.policy != HookPolicy.none);
        scripts.add(
          GeneratedScript(
            fileName: scriptFileName,
            content: CodexHttpHookScript.build(
              dialect: dialect,
              url: command.url,
              headers: command.headers,
              forwardStdin: !entry.blockOnDecision,
              passResponseToStdout: passResponseToStdout,
              bestEffort: !passResponseToStdout,
            ),
          ),
        );
        final scriptPath = ctx.runner?.commandStringForScriptFile(
              '${ctx.hooksDir}/$scriptFileName',
            ) ??
            '${ctx.hooksDir}/$scriptFileName';
        if (!first) buffer.writeln();
        buffer.writeln('[[hooks.$native]]');
        if (entry.matcher != null && entry.matcher!.trim().isNotEmpty) {
          buffer.writeln('matcher = "${_escape(entry.matcher!)}"');
        }
        buffer.writeln();
        buffer.writeln('[[hooks.$native.hooks]]');
        buffer.writeln('type = "command"');
        buffer.writeln('command = "${_escape(scriptPath)}"');
        buffer.writeln('timeout = ${entry.timeout?.inSeconds ?? 5}');
        first = false;
        continue;
      } else {
        warnings.add('hook_invalid_action_${entry.id}');
        continue;
      }
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
        dialect: runner?.dialect.name == 'powershell' ? 'powershell' : 'bash',
      );
      final scriptFileName = 'teampilot-hook-${entry.id}'
          '${runner?.dialect.scriptExtension ?? '.sh'}';
      scripts.add(GeneratedScript(fileName: scriptFileName, content: glue));
      final scriptPath = runner == null
          ? '${ctx.hooksDir}/$scriptFileName'
          : runner.commandStringForScriptFile(
              '${ctx.hooksDir}/$scriptFileName',
            );
      if (!first) buffer.writeln();
      buffer.writeln('[[hooks.$native]]');
      if (entry.matcher != null && entry.matcher!.trim().isNotEmpty) {
        buffer.writeln('matcher = "${_escape(entry.matcher!)}"');
      }
      buffer.writeln();
      buffer.writeln('[[hooks.$native.hooks]]');
      buffer.writeln('type = "command"');
      buffer.writeln('command = "${_escape(scriptPath)}"');
      buffer.writeln('timeout = ${entry.timeout?.inSeconds ?? 5}');
      first = false;
    }

    if (first) {
      // 无条目可渲染（含全部失败）时不产出空片段，但保留已收集的警告。
      return HookWriteResult(warnings: warnings);
    }
    return HookWriteResult(
      configFragments: {'config.toml': buffer.toString()},
      scripts: scripts,
      warnings: warnings,
    );
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
    final path = '${ctx.hooksDir}/$scriptFileName';
    return ctx.runner?.commandStringForScriptFile(path) ?? path;
  }

  static String _escape(String value) =>
      value.replaceAll('\\', r'\\').replaceAll('"', r'\"');
}
