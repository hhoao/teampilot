import 'dart:convert';

import '../../../../models/hook_entry.dart';
import '../../../../models/hook_event.dart';
import '../../../../models/team_config.dart';
import '../../../host/host_script_dialect.dart';
import '../../registry/capabilities/hook_capability.dart';
import '../../registry/capabilities/hook_registry.dart';

/// Antigravity hook renderer: `<configDir>/hooks.json`.
///
/// Antigravity keys the file by hook name, then by native event:
///
/// ```json
/// {
///   "teampilot-<id>": {
///     "PreToolUse": [
///       {
///         "matcher": "run_command",
///         "hooks": [
///           {"type": "command", "command": "<script>", "timeout": 10}
///         ]
///       }
///     ]
///   }
/// }
/// ```
///
/// Only command hooks are native: HTTP entries and target-native plugin
/// artifacts are reported as warnings instead of being silently dropped.
final class AntigravityHookWriter implements HookCapability {
  const AntigravityHookWriter({this.denyReason = 'TeamPilot hook policy'});

  /// Default per-hook timeout, in seconds.
  static const int defaultTimeoutSeconds = 10;

  /// Native Antigravity hook events.
  ///
  /// `PostInvocation` has no normalized [HookEvent] counterpart yet, so it is
  /// listed here for the native contract but never emitted by [render].
  static const Set<String> nativeEvents = {
    'SessionStart',
    'PreToolUse',
    'PostToolUse',
    'PreInvocation',
    'PostInvocation',
    'Stop',
  };

  final String denyReason;

  /// Native events whose matcher groups the CLI actually evaluates.
  static const Set<String> matcherEvents = {'PreToolUse', 'PostToolUse'};

  static bool _supportsMatcher(String native) => matcherEvents.contains(native);

  @override
  String? nativeEvent(HookEvent event) =>
      HookEventCapability.nativeEvent(event, CliTool.antigravity);

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
    final hooks = <String, Object?>{};
    final scripts = <GeneratedScript>[];
    final warnings = <String>[];
    final runner = ctx.runner;
    final usedScriptFileNames = <String>{};

    for (final entry in entries) {
      final native = nativeEvent(entry.event);
      if (native == null) {
        warnings.add('hook_unsupported_event_${entry.id}_${entry.event.name}');
        continue;
      }
      if (entry.policy != HookPolicy.none && !entry.event.isIntercepting) {
        warnings.add('hook_policy_ignored_${entry.id}_${entry.event.name}');
      }
      // Antigravity only honours matchers on the two tool events. The matcher is
      // still written through (the CLI ignores it), and the user is warned.
      if ((entry.matcher?.trim().isNotEmpty ?? false) &&
          !_supportsMatcher(native)) {
        warnings.add('hook_matcher_ignored_${entry.id}_${entry.event.name}');
      }
      final decisionJson =
          entry.policy == HookPolicy.none || !entry.event.isIntercepting
          ? null
          : entry.policy == HookPolicy.allow
          ? '{"decision":"allow"}'
          : jsonEncode({'decision': 'deny', 'reason': denyReason});

      final action = entry.action;
      if (action is NativePluginHookAction) {
        warnings.add('hook_native_plugin_unsupported_${entry.id}');
        continue;
      }
      if (action is HttpHookAction) {
        warnings.add('hook_http_unsupported_${entry.id}');
        continue;
      }
      if (action is! CommandHookAction) {
        warnings.add('hook_invalid_action_${entry.id}');
        continue;
      }

      final String command;
      if (entry.scriptFileName != null && action.command != null) {
        // Compatibility: keep a previously provisioned script basename.
        command = action.command!;
      } else {
        final inner = _innerCommand(action, entry.id, ctx, scripts);
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
        final scriptFileName = _uniqueScriptFileName(
          'teampilot-hook-${entry.id}-${entry.event.name}',
          runner?.dialect.scriptExtension ?? '.sh',
          usedScriptFileNames,
        );
        scripts.add(GeneratedScript(fileName: scriptFileName, content: glue));
        command = runner == null
            ? '${ctx.hooksDir}/$scriptFileName'
            : runner.commandStringForScriptFile(
                '${ctx.hooksDir}/$scriptFileName',
              );
      }

      final groups = List<Object?>.from(
        (hooks['teampilot-${entry.id}'] as Map?)?[native] as List? ?? const [],
      );
      groups.add({
        if (entry.matcher != null && entry.matcher!.trim().isNotEmpty)
          'matcher': entry.matcher,
        'hooks': [
          {
            'type': 'command',
            'command': command,
            'timeout': entry.timeout?.inSeconds ?? defaultTimeoutSeconds,
          },
        ],
      });
      final hook = Map<String, Object?>.from(
        (hooks['teampilot-${entry.id}'] as Map?) ?? const {},
      );
      hook[native] = groups;
      hooks['teampilot-${entry.id}'] = hook;
    }

    if (hooks.isEmpty) {
      return HookWriteResult(scripts: scripts, warnings: warnings);
    }
    return HookWriteResult(
      configFragments: {'hooks.json': hooks},
      scripts: scripts,
      warnings: warnings,
    );
  }

  /// Disambiguates scripts that share the same id + event (for example, two
  /// user-library hooks on `PreToolUse`) so one provision never overwrites the
  /// other's glue script.
  static String _uniqueScriptFileName(
    String base,
    String extension,
    Set<String> used,
  ) {
    var candidate = '$base$extension';
    var index = 2;
    while (!used.add(candidate)) {
      candidate = '$base-$index$extension';
      index++;
    }
    return candidate;
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
