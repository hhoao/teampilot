import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/hook_entry.dart';
import 'package:teampilot/models/hook_event.dart';
import 'package:teampilot/services/agent_status/member_agent_status_endpoint.dart';
import 'package:teampilot/services/cli/codex/provider/codex_hook_writer.dart';
import 'package:teampilot/services/cli/registry/capabilities/hook_writer_capability.dart';
import 'package:teampilot/services/cli/registry/config_profile/hook_seat_context_completer.dart';
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

  test('managed script missing data yields warning and no fragment', () {
    const entry = HookEntry(
      id: 'h1',
      source: HookSource.userLibrary,
      event: HookEvent.stop,
      action: CommandHookAction.script(
        fileName: 'hook.sh',
        scriptContent: null,
      ),
    );
    final result = writer.render(entries: const [entry], ctx: ctx);
    expect(result.warnings, contains('hook_script_missing_h1'));
    expect(result.configFragments['config.toml'], isNull);
    expect(result.scripts, isEmpty);
  });

  test('empty entries render nothing', () {
    final result = writer.render(entries: const [], ctx: ctx);
    expect(result.configFragments, isEmpty);
    expect(result.scripts, isEmpty);
    expect(result.warnings, isEmpty);
  });

  test('matcher is rendered into the TOML fragment', () {
    const entry = HookEntry(
      id: 'h1',
      source: HookSource.userLibrary,
      event: HookEvent.preToolUse,
      matcher: 'Bash|Read',
      action: CommandHookAction.raw('echo hi'),
    );
    final result = writer.render(entries: const [entry], ctx: ctx);
    final toml = result.configFragments['config.toml']! as String;
    expect(toml, contains('matcher = "Bash|Read"'));
    expect(toml, contains('[[hooks.PreToolUse]]'));
  });

  test('all-failed render keeps warnings without fragment', () {
    const entry = HookEntry(
      id: 'h1',
      source: HookSource.userLibrary,
      event: HookEvent.stop,
      action: CommandHookAction.script(
        fileName: 'hook.sh',
        scriptContent: null,
      ),
    );
    final result = writer.render(entries: const [entry], ctx: ctx);
    expect(result.warnings, contains('hook_script_missing_h1'));
    expect(result.configFragments, isEmpty);
    expect(result.scripts, isEmpty);
  });

  test('agent-status managed entries render http hooks with headers', () {
    const completer = HookSeatContextCompleter();
    const endpoint = MemberAgentStatusEndpoint(
      url: 'http://127.0.0.1:1/agent-status',
      token: 't',
      sessionId: 's',
    );
    final entries = [
      ...completer.agentStatusHooks(endpoint: endpoint, memberId: 'm1'),
      const HookEntry(
        id: 'h1',
        source: HookSource.userLibrary,
        event: HookEvent.stop,
        action: CommandHookAction.raw('echo done'),
      ),
    ];
    final result = writer.render(entries: entries, ctx: ctx);
    expect(result.warnings, isEmpty);
    final toml = result.configFragments['config.toml']! as String;
    expect(toml, contains('[[hooks.Stop]]'));
    expect(toml, contains('type = "http"'));
    expect(toml, contains('type = "command"'));
    expect(toml, contains('?event=PreToolUse'));
    expect(toml, contains('"X-Member" = "m1"'));
    // PreToolUse keeps the 1-day AskUserQuestion hold; other events 5s.
    final preToolUseBlock = toml.split('[[hooks.PreToolUse]]')[1];
    expect(preToolUseBlock, contains('timeout = 86400'));
    expect(preToolUseBlock, contains('matcher = "*"'));
    final stopBlock = toml.split('[[hooks.Stop]]')[1];
    expect(stopBlock, contains('timeout = 5'));
    expect(stopBlock, contains('?event=Stop'));
    expect(stopBlock, isNot(contains('matcher')));
    // The 4 matcher-capable events (PermissionRequest/PreToolUse/PostToolUse/
    // PostToolUseFailure) render `matcher = "*"`; Stop has no matcher.
    expect(
      'matcher = "*"'.allMatches(toml).length,
      4,
    );
  });
}
