import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/hook_entry.dart';
import 'package:teampilot/models/hook_event.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/agent_status/member_agent_status_endpoint.dart';
import 'package:teampilot/services/cli/codex/provider/codex_hook_writer.dart';
import 'package:teampilot/services/cli/codex/provider/codex_toml_parser.dart';
import 'package:teampilot/services/cli/registry/capabilities/hook_capability.dart';
import 'package:teampilot/services/cli/registry/capabilities/runtime_event_capability.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/cli/registry/config_profile/hook_seat_context_completer.dart';
import 'package:teampilot/services/hook/glue_script_builder.dart';
import 'package:teampilot/services/host/host_execution_environment.dart';
import 'package:teampilot/services/host/host_script_dialect.dart';
import 'package:teampilot/services/host/host_script_runner.dart';
import 'package:teampilot/services/storage/runtime_context.dart';
import 'package:teampilot/services/team_bus/member_bus_idle_endpoint.dart';

void main() {
  const writer = CodexHookWriter();
  const ctx = HookRenderContext(
    hooksDir: '/s/hooks',
    runner: null,
    glueBuilder: GlueScriptBuilder(),
  );

  test('shellCommandRequest is supported by codex writer', () {
    expect(writer.supportsEvent(HookEvent.shellCommandRequest), isTrue);
    expect(
      writer.nativeEvent(HookEvent.shellCommandRequest),
      'ShellCommandRequest',
    );
    expect(writer.supportsEvent(HookEvent.preToolUse), isTrue);
  });

  test('renders TOML fragment with [[hooks.Event]] and glue script', () {
    final entry = HookEntry(
      id: 'h1',
      source: HookSource.userLibrary,
      event: HookEvent.stop,
      matcher: null,
      action: CommandHookAction.raw('echo done'),
    );
    final result = writer.render(entries: [entry], ctx: ctx);
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
    final entry = HookEntry(
      id: 'h1',
      source: HookSource.userLibrary,
      event: HookEvent.preToolUse,
      policy: HookPolicy.deny,
      action: CommandHookAction.raw('echo hi'),
    );
    final result = writer.render(entries: [entry], ctx: ctx);
    final glue = result.scripts.single;
    expect(glue.content, contains('"permissionDecision":"deny"'));
  });

  test('managed script missing data yields warning and no fragment', () {
    final entry = HookEntry(
      id: 'h1',
      source: HookSource.userLibrary,
      event: HookEvent.stop,
      action: CommandHookAction.script(
        fileName: 'hook.sh',
        scriptContent: null,
      ),
    );
    final result = writer.render(entries: [entry], ctx: ctx);
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
    final entry = HookEntry(
      id: 'h1',
      source: HookSource.userLibrary,
      event: HookEvent.preToolUse,
      matcher: 'Bash|Read',
      action: CommandHookAction.raw('echo hi'),
    );
    final result = writer.render(entries: [entry], ctx: ctx);
    final toml = result.configFragments['config.toml']! as String;
    expect(toml, contains('matcher = "Bash|Read"'));
    expect(toml, contains('[[hooks.PreToolUse]]'));
  });

  test('all-failed render keeps warnings without fragment', () {
    final entry = HookEntry(
      id: 'h1',
      source: HookSource.userLibrary,
      event: HookEvent.stop,
      action: CommandHookAction.script(
        fileName: 'hook.sh',
        scriptContent: null,
      ),
    );
    final result = writer.render(entries: [entry], ctx: ctx);
    expect(result.warnings, contains('hook_script_missing_h1'));
    expect(result.configFragments, isEmpty);
    expect(result.scripts, isEmpty);
  });

  test('agent-status managed entries render command-hook forward scripts', () {
    const endpoint = MemberAgentStatusEndpoint(
      url: 'http://127.0.0.1:1/agent-status',
      token: 't',
      sessionId: 's',
    );
    final entries = [
      ..._runtimeHooks(endpoint),
      HookEntry(
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
    // codex 只支持 command/prompt/agent 三类 hook；http 必须渲染为 command 转发。
    expect(toml, isNot(contains('type = "http"')));
    expect(toml, contains('type = "command"'));
    // URL 身份 + 请求头移入转发脚本，TOML 只指向脚本路径。
    final preToolUseScript = result.scripts.singleWhere(
      (s) =>
          s.fileName ==
          'teampilot-http-teampilot-runtime-event-preToolUse'
              '-preToolUse.sh',
    );
    expect(preToolUseScript.content, contains('?event=PreToolUse'));
    expect(preToolUseScript.content, contains('-H \'X-Member: m1\''));
    expect(preToolUseScript.content, contains('-H \'X-Session: s\''));
    expect(preToolUseScript.content, contains('-H \'X-Bus-Token: t\''));
    final stopScript = result.scripts.singleWhere(
      (s) =>
          s.fileName == 'teampilot-http-teampilot-runtime-event-stop-stop.sh',
    );
    expect(stopScript.content, contains('?event=Stop'));
    expect(stopScript.content, contains('>/dev/null'));
    // PreToolUse keeps the 1-day AskUserQuestion hold; other events 5s.
    final preToolUseBlock = toml.split('[[hooks.PreToolUse]]')[1];
    expect(preToolUseBlock, contains('timeout = 86400'));
    expect(preToolUseBlock, contains('matcher = "*"'));
    expect(
      preToolUseBlock,
      contains(
        '/teampilot-http-teampilot-runtime-event-preToolUse-preToolUse.sh',
      ),
    );
    final stopBlock = toml.split('[[hooks.Stop]]')[1];
    expect(stopBlock, contains('timeout = 5'));
    expect(stopBlock, isNot(contains('?event=')));
    expect(stopBlock, isNot(contains('matcher')));
    // The 4 matcher-capable events (PermissionRequest/PreToolUse/PostToolUse/
    // PostToolUseFailure) render `matcher = "*"`; Stop has no matcher.
    expect('matcher = "*"'.allMatches(toml).length, 4);
  });

  test('bus-idle managed entries render response-to-stdout stop script', () {
    const completer = HookSeatContextCompleter();
    const idle = MemberBusIdleEndpoint(
      url: 'http://127.0.0.1:1/idle',
      token: 't',
      sessionId: 's',
    );
    final entries = completer.busIdleHooks(idle: idle, memberId: 'm1');
    final result = writer.render(entries: entries, ctx: ctx);
    expect(result.warnings, isEmpty);
    final toml = result.configFragments['config.toml']! as String;
    expect(toml, isNot(contains('type = "http"')));
    expect(toml, contains('[[hooks.Stop]]'));
    expect(toml, contains('[[hooks.StopFailure]]'));
    final script = result.scripts.singleWhere(
      (s) => s.fileName == 'teampilot-http-teampilot-bus-idle-stop-stop.sh',
    );
    // blockOnDecision: POST 响应 (followup/decision) 透传 stdout，不转发 stdin。
    expect(script.content, contains("'http://127.0.0.1:1/idle'"));
    expect(script.content, isNot(contains('\$payload')));
    expect(script.content, isNot(contains('>/dev/null')));
  });

  test('http entry command wrapped by runner when runner set', () {
    const runner = HostScriptRunner(
      HostExecutionEnvironment(
        dialect: HostScriptDialect.bash,
        isWindowsHost: false,
        storageMode: StorageBackendMode.native,
      ),
    );
    const runnerCtx = HookRenderContext(
      hooksDir: '/s/hooks',
      runner: runner,
      glueBuilder: GlueScriptBuilder(),
    );
    const endpoint = MemberAgentStatusEndpoint(url: 'http://127.0.0.1:9/a');
    final entries = _runtimeHooks(endpoint);
    final result = writer.render(entries: entries, ctx: runnerCtx);
    final toml = result.configFragments['config.toml']! as String;
    // Schema gate: everything the writer renders must be loadable by codex —
    // any unsupported hook `type` (e.g. native `http`) fails here.
    expect(CodexTomlParser.invalidHookTypes(toml), isEmpty);
    expect(
      toml,
      contains(
        'command = "bash \\"/s/hooks/'
        'teampilot-http-teampilot-runtime-event-preToolUse-preToolUse.sh\\""',
      ),
    );
  });
}

List<HookEntry> _runtimeHooks(MemberAgentStatusEndpoint endpoint) =>
    CliToolRegistry.builtIn()
        .capability<RuntimeEventCapability>(CliTool.codex)!
        .managedHookEntries(
          RuntimeEventHookContext(endpoint: endpoint, memberId: 'm1'),
        );
