import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/hook_entry.dart';
import 'package:teampilot/models/hook_event.dart';
import 'package:teampilot/models/plugin.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/agent_status/member_agent_status_endpoint.dart';
import 'package:teampilot/services/cli/registry/config_profile/hook_seat_context_completer.dart';
import 'package:teampilot/services/team_bus/member_bus_idle_endpoint.dart';

void main() {
  const completer = HookSeatContextCompleter();

  test('agent status hooks cover all events with per-event urls', () {
    const endpoint = MemberAgentStatusEndpoint(
      url: 'http://127.0.0.1:1/agent-status',
      token: 't',
      sessionId: 's',
    );
    final entries = completer.agentStatusHooks(
      endpoint: endpoint,
      memberId: 'm1',
    );
    expect(entries, hasLength(7));
    expect(
      entries.map((e) => e.event),
      [
        HookEvent.permissionRequest,
        HookEvent.preToolUse,
        HookEvent.postToolUse,
        HookEvent.postToolUseFailure,
        HookEvent.stop,
        HookEvent.stopFailure,
        HookEvent.userPromptSubmit,
      ],
    );
    const matcherEvents = {
      HookEvent.permissionRequest,
      HookEvent.preToolUse,
      HookEvent.postToolUse,
      HookEvent.postToolUseFailure,
    };
    for (final entry in entries) {
      expect(entry.source, HookSource.managed);
      expect(
        entry.matcher,
        matcherEvents.contains(entry.event) ? '*' : null,
      );
      expect(
        entry.timeout,
        entry.event == HookEvent.preToolUse
            ? const Duration(days: 1)
            : const Duration(seconds: 5),
      );
      final http = entry.action as HttpHookAction;
      // URL 事件名与现有 agent-status 一致（PascalCase 原生名），
      // 保证 per-event URL 去重身份与 hook-gate 兼容。
      final native = HookEventCapability.nativeEvent(
        entry.event,
        CliTool.claude,
      );
      expect(http.url, contains('event=$native'));
      expect(http.headers['X-Member'], 'm1');
    }
  });

  test('bus idle hooks are stop + stopFailure with blockOnDecision', () {
    const idle = MemberBusIdleEndpoint(
      url: 'http://127.0.0.1:2/idle',
      token: 't',
      sessionId: 's',
    );
    final entries = completer.busIdleHooks(idle: idle, memberId: 'm1');
    expect(entries.map((e) => e.event), [HookEvent.stop, HookEvent.stopFailure]);
    for (final entry in entries) {
      expect(entry.source, HookSource.managed);
      expect(entry.blockOnDecision, isTrue);
      expect(entry.timeout, const Duration(seconds: 5));
      final http = entry.action as HttpHookAction;
      expect(http.url, idle.url);
      expect(http.headers, {'X-Member': 'm1', 'X-Session': 's', 'X-Bus-Token': 't'});
    }
  });

  test('delegate hooks become managed preToolUse entries', () {
    final entries = completer.delegateHooks(
      commands: ['/s/scripts/team-lead-delegate.sh'],
    );
    expect(entries.single.event, HookEvent.preToolUse);
    expect(entries.single.source, HookSource.managed);
    final cmd = entries.single.action as CommandHookAction;
    expect(cmd.command, '/s/scripts/team-lead-delegate.sh');
  });

  test('extension settings hooks become extension entries', () {
    final entries = completer.extensionHooks(
      extensionId: 'rtk',
      events: const ['PreToolUse', 'UserPromptSubmit'],
      command: 'bash /s/ext-hook.sh',
    );
    expect(entries.map((e) => e.event), [
      HookEvent.preToolUse,
      HookEvent.userPromptSubmit,
    ]);
    expect(entries.first.source, HookSource.extension);
    final cmd = entries.first.action as CommandHookAction;
    expect(cmd.command, 'bash /s/ext-hook.sh');
  });

  test('extension entries carry per-extension ids (collision-safe glue names)',
      () {
    final rtk = completer.extensionHooks(
      extensionId: 'rtk',
      events: const ['PreToolUse'],
      command: 'bash /s/rtk.sh',
    );
    final other = completer.extensionHooks(
      extensionId: 'prompt-boost',
      events: const ['PreToolUse'],
      command: 'bash /s/prompt-boost.sh',
    );
    expect(
      rtk.single.id,
      'teampilot-extension-settings-hook-rtk-PreToolUse',
    );
    expect(
      other.single.id,
      'teampilot-extension-settings-hook-prompt-boost-PreToolUse',
    );
    expect(rtk.single.id, isNot(other.single.id));
  });

  test('plugin hooks become plugin-source entries aligned to PluginHook fields',
      () {
    final entries = completer.pluginHooks(
      hooks: const [
        PluginHook(event: 'Stop', matcher: '.*'),
        PluginHook(event: 'PreToolUse', matcher: 'Bash|Edit'),
        PluginHook(event: 'NotAnEvent', matcher: '.*'),
        PluginHook(event: 'postToolUseFailure', matcher: ''),
      ],
      command: 'bash /s/plugin-hook.sh',
    );
    expect(entries.map((e) => e.event), [
      HookEvent.stop,
      HookEvent.preToolUse,
      HookEvent.postToolUseFailure,
    ]);
    for (final entry in entries) {
      expect(entry.source, HookSource.plugin);
      final cmd = entry.action as CommandHookAction;
      expect(cmd.command, 'bash /s/plugin-hook.sh');
    }
    expect(entries[0].matcher, '.*');
    expect(entries[1].matcher, 'Bash|Edit');
    expect(entries[2].matcher, isNull);
  });
}
