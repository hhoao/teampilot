import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/hook_entry.dart';
import 'package:teampilot/models/hook_event.dart';
import 'package:teampilot/services/cli/codex/provider/codex_hook_writer.dart';
import 'package:teampilot/services/cli/registry/capabilities/hook_writer_capability.dart';
import 'package:teampilot/services/hook/glue_script_builder.dart';

void main() {
  const writer = CodexHookWriter();
  const ctx = HookRenderContext(
    hooksDir: '/s/hooks',
    runner: null,
    glueBuilder: GlueScriptBuilder(),
  );

  test('shellCommandRequest is supported by codex writer', () {
    expect(writer.supportsEvent(HookEvent.shellCommandRequest), isTrue);
    expect(writer.nativeEvent(HookEvent.shellCommandRequest),
        'ShellCommandRequest');
    expect(writer.supportsEvent(HookEvent.preToolUse), isTrue);
  });

  test('renders TOML fragment with [[hooks.Event]] and glue script', () {
    const entry = HookEntry(
      id: 'h1',
      source: HookSource.userLibrary,
      event: HookEvent.stop,
      matcher: null,
      action: CommandHookAction.raw('echo done'),
    );
    final result = writer.render(entries: const [entry], ctx: ctx);
    expect(result.warnings, isEmpty);
    final toml = result.configFragments['config.toml']! as String;
    expect(toml, contains('[[hooks.Stop]]'));
    expect(toml, contains('type = "command"'));
    expect(toml, contains('/s/hooks/teampilot-hook-h1.sh'));
    expect(
      result.scripts.singleWhere((s) => s.fileName == 'teampilot-hook-h1.sh'),
      isNotNull,
    );
  });

  test('policy deny injects decision JSON into glue', () {
    const entry = HookEntry(
      id: 'h1',
      source: HookSource.userLibrary,
      event: HookEvent.preToolUse,
      policy: HookPolicy.deny,
      action: CommandHookAction.raw('echo hi'),
    );
    final result = writer.render(entries: const [entry], ctx: ctx);
    final glue = result.scripts.single;
    expect(glue.content, contains('"permissionDecision":"deny"'));
  });

  test('unsupported event is skipped with warning', () {
    const entry = HookEntry(
      id: 'h1',
      source: HookSource.userLibrary,
      event: HookEvent.notification,
      action: CommandHookAction.raw('echo hi'),
    );
    // notification 是 codex 支持的事件：产物非空、无警告。
    final result = writer.render(entries: const [entry], ctx: ctx);
    expect(result.warnings, isEmpty);
    expect(result.configFragments['config.toml'], isNotNull);
  });
}
