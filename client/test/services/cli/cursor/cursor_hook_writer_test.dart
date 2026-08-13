import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/hook_entry.dart';
import 'package:teampilot/models/hook_event.dart';
import 'package:teampilot/services/cli/cursor/provider/cursor_hook_writer.dart';
import 'package:teampilot/services/cli/registry/capabilities/hook_writer_capability.dart';
import 'package:teampilot/services/hook/glue_script_builder.dart';

void main() {
  const writer = CursorHookWriter();
  const ctx = HookRenderContext(
    hooksDir: '/s/hooks',
    runner: null,
    glueBuilder: GlueScriptBuilder(),
  );

  test('cursor events are lowercase native names', () {
    expect(writer.nativeEvent(HookEvent.userPromptSubmit), 'beforeSubmitPrompt');
    expect(writer.nativeEvent(HookEvent.preToolUse), 'preToolUse');
    expect(writer.nativeEvent(HookEvent.stop), 'stop');
    expect(writer.supportsEvent(HookEvent.permissionRequest), isFalse);
  });

  test('renders hooks.json with command, matcher, loop_limit', () {
    const entry = HookEntry(
      id: 'h1',
      source: HookSource.userLibrary,
      event: HookEvent.preToolUse,
      matcher: 'Shell|Read|Write',
      timeout: Duration(seconds: 20),
      action: CommandHookAction.raw('echo hi'),
    );
    final result = writer.render(entries: const [entry], ctx: ctx);
    expect(result.warnings, isEmpty);
    final hooksJson = result.configFragments['hooks.json']! as Map;
    expect(hooksJson['version'], 1);
    final pre = ((hooksJson['hooks'] as Map)['preToolUse'] as List).single
        as Map;
    expect(pre['matcher'], 'Shell|Read|Write');
    expect(pre['timeout'], 20);
    final command = pre['command'] as String;
    expect(command, contains('/s/hooks/teampilot-hook-h1.sh'));
  });

  test('stop hook gets loop_limit null; policy deny renders cursor JSON', () {
    const entry = HookEntry(
      id: 'h1',
      source: HookSource.userLibrary,
      event: HookEvent.stop,
      action: CommandHookAction.raw('echo done'),
    );
    final result = writer.render(entries: const [entry], ctx: ctx);
    final stop = ((result.configFragments['hooks.json'] as Map)['hooks']
        as Map)['stop'] as List;
    expect((stop.single as Map)['loop_limit'], isNull);
  });

  test('policy deny on preToolUse injects cursor permission JSON', () {
    const entry = HookEntry(
      id: 'h1',
      source: HookSource.userLibrary,
      event: HookEvent.preToolUse,
      policy: HookPolicy.deny,
      action: CommandHookAction.raw('echo hi'),
    );
    final result = writer.render(entries: const [entry], ctx: ctx);
    final glue = result.scripts.single;
    expect(glue.content, contains('"permission":"deny"'));
  });

  test('http action unsupported → warning', () {
    const entry = HookEntry(
      id: 'h1',
      source: HookSource.userLibrary,
      event: HookEvent.stop,
      action: HttpHookAction(url: 'http://x'),
    );
    final result = writer.render(entries: const [entry], ctx: ctx);
    expect(result.warnings, contains('hook_http_unsupported_h1'));
    expect(result.configFragments, isEmpty);
  });
}
