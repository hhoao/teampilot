import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/hook_entry.dart';
import 'package:teampilot/models/hook_event.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/antigravity/capabilities/hook_writer.dart';
import 'package:teampilot/services/cli/registry/capabilities/hook_capability.dart';
import 'package:teampilot/services/cli/registry/built_in_cli_tools.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/hook/glue_script_builder.dart';

void main() {
  const writer = AntigravityHookWriter();
  const ctx = HookRenderContext(
    hooksDir: '/hooks',
    runner: null,
    glueBuilder: GlueScriptBuilder(),
  );

  HookEntry entry({
    String id = 'guard',
    HookEvent event = HookEvent.preToolUse,
    String? matcher,
    HookAction? action,
    HookPolicy policy = HookPolicy.none,
    Duration? timeout,
    String? scriptFileName,
    bool blockOnDecision = false,
  }) => HookEntry(
    id: id,
    source: HookSource.userLibrary,
    event: event,
    matcher: matcher,
    action: action ?? CommandHookAction.raw('echo blocked'),
    policy: policy,
    timeout: timeout,
    scriptFileName: scriptFileName,
    blockOnDecision: blockOnDecision,
  );

  Map<String, Object?> hooksJson(HookWriteResult result) =>
      (result.configFragments['hooks.json']! as Map).cast<String, Object?>();

  group('event matrix', () {
    test('maps the six native events to normalised hook events', () {
      expect(AntigravityHookWriter.nativeEvents, hasLength(6));
      expect(writer.nativeEvent(HookEvent.sessionStart), 'SessionStart');
      expect(writer.nativeEvent(HookEvent.userPromptSubmit), 'PreInvocation');
      expect(writer.nativeEvent(HookEvent.preToolUse), 'PreToolUse');
      expect(writer.nativeEvent(HookEvent.postToolUse), 'PostToolUse');
      expect(writer.nativeEvent(HookEvent.stop), 'Stop');
      expect(writer.nativeEvent(HookEvent.sessionEnd), isNull);
      expect(writer.nativeEvent(HookEvent.preCompact), isNull);
      expect(writer.supportsEvent(HookEvent.preCompact), isFalse);
    });

    test('userPromptSubmit is approximate; tool events are exact', () {
      expect(
        HookEventCapability.support(
          HookEvent.userPromptSubmit,
          CliTool.antigravity,
        ).approximate,
        isTrue,
      );
      expect(
        HookEventCapability.support(
          HookEvent.preToolUse,
          CliTool.antigravity,
        ).approximate,
        isFalse,
      );
    });

    test('registers the hook writer capability on the tool', () {
      final registry = CliToolRegistry();
      registerBuiltInCliTools(registry);
      expect(
        registry.capability<HookCapability>(CliTool.antigravity),
        isA<AntigravityHookWriter>(),
      );
    });
  });

  group('render', () {
    test('renders hooks.json with a PreToolUse matcher and script path', () {
      final result = writer.render(
        entries: [entry(matcher: 'run_command')],
        ctx: ctx,
      );
      expect(result.warnings, isEmpty);

      final fragment = result.configFragments['hooks.json'];
      expect(fragment, isA<Map<String, Object?>>());
      final json = jsonEncode(fragment);
      expect(json, contains('"PreToolUse"'));
      expect(json, contains('"matcher":"run_command"'));

      final hook = (hooksJson(result)['teampilot-guard'] as Map)
          .cast<String, Object?>();
      final group = (hook['PreToolUse'] as List).single as Map;
      expect(group['matcher'], 'run_command');
      final inner = (group['hooks'] as List).single as Map;
      expect(inner['type'], 'command');
      expect(inner['command'], '/hooks/teampilot-hook-guard-preToolUse.sh');
      expect(inner['timeout'], AntigravityHookWriter.defaultTimeoutSeconds);
      expect(
        result.scripts.single.fileName,
        'teampilot-hook-guard-preToolUse.sh',
      );
    });

    test('omits the matcher when blank and honours an explicit timeout', () {
      final result = writer.render(
        entries: [entry(matcher: '  ', timeout: const Duration(seconds: 3))],
        ctx: ctx,
      );
      final group =
          ((hooksJson(result)['teampilot-guard'] as Map)['PreToolUse'] as List)
                  .single
              as Map;
      expect(group.containsKey('matcher'), isFalse);
      expect((group['hooks'] as List).single, containsPair('timeout', 3));
    });

    test('deny policy injects Antigravity decision JSON into the glue', () {
      final result = writer.render(
        entries: [entry(policy: HookPolicy.deny)],
        ctx: ctx,
      );
      expect(
        result.scripts.single.content,
        contains('{"decision":"deny","reason":"TeamPilot hook policy"}'),
      );
    });

    test('deny reason quotes and backslashes stay valid JSON', () {
      const reason = r'He said "no" to C:\temp';
      const custom = AntigravityHookWriter(denyReason: reason);
      final result = custom.render(
        entries: [entry(policy: HookPolicy.deny)],
        ctx: ctx,
      );
      final decision = RegExp(
        r"DECISION='(.+)'",
      ).firstMatch(result.scripts.single.content)!.group(1)!;
      final decoded = jsonDecode(decision) as Map<String, Object?>;
      expect(decoded['decision'], 'deny');
      expect(decoded['reason'], reason);
    });

    test('allow policy injects {"decision":"allow"}', () {
      final result = writer.render(
        entries: [entry(policy: HookPolicy.allow)],
        ctx: ctx,
      );
      expect(result.scripts.single.content, contains('{"decision":"allow"}'));
    });

    test('policy on a non-intercepting event is ignored with a warning', () {
      final result = writer.render(
        entries: [entry(event: HookEvent.stop, policy: HookPolicy.deny)],
        ctx: ctx,
      );
      expect(result.warnings, contains('hook_policy_ignored_guard_stop'));
      expect(result.scripts.single.content, isNot(contains('DECISION=')));
    });

    test('matcher on a non-tool event is written through and warned', () {
      final result = writer.render(
        entries: [entry(event: HookEvent.sessionStart, matcher: 'run_command')],
        ctx: ctx,
      );
      expect(
        result.warnings,
        contains('hook_matcher_ignored_guard_sessionStart'),
      );
      final group =
          ((hooksJson(result)['teampilot-guard'] as Map)['SessionStart']
                      as List)
                  .single
              as Map;
      expect(group['matcher'], 'run_command');
    });

    test('PreToolUse and PostToolUse matchers are not warned', () {
      for (final event in [HookEvent.preToolUse, HookEvent.postToolUse]) {
        final result = writer.render(
          entries: [entry(event: event, matcher: 'run_command')],
          ctx: ctx,
        );
        expect(result.warnings, isEmpty, reason: event.name);
      }
    });

    test('http hooks are unsupported and warned', () {
      final result = writer.render(
        entries: [
          entry(action: HttpHookAction(url: 'http://127.0.0.1:1/hook')),
        ],
        ctx: ctx,
      );
      expect(result.warnings, contains('hook_http_unsupported_guard'));
      expect(result.configFragments, isEmpty);
      expect(result.scripts, isEmpty);
    });

    test('native plugin hook actions are unsupported and warned', () {
      final result = writer.render(
        entries: [
          entry(
            action: NativePluginHookAction(
              fileName: 'plugin.json',
              source: 'antigravity',
              pluginPath: '/plugins/p',
            ),
          ),
        ],
        ctx: ctx,
      );
      expect(result.warnings, contains('hook_native_plugin_unsupported_guard'));
      expect(result.configFragments, isEmpty);
    });

    test('unsupported event is warned and skipped', () {
      final result = writer.render(
        entries: [entry(event: HookEvent.preCompact)],
        ctx: ctx,
      );
      expect(
        result.warnings,
        contains('hook_unsupported_event_guard_preCompact'),
      );
      expect(result.configFragments, isEmpty);
    });

    test('sessionStart maps to SessionStart', () {
      final result = writer.render(
        entries: [entry(event: HookEvent.sessionStart)],
        ctx: ctx,
      );
      expect(
        (hooksJson(result)['teampilot-guard'] as Map).containsKey(
          'SessionStart',
        ),
        isTrue,
      );
    });

    test('compatibility scriptFileName keeps the raw command', () {
      final result = writer.render(
        entries: [
          entry(
            action: CommandHookAction.raw('/hooks/custom.sh'),
            scriptFileName: 'custom.sh',
          ),
        ],
        ctx: ctx,
      );
      final group =
          ((hooksJson(result)['teampilot-guard'] as Map)['PreToolUse'] as List)
                  .single
              as Map;
      expect(
        (group['hooks'] as List).single,
        containsPair('command', '/hooks/custom.sh'),
      );
      expect(result.scripts, isEmpty);
    });

    test('groups multiple entries by event under the same hook name', () {
      final result = writer.render(
        entries: [
          entry(matcher: 'run_command'),
          entry(matcher: 'read_file', action: CommandHookAction.raw('echo 2')),
        ],
        ctx: ctx,
      );
      final hook = (hooksJson(result)['teampilot-guard'] as Map)
          .cast<String, Object?>();
      final groups = hook['PreToolUse'] as List;
      expect(groups, hasLength(2));

      final scripts = result.scripts.map((s) => s.fileName).toList();
      expect(scripts, [
        'teampilot-hook-guard-preToolUse.sh',
        'teampilot-hook-guard-preToolUse-2.sh',
      ]);
      final commands = groups.map((group) {
        final hooks = (group as Map)['hooks'] as List;
        return (hooks.single as Map)['command'];
      }).toList();
      expect(commands, [
        '/hooks/teampilot-hook-guard-preToolUse.sh',
        '/hooks/teampilot-hook-guard-preToolUse-2.sh',
      ]);
    });

    test('fragments from two provisions merge into valid JSON', () {
      final first = writer.render(
        entries: [entry(id: 'a')],
        ctx: ctx,
      );
      final second = writer.render(
        entries: [entry(id: 'b', event: HookEvent.stop)],
        ctx: ctx,
      );
      expect(first.configFragments['hooks.json'], isA<Map<String, Object?>>());
      expect(second.configFragments['hooks.json'], isA<Map<String, Object?>>());

      final merged = <String, Object?>{
        ...hooksJson(first),
        ...hooksJson(second),
      };
      final roundTrip = jsonDecode(jsonEncode(merged)) as Map<String, Object?>;
      expect(
        roundTrip.keys,
        containsAll(<String>['teampilot-a', 'teampilot-b']),
      );
    });
  });
}
