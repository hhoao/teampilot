import '../../../../models/hook_entry.dart';
import '../../../../models/hook_event.dart';
import '../../../../models/team_config.dart';
import '../../registry/capabilities/hook_registry.dart';
import '../../registry/capabilities/hook_writer_capability.dart';

const opencodeUserHooksPluginFileName = 'teampilot-user-hooks.js';

/// 一条 JS 订阅：glue 命令行；[tool] 非空 → `tool.execute.*` 按 tool 键限定
/// （opencode plugin 返回的函数式 hook 内 `input.tool` 正则过滤）。
class _OpencodeSubscription {
  const _OpencodeSubscription(this.command, {this.tool});

  final String command;
  final String? tool;
}

/// opencode 无原生 hooks，也无 http hooks —— 生成一个 JS plugin 桥：
/// plugin 返回函数值 hooks（仓库已验证模式，同 agent_status_plugin）：
/// `event` 函数按 `event.type`/`event.data.type` 分发非拦截订阅；tool.execute.*
/// 的函数式 hook 按 tool 键限定。每个 hook 用 Node `child_process` 跑 glue
/// 命令，stdout（决策 JSON）原样传回。
///
/// 共存说明：用户 hooks plugin（`teampilot-user-hooks.js`）与内部托管 plugin
/// （`teampilot-agent-status.js` / `teampilot-idle-bus.js`，事件订阅 + /agent-status
/// POST + /idle 报告）**平行安装**于 opencode.json `plugin` 数组 —— 两者都是
/// opencode 特有能力而非"hook 配置"，内部托管保持为专属 JS plugin，**不迁移**
/// 进本 writer。写入时经 `mergeOpencodePluginEntries` 按路径去重合并。
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
    final subscriptions = <String, List<_OpencodeSubscription>>{};

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
      // Matcher 仅对 tool.execute.before/after 生效（按 tool 键限定）；其余
      // 事件上的 matcher 忽略并警告（spec §2.1）。
      final matcher = entry.matcher?.trim() ?? '';
      final toolKeyed = matcher.isNotEmpty &&
          (native == 'tool.execute.before' || native == 'tool.execute.after');
      if (!toolKeyed && matcher.isNotEmpty) {
        warnings.add('hook_matcher_ignored_${entry.id}_${entry.event.name}');
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
      subscriptions
          .putIfAbsent(native, () => [])
          .add(_OpencodeSubscription(commandLine, tool: toolKeyed ? matcher : null));
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

  String _buildPluginSource(Map<String, List<_OpencodeSubscription>> subscriptions) {
    final toolHooks = <String, List<_OpencodeSubscription>>{};
    final eventHooks = <String, List<_OpencodeSubscription>>{};
    for (final entry in subscriptions.entries) {
      for (final sub in entry.value) {
        if (sub.tool != null) {
          (toolHooks[entry.key] ??= []).add(sub);
        } else {
          (eventHooks[entry.key] ??= []).add(sub);
        }
      }
    }
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
      ..writeln('  return {');
    // 非 tool.execute.* 订阅：`event` 函数按事件类型分发（仓库已验证模式）。
    if (eventHooks.isNotEmpty) {
      buffer.writeln('    event: async ({ event }) => {');
      buffer.writeln('      const evt = event?.type || event?.data?.type;');
      for (final entry in eventHooks.entries) {
        final event = entry.key.replaceAll('"', r'\"');
        for (final sub in entry.value) {
          final safe = sub.command.replaceAll('"', r'\"');
          buffer.writeln('      if (evt === "$event") {');
          buffer.writeln('        const out = await run("$safe");');
          buffer.writeln(
            '        try { return out ? JSON.parse(out) : {}; } catch (_) { return {}; }',
          );
          buffer.writeln('      }');
        }
      }
      buffer.writeln('    },');
    }
    // tool.execute.before/after：函数式 hook 按 `input.tool`（工具名）正则
    // 过滤，`{"decision":"deny"}` → throw 阻断工具调用。
    for (final entry in toolHooks.entries) {
      final event = entry.key.replaceAll('"', r'\"');
      final intercepting = entry.key == 'tool.execute.before';
      buffer.writeln('    "$event": async (ev, output) => {');
      for (final sub in entry.value) {
        final tool = sub.tool!.replaceAll('"', r'\"');
        final safe = sub.command.replaceAll('"', r'\"');
        buffer.writeln('      if (new RegExp("$tool").test(ev.tool)) {');
        if (intercepting) {
          buffer.writeln('        const out = await run("$safe");');
          buffer.writeln('        if (out) {');
          buffer.writeln('          let d = null;');
          buffer.writeln(
            '          try { d = JSON.parse(out); } catch (_) { return; }',
          );
          buffer.writeln(
            '          if (d && d.decision === "deny") '
            'throw new Error(d.reason || "denied by TeamPilot hook");',
          );
          buffer.writeln('        }');
        } else {
          buffer.writeln('        await run("$safe");');
        }
        buffer.writeln('      }');
      }
      buffer.writeln('    },');
    }
    buffer
      ..writeln('  };')
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
