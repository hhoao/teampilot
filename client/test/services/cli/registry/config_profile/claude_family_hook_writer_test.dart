import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/hook_entry.dart';
import 'package:teampilot/models/hook_event.dart';
import 'package:teampilot/services/cli/registry/config_profile/claude_family_hook_writer.dart';
import 'package:teampilot/services/cli/registry/capabilities/hook_capability.dart';
import 'package:teampilot/services/host/host_execution_environment.dart';
import 'package:teampilot/services/host/host_script_dialect.dart';
import 'package:teampilot/services/host/host_script_runner.dart';
import 'package:teampilot/services/host/team_pilot_hook_scripts.dart';
import 'package:teampilot/services/hook/glue_script_builder.dart';
import 'package:teampilot/services/storage/runtime_context.dart';

HookRenderContext bashCtx(String hooksDir) => HookRenderContext(
  hooksDir: hooksDir,
  runner: HostScriptRunner(
    const HostExecutionEnvironment(
      dialect: HostScriptDialect.bash,
      isWindowsHost: false,
      storageMode: StorageBackendMode.native,
    ),
  ),
  glueBuilder: const GlueScriptBuilder(),
);

void main() {
  const writer = ClaudeFamilyHookWriter();

  test(
    'raw preToolUse deny hook renders glue + native event + policy json',
    () {
      final entry = HookEntry(
        id: 'h1',
        source: HookSource.userLibrary,
        event: HookEvent.preToolUse,
        matcher: 'Bash',
        policy: HookPolicy.deny,
        action: CommandHookAction.raw('echo hi'),
      );
      final result = writer.render(entries: [entry], ctx: bashCtx('/s/hooks'));
      expect(result.warnings, isEmpty);
      final section = result.configFragments['settings.json']! as Map;
      final pre = (section['hooks'] as Map)['PreToolUse'] as List;
      final entryJson = pre.single as Map;
      expect(entryJson['matcher'], 'Bash');
      final hook = ((entryJson['hooks'] as List).single) as Map;
      expect(hook['type'], 'command');
      final command = hook['command'] as String;
      expect(command, contains('/s/hooks/teampilot-hook-h1.sh'));
      expect(hook['timeout'], 5);
      // 胶水脚本含决策 JSON
      final glue = result.scripts.singleWhere(
        (s) => s.fileName == 'teampilot-hook-h1.sh',
      );
      expect(glue.content, contains('"permissionDecision":"deny"'));
    },
  );

  test('compatibility basename preserves the legacy command and config', () {
    final entry = HookEntry(
      id: 'teampilot-team-lead-self-SendMessage',
      source: HookSource.managed,
      event: HookEvent.preToolUse,
      matcher: 'SendMessage',
      action: CommandHookAction.raw(
        'bash "/s/hooks/${TeamPilotHookScripts.teamLeadSelf}.sh"',
      ),
      scriptFileName: TeamPilotHookScripts.teamLeadSelf,
    );

    final result = writer.render(entries: [entry], ctx: bashCtx('/s/hooks'));
    final section = result.configFragments['settings.json']! as Map;
    final pre = (section['hooks'] as Map)['PreToolUse'] as List;
    final hookGroup = pre.single as Map;
    final hook = ((hookGroup['hooks'] as List).single) as Map;

    expect(hook['command'], contains('${TeamPilotHookScripts.teamLeadSelf}.sh'));
    expect(result.scripts, isEmpty);
  });

  test('http action renders native http hook', () {
    final entry = HookEntry(
      id: 'h2',
      source: HookSource.userLibrary,
      event: HookEvent.stop,
      action: HttpHookAction(
        url: 'http://127.0.0.1:1/hook',
        headers: {'X-A': 'b'},
      ),
    );
    final result = writer.render(entries: [entry], ctx: bashCtx('/s/h'));
    final section = result.configFragments['settings.json']! as Map;
    final stop = (section['hooks'] as Map)['Stop'] as List;
    final hook = (((stop.single as Map)['hooks'] as List).single) as Map;
    expect(hook['type'], 'http');
    expect(hook['url'], 'http://127.0.0.1:1/hook');
    expect(hook['headers'], {'X-A': 'b'});
  });

  test('http action with matcher renders entry-level matcher', () {
    final entry = HookEntry(
      id: 'h5',
      source: HookSource.managed,
      event: HookEvent.preToolUse,
      matcher: '*',
      action: HttpHookAction(
        url: 'http://127.0.0.1:1/status?event=PreToolUse',
        headers: {'X-Member': 'm1'},
      ),
    );
    final result = writer.render(entries: [entry], ctx: bashCtx('/s/h'));
    final section = result.configFragments['settings.json']! as Map;
    final pre = (section['hooks'] as Map)['PreToolUse'] as List;
    final entryJson = pre.single as Map;
    expect(entryJson['matcher'], '*');
    final hook = ((entryJson['hooks'] as List).single) as Map;
    expect(hook['type'], 'http');
    expect(hook['url'], contains('event=PreToolUse'));
  });

  test('unsupported event and script-action script file are written', () {
    final entry = HookEntry(
      id: 'h3',
      source: HookSource.userLibrary,
      event: HookEvent.stopFailure, // supported
      action: CommandHookAction.script(
        fileName: 'hook.sh',
        scriptContent: 'echo hi',
      ),
    );
    final result = writer.render(entries: [entry], ctx: bashCtx('/s/h'));
    // 托管脚本也作为 GeneratedScript 写出
    expect(result.scripts.any((s) => s.fileName == 'h3/hook.sh'), isTrue);
    expect(result.warnings, isEmpty);
  });

  test('policy on non-intercepting event warns', () {
    final entry = HookEntry(
      id: 'h4',
      source: HookSource.userLibrary,
      event: HookEvent.stop,
      policy: HookPolicy.deny,
      action: CommandHookAction.raw('echo hi'),
    );
    final result = writer.render(entries: [entry], ctx: bashCtx('/s/h'));
    expect(result.warnings, ['hook_policy_ignored_h4_stop']);
  });

  test('idempotent render: same entry renders same fragment', () {
    final entry = HookEntry(
      id: 'h1',
      source: HookSource.userLibrary,
      event: HookEvent.stop,
      action: CommandHookAction.raw('echo hi'),
    );
    final a = writer.render(entries: [entry], ctx: bashCtx('/s/h'));
    final b = writer.render(entries: [entry], ctx: bashCtx('/s/h'));
    expect(a.configFragments, b.configFragments);
  });
}
