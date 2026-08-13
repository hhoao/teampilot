import '../../../../models/hook_entry.dart';
import '../../../../models/hook_event.dart';
import '../../../../models/team_config.dart';
import '../../registry/capabilities/hook_registry.dart';
import '../../registry/capabilities/hook_writer_capability.dart';

const opencodeUserHooksPluginFileName = 'teampilot-user-hooks.js';

/// opencode 无原生 hooks —— 生成一个 JS plugin 桥：
/// 订阅 SDK 事件（`input.client.events.on`），对每个 hook 用 Node
/// `child_process` 跑 glue 命令，stdout（决策 JSON）原样传回。
class OpencodeHookWriter implements HookWriterCapability {
  const OpencodeHookWriter({this.denyReason = 'TeamPilot hook policy'});

  final String denyReason;

  @override
  String? nativeEvent(HookEvent event) =>
      HookEventCapability.nativeEvent(event, CliTool.opencode);

  @override
  bool get supportsMatcher => true;
  @override
  bool get supportsHttp => false;
  @override
  bool get supportsPolicy => true;

  @override
  bool supportsEvent(HookEvent event) => nativeEvent(event) != null;

  @override
  HookWriteResult render({
    required List<HookEntry> entries,
    required HookRenderContext ctx,
  }) {
    final scripts = <GeneratedScript>[];
    final warnings = <String>[];
    final subscriptions = <String, List<String>>{}; // nativeEvent -> command

    for (final entry in entries) {
      final native = nativeEvent(entry.event);
      if (native == null) {
        warnings.add('hook_unsupported_event_${entry.id}_${entry.event.name}');
        continue;
      }
      if (entry.action is HttpHookAction) {
        warnings.add('hook_http_unsupported_${entry.id}');
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
          ? '{"decision":"allow"}'
          : '{"decision":"deny","reason":"$denyReason"}';
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
      final commandLine = "bash '${ctx.hooksDir}/$scriptFileName'";
      subscriptions.putIfAbsent(native, () => []).add(commandLine);
    }

    if (subscriptions.isEmpty) {
      return HookWriteResult(warnings: warnings);
    }
    scripts.add(
      GeneratedScript(
        fileName: opencodeUserHooksPluginFileName,
        content: _buildPluginSource(subscriptions),
      ),
    );
    return HookWriteResult(
      configFragments: {
        'opencode.json': {
          'plugin': ['./$opencodeUserHooksPluginFileName'],
        },
      },
      scripts: scripts,
      warnings: warnings,
    );
  }

  String _buildPluginSource(Map<String, List<String>> subscriptions) {
    final buffer = StringBuffer()
      ..writeln('export const TeampilotUserHooks = async (input, options) => {')
      ..writeln('  const { execFile } = require("node:child_process");')
      ..writeln('  const run = (command) =>')
      ..writeln(
        '    new Promise((resolve) => {'
        ' execFile(command.split(/\\s+/)[0], '
        'command.split(/\\s+/).slice(1), '
        '{ encoding: "utf8" }, (err, stdout) => resolve(stdout || null)); });',
      )
      ..writeln('  const on = (event, handler) => {');
    for (final entry in subscriptions.entries) {
      final event = entry.key.replaceAll('"', r'\"');
      for (final command in entry.value) {
        final safe = command.replaceAll('"', r'\"');
        buffer.writeln(
          '    if (input.client?.events?.on) '
          'input.client.events.on("$event", async () => {'
          ' const out = await run("$safe"); return out ? JSON.parse(out) : {}; });',
        );
      }
    }
    buffer
      ..writeln('  };')
      ..writeln('  on();')
      ..writeln('};');
    return buffer.toString();
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
