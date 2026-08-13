import '../../../../models/hook_entry.dart';
import '../../../../models/hook_event.dart';
import '../../../../models/team_config.dart';
import '../../../host/host_script_dialect.dart';
import '../../registry/capabilities/hook_registry.dart';
import '../../registry/capabilities/hook_writer_capability.dart';

/// Codex hook writer：`config.toml` 的 `[[hooks.<Event>]]` 片段。
class CodexHookWriter implements HookWriterCapability {
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
        // codex TOML 原生 http 类 hook（url + headers）在此渲染。
        final timeout = entry.timeout?.inSeconds;
        if (!first) buffer.writeln();
        buffer.writeln('[[hooks.$native]]');
        buffer.writeln();
        buffer.writeln('[[hooks.$native.hooks]]');
        buffer.writeln('type = "http"');
        buffer.writeln(
          'url = "${command.url.replaceAll('\\', r'\\').replaceAll('"', r'\"')}"',
        );
        if (command.headers.isNotEmpty) {
          final escapedHeaders = command.headers.entries
              .map(
                (e) =>
                    '"${e.key.replaceAll('\\', r'\\').replaceAll('"', r'\"')}" = '
                    '"${e.value.replaceAll('\\', r'\\').replaceAll('"', r'\"')}"',
              )
              .join(', ');
          buffer.writeln('headers = {$escapedHeaders}');
        }
        if (timeout != null) buffer.writeln('timeout = $timeout');
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
      // 无条目时不产出空片段。
      return const HookWriteResult(warnings: []);
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
