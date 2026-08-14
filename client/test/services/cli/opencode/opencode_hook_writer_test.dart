import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/hook_entry.dart';
import 'package:teampilot/models/hook_event.dart';
import 'package:teampilot/services/cli/opencode/capabilities/config_profile.dart';
import 'package:teampilot/services/cli/opencode/capabilities/opencode_hook_writer.dart';
import 'package:teampilot/services/cli/registry/capabilities/hook_capability.dart';
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

  test('tool.execute matcher registers tool-keyed hook, plain falls back', () {
    const bashEntry = HookEntry(
      id: 'h1',
      source: HookSource.userLibrary,
      event: HookEvent.preToolUse,
      matcher: 'bash',
      action: CommandHookAction.raw('echo hi'),
    );
    const plainEntry = HookEntry(
      id: 'h2',
      source: HookSource.userLibrary,
      event: HookEvent.preToolUse,
      action: CommandHookAction.raw('echo hi2'),
    );
    final result = writer.render(
      entries: const [bashEntry, plainEntry],
      ctx: ctx,
    );
    expect(result.warnings, isEmpty);
    final js = result.scripts
        .singleWhere((s) => s.fileName == 'teampilot-user-hooks.js')
        .content;
    expect(js, contains('"tool.execute.before": async (ev, output)'));
    expect(js, contains('new RegExp("bash")'));
    expect(js, contains('run(["bash","/s/hooks/teampilot-hook-h1.sh"])'));
    expect(js, contains('d.decision === "deny"'));
    expect(js, contains('evt === "tool.execute.before"'));
    expect(js, contains('event: async ({ event })'));
    expect(
      result.scripts.any((s) => s.fileName == 'teampilot-hook-h1.sh'),
      isTrue,
    );
    expect(
      result.scripts.any((s) => s.fileName == 'teampilot-hook-h2.sh'),
      isTrue,
    );
  });

  test('multiple tool-keyed entries on same event emit independent checks',
      () {
    const bashEntry = HookEntry(
      id: 'h1',
      source: HookSource.userLibrary,
      event: HookEvent.preToolUse,
      matcher: 'bash',
      action: CommandHookAction.raw('echo a'),
    );
    const readEntry = HookEntry(
      id: 'h2',
      source: HookSource.userLibrary,
      event: HookEvent.preToolUse,
      matcher: 'read',
      action: CommandHookAction.raw('echo b'),
    );
    final result = writer.render(
      entries: const [bashEntry, readEntry],
      ctx: ctx,
    );
    final js = result.scripts
        .singleWhere((s) => s.fileName == 'teampilot-user-hooks.js')
        .content;
    expect(js, contains('new RegExp("bash")'));
    expect(js, contains('new RegExp("read")'));
    expect(js, contains('/s/hooks/teampilot-hook-h1.sh'));
    expect(js, contains('/s/hooks/teampilot-hook-h2.sh'));
  });

  test('matcher on non-tool.execute event warns and is ignored', () {
    const entry = HookEntry(
      id: 'h1',
      source: HookSource.userLibrary,
      event: HookEvent.stop,
      matcher: 'bash',
      action: CommandHookAction.raw('echo hi'),
    );
    final result = writer.render(entries: const [entry], ctx: ctx);
    expect(result.warnings, ['hook_matcher_ignored_h1_stop']);
    final js = result.scripts
        .singleWhere((s) => s.fileName == 'teampilot-user-hooks.js')
        .content;
    expect(js, isNot(contains('"tool.execute.')));
    expect(js, contains('evt === "session.idle"'));
  });

  test('non-tool subscriptions use event hook filtering by event type', () {
    const stopEntry = HookEntry(
      id: 'h1',
      source: HookSource.userLibrary,
      event: HookEvent.stop,
      action: CommandHookAction.raw('echo hi'),
    );
    const promptEntry = HookEntry(
      id: 'h2',
      source: HookSource.userLibrary,
      event: HookEvent.userPromptSubmit,
      action: CommandHookAction.raw('echo hi2'),
    );
    final result = writer.render(
      entries: const [stopEntry, promptEntry],
      ctx: ctx,
    );
    final js = result.scripts
        .singleWhere((s) => s.fileName == 'teampilot-user-hooks.js')
        .content;
    expect(js, contains('event: async ({ event })'));
    expect(js, contains('const evt = event?.type || event?.data?.type;'));
    expect(js, contains('evt === "session.idle"'));
    expect(js, contains('evt === "chat.message"'));
    expect(js, contains('run(["bash","/s/hooks/teampilot-hook-h1.sh"])'));
    expect(js, contains('run(["bash","/s/hooks/teampilot-hook-h2.sh"])'));
    expect(js, isNot(contains('input.client?.events?.on')));
  });

  test('multiple hooks on same native event all fire, no early return', () {
    const first = HookEntry(
      id: 'h1',
      source: HookSource.userLibrary,
      event: HookEvent.stop,
      action: CommandHookAction.raw('echo a'),
    );
    const second = HookEntry(
      id: 'h2',
      source: HookSource.userLibrary,
      event: HookEvent.stop,
      action: CommandHookAction.raw('echo b'),
    );
    final result = writer.render(entries: const [first, second], ctx: ctx);
    final js = result.scripts
        .singleWhere((s) => s.fileName == 'teampilot-user-hooks.js')
        .content;
    expect(js, contains('evt === "session.idle"'));
    expect(js, contains('/s/hooks/teampilot-hook-h1.sh'));
    expect(js, contains('/s/hooks/teampilot-hook-h2.sh'));
    // 累积链：无提前 return，两条分支都写 `last`，链尾统一返回。
    expect(js, isNot(contains('return out ? JSON.parse(out)')));
    expect(js, contains('last = JSON.parse(out)'));
    expect(js, contains('return last || {}'));
    expect(js.split('if (evt === "session.idle")').length - 1, 2,
        reason: 'both subscriptions must emit an if branch');
  });

  test('spaced script path renders as single argv element', () {
    const spacedCtx = HookRenderContext(
      hooksDir: '/home/John Doe/s/hooks',
      runner: null,
      glueBuilder: GlueScriptBuilder(),
    );
    const entry = HookEntry(
      id: 'h1',
      source: HookSource.userLibrary,
      event: HookEvent.userPromptSubmit,
      action: CommandHookAction.raw('echo hi'),
    );
    final result = writer.render(entries: const [entry], ctx: spacedCtx);
    final js = result.scripts
        .singleWhere((s) => s.fileName == 'teampilot-user-hooks.js')
        .content;
    expect(
      js,
      contains(
        'run(["bash","/home/John Doe/s/hooks/teampilot-hook-h1.sh"])',
      ),
    );
  });

  test('matcher regex escapes backslashes before quotes', () {
    const entry = HookEntry(
      id: 'h1',
      source: HookSource.userLibrary,
      event: HookEvent.preToolUse,
      matcher: r'\b(rm|mv)\b',
      action: CommandHookAction.raw('echo hi'),
    );
    final result = writer.render(entries: const [entry], ctx: ctx);
    final js = result.scripts
        .singleWhere((s) => s.fileName == 'teampilot-user-hooks.js')
        .content;
    expect(js, contains(r'new RegExp("\\b(rm|mv)\\b")'));
  });

  test('user hooks plugin coexists with agent-status/idle plugin entries', () {
    var config = const <String, Object?>{'plugin': ['./teampilot-agent-status.js']};
    config = mergeOpencodePluginEntries(config, ['./teampilot-user-hooks.js']);
    expect(config['plugin'], [
      './teampilot-agent-status.js',
      './teampilot-user-hooks.js',
    ]);
    final mergedAgain =
        mergeOpencodePluginEntries(config, ['./teampilot-user-hooks.js']);
    expect(mergedAgain['plugin'], config['plugin']);
  });
}
