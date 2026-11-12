import '../../../../models/hook_entry.dart';
import '../../../../models/hook_event.dart';
import '../../../../models/team_config.dart';
import '../../../host/host_script_dialect.dart';
import '../../registry/capabilities/hook_capability.dart';
import '../../registry/capabilities/hook_registry.dart';

/// Grok hook renderer: `$GROK_HOME/hooks/teampilot.json`.
///
/// Grok reads Claude-compatible `{"hooks": {...}}` files from `hooks/*.json`
/// and accepts both `permissionDecision` and top-level `decision` outputs.
final class GrokHookWriter
    with BusProtocolHookDefaults
    implements HookCapability {
  const GrokHookWriter({this.denyReason = 'TeamPilot hook policy'});

  final String denyReason;

  static const fragmentFileName = 'hooks/teampilot.json';

  @override
  String? nativeEvent(HookEvent event) =>
      HookEventCapability.nativeEvent(event, CliTool.grok);

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
      final decisionJson =
          entry.policy == HookPolicy.none || !entry.event.isIntercepting
          ? null
          : entry.policy == HookPolicy.allow
          ? '{"decision":"allow"}'
          : '{"decision":"deny","reason":"$denyReason"}';
      final hooksList = List<Object?>.from(
        (hooks[native] as List?) ?? const [],
      );

      switch (entry.action) {
        case NativePluginHookAction _:
          warnings.add('hook_native_plugin_unsupported_${entry.id}');
          continue;
        case HttpHookAction http:
          final hookJson = <String, Object?>{
            'type': 'http',
            'url': http.url,
            if (entry.timeout != null) 'timeout': entry.timeout!.inSeconds,
          };
          hooksList.add({
            if (entry.matcher != null && entry.matcher!.trim().isNotEmpty)
              'matcher': entry.matcher,
            'hooks': [hookJson],
          });
        case CommandHookAction command:
          if (entry.scriptFileName != null && command.command != null) {
            hooksList.add({
              if (entry.matcher != null && entry.matcher!.trim().isNotEmpty)
                'matcher': entry.matcher,
              'hooks': [
                {
                  'type': 'command',
                  'command': command.command,
                  'timeout': entry.timeout?.inSeconds ?? 5,
                },
              ],
            });
          } else {
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
            final scriptFileName =
                'teampilot-hook-${entry.id}'
                '${runner?.dialect.scriptExtension ?? '.sh'}';
            scripts.add(
              GeneratedScript(fileName: scriptFileName, content: glue),
            );
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
      }
      hooks[native] = hooksList;
    }

    return HookWriteResult(
      configFragments: {
        fragmentFileName: {'hooks': hooks},
      },
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
}
