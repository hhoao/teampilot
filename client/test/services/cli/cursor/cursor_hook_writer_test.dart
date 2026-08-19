import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/hook_entry.dart';
import 'package:teampilot/models/hook_event.dart';
import 'package:teampilot/services/cli/cursor/provider/cursor_hook_writer.dart';
import 'package:teampilot/services/cli/registry/capabilities/hook_capability.dart';
import 'package:teampilot/services/hook/glue_script_builder.dart';

void main() {
  const writer = CursorHookWriter();
  const ctx = HookRenderContext(
    hooksDir: '/s/hooks',
    runner: null,
    glueBuilder: GlueScriptBuilder(),
  );

  test('cursor events are lowercase native names', () {
    expect(
      writer.nativeEvent(HookEvent.userPromptSubmit),
      'beforeSubmitPrompt',
    );
    expect(writer.nativeEvent(HookEvent.preToolUse), 'preToolUse');
    expect(writer.nativeEvent(HookEvent.stop), 'stop');
    expect(writer.supportsEvent(HookEvent.permissionRequest), isFalse);
  });

  test('renders hooks.json with command, matcher, loop_limit', () {
    final entry = HookEntry(
      id: 'h1',
      source: HookSource.userLibrary,
      event: HookEvent.preToolUse,
      matcher: 'Shell|Read|Write',
      timeout: Duration(seconds: 20),
      action: CommandHookAction.raw('echo hi'),
    );
    final result = writer.render(entries: [entry], ctx: ctx);
    expect(result.warnings, isEmpty);
    final hooksJson = result.configFragments['hooks.json']! as Map;
    expect(hooksJson['version'], 1);
    final pre =
        ((hooksJson['hooks'] as Map)['preToolUse'] as List).single as Map;
    expect(pre['matcher'], 'Shell|Read|Write');
    expect(pre['timeout'], 20);
    final command = pre['command'] as String;
    expect(command, contains('/s/hooks/teampilot-hook-h1.sh'));
  });

  test('stop hook gets loop_limit null; policy deny renders cursor JSON', () {
    final entry = HookEntry(
      id: 'h1',
      source: HookSource.userLibrary,
      event: HookEvent.stop,
      action: CommandHookAction.raw('echo done'),
    );
    final result = writer.render(entries: [entry], ctx: ctx);
    final stop =
        ((result.configFragments['hooks.json'] as Map)['hooks'] as Map)['stop']
            as List;
    expect((stop.single as Map)['loop_limit'], isNull);
  });

  test('policy deny on preToolUse injects cursor permission JSON', () {
    final entry = HookEntry(
      id: 'h1',
      source: HookSource.userLibrary,
      event: HookEvent.preToolUse,
      policy: HookPolicy.deny,
      action: CommandHookAction.raw('echo hi'),
    );
    final result = writer.render(entries: [entry], ctx: ctx);
    final glue = result.scripts.single;
    expect(glue.content, contains('"permission":"deny"'));
  });

  test('http agent-status entry renders bash forwarding script', () {
    final entry = HookEntry(
      id: 'teampilot-agent-status-stop',
      source: HookSource.managed,
      event: HookEvent.stop,
      timeout: Duration(seconds: 5),
      action: HttpHookAction(
        url: 'http://127.0.0.1:1/agent-status?event=Stop',
        headers: {'X-Member': 'm1'},
      ),
    );
    final result = writer.render(entries: [entry], ctx: ctx);
    expect(result.warnings, isEmpty);
    final script = result.scripts.singleWhere(
      (s) => s.fileName == 'teampilot-http-teampilot-agent-status-stop-stop.sh',
    );
    expect(script.content, contains("curl -sS -X POST"));
    expect(
      script.content,
      contains("'http://127.0.0.1:1/agent-status?event=Stop'"),
    );
    expect(script.content, contains("'X-Member: m1'"));
    final hooksJson = result.configFragments['hooks.json']! as Map;
    final stop = ((hooksJson['hooks'] as Map)['stop'] as List).single as Map;
    expect(
      stop['command'],
      contains('teampilot-http-teampilot-agent-status-stop-stop.sh'),
    );
    expect(stop['timeout'], isNotNull);
  });

  test('bus idle hook prints followup_message on decision:block', () {
    final entry = HookEntry(
      id: 'teampilot-bus-idle-stop',
      source: HookSource.managed,
      event: HookEvent.stop,
      blockOnDecision: true,
      timeout: Duration(seconds: 5),
      action: HttpHookAction(
        url: 'http://127.0.0.1:2/idle',
        headers: {'X-Member': 'm1'},
      ),
    );
    final result = writer.render(entries: [entry], ctx: ctx);
    final script = result.scripts.single;
    expect(script.content, contains('"decision":"block"'));
    expect(script.content, contains('followup_message'));
    expect(script.content, contains('exit 0'));
  });

  test('managed + user entries merge idempotently by command', () {
    final agentStatus = HookEntry(
      id: 'teampilot-agent-status-stop',
      source: HookSource.managed,
      event: HookEvent.stop,
      action: HttpHookAction(url: 'http://127.0.0.1:1/agent-status?event=Stop'),
    );
    final userHook = HookEntry(
      id: 'h1',
      source: HookSource.userLibrary,
      event: HookEvent.stop,
      action: CommandHookAction.raw('echo done'),
    );
    const ctx = HookRenderContext(
      hooksDir: '/h/hooks',
      runner: null,
      glueBuilder: GlueScriptBuilder(),
    );
    final result = writer.render(entries: [agentStatus, userHook], ctx: ctx);
    final stop =
        ((result.configFragments['hooks.json'] as Map)['hooks'] as Map)['stop']
            as List;
    expect(stop, hasLength(2));
    final re = writer.render(entries: [agentStatus, userHook], ctx: ctx);
    expect(
      ((re.configFragments['hooks.json'] as Map)['hooks'] as Map)['stop'],
      hasLength(2),
    );
  });
}
