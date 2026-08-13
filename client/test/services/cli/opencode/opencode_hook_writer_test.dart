import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/hook_entry.dart';
import 'package:teampilot/models/hook_event.dart';
import 'package:teampilot/services/cli/opencode/capabilities/opencode_hook_writer.dart';
import 'package:teampilot/services/cli/registry/capabilities/hook_writer_capability.dart';
import 'package:teampilot/services/hook/glue_script_builder.dart';

void main() {
  const writer = OpencodeHookWriter();
  const ctx = HookRenderContext(
    hooksDir: '/s/hooks',
    runner: null,
    glueBuilder: GlueScriptBuilder(),
  );

  test('bridge supports tool + permission + stop events only', () {
    expect(writer.supportsEvent(HookEvent.preToolUse), isTrue);
    expect(writer.supportsEvent(HookEvent.stop), isTrue);
    expect(writer.supportsEvent(HookEvent.sessionStart), isFalse);
  });

  test('renders plugin entry + JS source with event subscriptions', () {
    const entry = HookEntry(
      id: 'h1',
      source: HookSource.userLibrary,
      event: HookEvent.preToolUse,
      matcher: 'bash',
      action: CommandHookAction.raw('echo hi'),
    );
    final result = writer.render(entries: const [entry], ctx: ctx);
    expect(result.warnings, isEmpty);
    final opencodeJson = result.configFragments['opencode.json']! as Map;
    expect(opencodeJson['plugin'], ['./teampilot-user-hooks.js']);
    final js = result.scripts.singleWhere(
      (s) => s.fileName == 'teampilot-user-hooks.js',
    );
    expect(js.content, contains('tool.execute.before'));
    expect(js.content, contains('/s/hooks/teampilot-hook-h1.sh'));
  });

  test('policy deny injects decision bridge contract', () {
    const entry = HookEntry(
      id: 'h1',
      source: HookSource.userLibrary,
      event: HookEvent.permissionRequest,
      policy: HookPolicy.deny,
      action: CommandHookAction.raw('echo hi'),
    );
    final result = writer.render(entries: const [entry], ctx: ctx);
    final glue = result.scripts.singleWhere(
      (s) => s.fileName == 'teampilot-hook-h1.sh',
    );
    expect(glue.content, contains('"decision":"deny"'));
  });

  test('unsupported events warn', () {
    const entry = HookEntry(
      id: 'h1',
      source: HookSource.userLibrary,
      event: HookEvent.sessionStart,
      action: CommandHookAction.raw('echo hi'),
    );
    final result = writer.render(entries: const [entry], ctx: ctx);
    expect(
      result.warnings,
      ['hook_unsupported_event_h1_sessionStart'],
    );
  });
}
