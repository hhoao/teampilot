import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/hook_entry.dart';
import 'package:teampilot/models/hook_event.dart';
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
    expect(entries.map((e) => e.event), containsAll([
      HookEvent.permissionRequest,
      HookEvent.preToolUse,
      HookEvent.postToolUse,
      HookEvent.postToolUseFailure,
      HookEvent.stop,
      HookEvent.stopFailure,
      HookEvent.userPromptSubmit,
    ]));
    for (final entry in entries) {
      expect(entry.source, HookSource.managed);
      final http = entry.action as HttpHookAction;
      // URL 事件名与现有 agent-status 一致（PascalCase 原生名），
      // 保证 per-event URL 去重身份与 hook-gate 兼容。
      final native = HookEventCapability.nativeEvent(
        entry.event,
        CliTool.claude,
      );
      expect(http.url, contains('event=$native'));
      expect(http.headers['X-Member'], 'm1');
      expect(entry.timeout, isNotNull);
    }
  });

  test('bus idle hooks are stop + stopFailure with blockOnDecision', () {
    const idle = MemberBusIdleEndpoint(
      url: 'http://127.0.0.1:2/idle',
      token: null,
      sessionId: null,
    );
    final entries = completer.busIdleHooks(idle: idle, memberId: 'm1');
    expect(entries.map((e) => e.event), [HookEvent.stop, HookEvent.stopFailure]);
    expect(entries.every((e) => e.blockOnDecision), isTrue);
  });
}
